# Phase 2: Background Jobs + Polling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the background job pipeline: `LinkIntakeJob` (add URL → extract → create source + items → broadcast), `SourcePollJob` (per-source polling with domain mutex), `SourcePollSweepJob` (hourly recurring sweep), plus supporting infrastructure (ChannelResolver, DomainMutex, queue config, error tracking migration, Procfile.dev worker).

**Architecture:** Extractor registry dispatches to site-specific extractors. `LinkIntakeJob` classifies URLs, resolves YouTube channels to RSS feed URLs, creates Source + Follow + Items, and broadcasts results via Turbo Streams. `SourcePollSweepJob` runs hourly via Solid Queue recurring tasks, enqueuing `SourcePollJob` per due source. `SourcePollJob` acquires a per-domain mutex (via Rails.cache) before fetching, dispatches to the extractor, upserts items (dedup-safe), and recalculates the adaptive `next_crawl_at`. Single retry on failure, then record error on source and discard.

**Tech Stack:** Rails 8.1, Ruby 4.0.5, Solid Queue (recurring tasks + named queues), Solid Cable (Turbo Stream broadcasts), Solid Cache (domain mutex), `full_search` gem (FTS5, already wired), faraday + feedjira + nokogiri (already in Gemfile from Phase 1 gems task).

**Spec:** `docs/superpowers/specs/2026-08-13-extractor-design.md` — Phase 2 section

**Prerequisite:** This plan assumes the Phase 1 extractor subsystem (`lib/stray/extractor.rb`, `lib/stray/extractor_registry.rb`, `lib/stray/yt_dlp/runner.rb`, `lib/stray/extractors/youtube_rss.rb`, `lib/stray/extractors/yt_dlp.rb`, `config/initializers/extractors.rb`, Dockerfile yt-dlp) has been implemented. The data layer (migrations + models) is already done. If any Phase 1 extractor code is missing, complete those tasks from the Phase 1 plan before starting this plan.

---

## File Map

### Jobs (app/jobs/)
- `app/jobs/link_intake_job.rb` — classify URL, extract, create source+items, broadcast
- `app/jobs/source_poll_job.rb` — per-source poll with domain mutex, upsert items, recalculate cadence
- `app/jobs/source_poll_sweep_job.rb` — recurring sweep, enqueue poll jobs for due sources

### Supporting libs (lib/stray/)
- `lib/stray/youtube/channel_resolver.rb` — resolve YouTube channel URL → channel_id + RSS feed URL
- `lib/stray/domain_mutex.rb` — per-domain mutex via Rails.cache

### Config
- `config/queue.yml` — add `:polling` queue with 1 thread
- `config/recurring.yml` — add `source_poll_sweep` hourly entry
- `Procfile.dev` — add `worker: bin/jobs`

### Migration
- `db/migrate/YYYYMMDDHHMMSS_add_error_tracking_to_sources.rb` — `last_error`, `last_error_at` columns

### Tests
- `test/jobs/link_intake_job_test.rb`
- `test/jobs/source_poll_job_test.rb`
- `test/jobs/source_poll_sweep_job_test.rb`
- `test/lib/stray/youtube/channel_resolver_test.rb`
- `test/lib/stray/domain_mutex_test.rb`

---

## Task 1: Add error tracking migration to sources

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_error_tracking_to_sources.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration AddErrorTrackingToSources last_error:string last_error_at:datetime`
Expected: creates migration file.

- [ ] **Step 2: Verify migration content**

```ruby
class AddErrorTrackingToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :last_error, :string
    add_column :sources, :last_error_at, :datetime
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: migration succeeds.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_add_error_tracking_to_sources.rb db/schema.rb
git commit -m "feat: add error tracking columns to sources"
```

---

## Task 2: DomainMutex — per-domain fetch lock

**Files:**
- Create: `lib/stray/domain_mutex.rb`
- Create: `test/lib/stray/domain_mutex_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Stray::DomainMutexTest < ActiveSupport::TestCase
  test "acquires lock and yields block" do
    executed = false
    Stray::DomainMutex.with_lock("example.com") do
      executed = true
      assert Rails.cache.exist?("stray:domain_lock:example.com")
    end
    assert executed
    assert_not Rails.cache.exist?("stray:domain_lock:example.com")
  end

  test "releases lock even on exception" do
    assert_raises(StandardError) do
      Stray::DomainMutex.with_lock("example.com") do
        raise StandardError, "boom"
      end
    end
    assert_not Rails.cache.exist?("stray:domain_lock:example.com")
  end

  test "raises LockTimeout when lock already held" do
    Rails.cache.write("stray:domain_lock:example.com", Process.pid, expires_in: 5.minutes)

    assert_raises(Stray::DomainMutex::LockTimeout) do
      Stray::DomainMutex.with_lock("example.com", timeout: 0.seconds) do
        # never reached
      end
    end
  ensure
    Rails.cache.delete("stray:domain_lock:example.com")
  end

  test "extracts domain from URL" do
    assert_equal "example.com", Stray::DomainMutex.domain_for("https://www.example.com/path?q=1")
    assert_equal "bitchute.com", Stray::DomainMutex.domain_for("https://bitchute.com/video/abc")
    assert_nil Stray::DomainMutex.domain_for("not a url")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/domain_mutex_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::DomainMutex`

- [ ] **Step 3: Write DomainMutex**

```ruby
require "uri"

module Stray
  class DomainMutex
    LOCK_PREFIX = "stray:domain_lock:"
    DEFAULT_TIMEOUT = 10.seconds
    LOCK_TTL = 5.minutes

    class LockTimeout < StandardError; end

    class << self
      def with_lock(domain, timeout: DEFAULT_TIMEOUT)
        return yield if domain.nil?

        key = lock_key(domain)
        acquire(key, timeout)
        begin
          yield
        ensure
          release(key)
        end
      end

      def domain_for(url)
        URI.parse(url).host
      rescue URI::InvalidURIError
        nil
      end

      private

      def lock_key(domain)
        "#{LOCK_PREFIX}#{domain}"
      end

      def acquire(key, timeout)
        deadline = Time.current + timeout
        loop do
          if Rails.cache.write(key, Process.pid, expires_in: LOCK_TTL, unless_exist: true)
            return
          end
          raise LockTimeout if Time.current >= deadline

          sleep 1
        end
      end

      def release(key)
        owner = Rails.cache.read(key)
        Rails.cache.delete(key) if owner == Process.pid
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/domain_mutex_test.rb`
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/domain_mutex.rb test/lib/stray/domain_mutex_test.rb
git commit -m "feat: add DomainMutex for per-domain fetch locking"
```

---

## Task 3: YouTube ChannelResolver — direct /channel/UC... parsing

**Files:**
- Create: `lib/stray/youtube/channel_resolver.rb`
- Create: `test/lib/stray/youtube/channel_resolver_test.rb`

- [ ] **Step 1: Write the failing test for /channel/UC... URLs**

```ruby
require "test_helper"

class Stray::Youtube::ChannelResolverTest < ActiveSupport::TestCase
  test "resolves /channel/UC... URL directly without subprocess" do
    result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw")

    assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
    assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_url
    assert_nil result.channel_name
  end

  test "raises for non-YouTube URLs" do
    assert_raises(ArgumentError) do
      Stray::Youtube::ChannelResolver.resolve("https://bitchute.com/channel/abc")
    end
  end

  test "raises for YouTube video URLs" do
    assert_raises(ArgumentError) do
      Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/youtube/channel_resolver_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::Youtube::ChannelResolver`

- [ ] **Step 3: Write ChannelResolver with /channel/UC... support**

```ruby
require "uri"

module Stray
  module Youtube
    class ChannelResolver
      Result = Data.define(:channel_id, :rss_url, :channel_name, :channel_url)

      RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="

      class << self
        def resolve(url)
          uri = URI.parse(url)
          raise ArgumentError, "Not a YouTube URL" unless youtube?(uri)
          raise ArgumentError, "Not a channel URL" if video_url?(uri)

          channel_id = extract_channel_id(uri)
          raise ArgumentError, "Could not extract channel ID from URL" unless channel_id

          Result.new(
            channel_id:,
            rss_url: "#{RSS_BASE}#{channel_id}",
            channel_name: nil,
            channel_url: uri.to_s
          )
        end

        def build_rss_url(channel_id)
          "#{RSS_BASE}#{channel_id}"
        end

        private

        def youtube?(uri)
          uri.host&.end_with?("youtube.com") || uri.host == "youtu.be"
        end

        def video_url?(uri)
          (uri.host == "youtu.be" && uri.path.present?) ||
            (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
        end

        def extract_channel_id(uri)
          if uri.path&.start_with?("/channel/")
            uri.path.match(%r{/channel/(UC[a-zA-Z0-9_-]+)})&.captures&.first
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/youtube/channel_resolver_test.rb`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/youtube/channel_resolver.rb test/lib/stray/youtube/channel_resolver_test.rb
git commit -m "feat: add YouTube ChannelResolver with /channel/UC... parsing"
```

---

## Task 4: ChannelResolver — handle/@handle/c/user URL resolution via yt-dlp

**Files:**
- Modify: `lib/stray/youtube/channel_resolver.rb`
- Modify: `test/lib/stray/youtube/channel_resolver_test.rb`

- [ ] **Step 1: Add tests for handle resolution**

Add these tests to `Stray::Youtube::ChannelResolverTest`:

```ruby
  test "resolves /@handle URL via yt-dlp" do
    json = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }.to_json

    runner = mock_runner(json)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/@RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
      assert_equal "Rick Astley", result.channel_name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_url
    end
  end

  test "resolves /c/name URL via yt-dlp" do
    json = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }.to_json

    runner = mock_runner(json)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/c/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "Rick Astley", result.channel_name
    end
  end

  test "resolves /user/name URL via yt-dlp" do
    json = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }.to_json

    runner = mock_runner(json)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/user/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    end
  end

  private

  def mock_runner(json_response)
    runner = Minitest::Mock.new
    runner.expect(:single_video, JSON.parse(json_response), [ String ])
    runner
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/youtube/channel_resolver_test.rb`
Expected: FAIL — handle/c/user URLs not handled yet (raises `ArgumentError: Could not extract channel ID`).

- [ ] **Step 3: Update ChannelResolver to handle handle/c/user URLs**

Update the `extract_channel_id` method and add a `needs_resolution?` check:

```ruby
require "uri"

module Stray
  module Youtube
    class ChannelResolver
      Result = Data.define(:channel_id, :rss_url, :channel_name, :channel_url)

      RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="

      class << self
        def resolve(url)
          uri = URI.parse(url)
          raise ArgumentError, "Not a YouTube URL" unless youtube?(uri)
          raise ArgumentError, "Not a channel URL" if video_url?(uri)

          if direct_channel_id?(uri)
            resolve_direct(uri)
          else
            resolve_via_ytdlp(uri)
          end
        end

        def build_rss_url(channel_id)
          "#{RSS_BASE}#{channel_id}"
        end

        private

        def youtube?(uri)
          uri.host&.end_with?("youtube.com") || uri.host == "youtu.be"
        end

        def video_url?(uri)
          (uri.host == "youtu.be" && uri.path.present? && !uri.path.start_with?("/channel/", "/@")) ||
            (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
        end

        def direct_channel_id?(uri)
          uri.path&.start_with?("/channel/UC")
        end

        def resolve_direct(uri)
          channel_id = uri.path.match(%r{/channel/(UC[a-zA-Z0-9_-]+)})&.captures&.first
          raise ArgumentError, "Could not extract channel ID from URL" unless channel_id

          Result.new(
            channel_id:,
            rss_url: build_rss_url(channel_id),
            channel_name: nil,
            channel_url: uri.to_s
          )
        end

        def resolve_via_ytdlp(uri)
          data = Stray::YtDlp::Runner.new.single_video(uri.to_s)

          channel_id = data["channel_id"]
          raise ArgumentError, "yt-dlp did not return a channel_id" unless channel_id

          Result.new(
            channel_id:,
            rss_url: build_rss_url(channel_id),
            channel_name: data["channel"],
            channel_url: data["channel_url"] || uri.to_s
          )
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/youtube/channel_resolver_test.rb`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/youtube/channel_resolver.rb test/lib/stray/youtube/channel_resolver_test.rb
git commit -m "feat: add handle/c/user URL resolution via yt-dlp to ChannelResolver"
```

---

## Task 5: SourcePollJob — dispatch to extractor and upsert items

**Files:**
- Create: `app/jobs/source_poll_job.rb`
- Create: `test/jobs/source_poll_job_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class SourcePollJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @source = Source.create!(
      user: @user,
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123"
    )
    @extractor = Minitest::Mock.new
  end

  def teardown
    @extractor.verify
  end

  test "performs poll: extracts items, upserts, recalculates cadence" do
    contents = [
      Stray::ExtractedContent.new(
        title: "Video 1", content_text: "Desc 1", content_html: nil,
        thumbnail_url: "https://example.com/t1.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120, creator_identity: nil
      ),
      Stray::ExtractedContent.new(
        title: "Video 2", content_text: "Desc 2", content_html: nil,
        thumbnail_url: "https://example.com/t2.jpg", published_at: 2.days.ago,
        external_id: "vid2", duration: 180, creator_identity: nil
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
      Stray::DomainMutex.stub(:with_lock, ->(_domain) { yield }) do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal 2, @source.items.count
    assert_equal "Video 1", @source.items.find_by(external_id: "vid1").title
    assert_equal "Video 2", @source.items.find_by(external_id: "vid2").title
    assert_not_nil @source.last_polled_at
    assert_not_nil @source.next_crawl_at
    assert_nil @source.last_error
  end

  test "does not create duplicate items on re-poll" do
    @source.items.create!(
      user: @user, external_id: "vid1", title: "Old Title", url: "https://example.com/v1",
      published_at: 1.day.ago
    )

    contents = [
      Stray::ExtractedContent.new(
        title: "New Title", content_text: "Updated", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "vid1", duration: nil, creator_identity: nil
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
      Stray::DomainMutex.stub(:with_lock, ->(_domain) { yield }) do
        SourcePollJob.perform_now(@source.id)
      end
    end

    assert_equal 1, @source.items.count
    assert_equal "New Title", @source.items.find_by(external_id: "vid1").title
  end

  test "records error on extraction failure" do
    @extractor.expect(:extract, ->(*) { raise Stray::YtDlp::ExtractionFailed, "yt-dlp failed" }, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
      Stray::DomainMutex.stub(:with_lock, ->(_domain) { yield }) do
        assert_raises(Stray::YtDlp::ExtractionFailed) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end

    @source.reload
    assert_equal "yt-dlp failed", @source.last_error
    assert_not_nil @source.last_error_at
  end

  test "skips non-existent source gracefully" do
    assert_nothing_raised do
      SourcePollJob.perform_now(99999)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: FAIL with `NameError: uninitialized constant SourcePollJob`

- [ ] **Step 3: Write SourcePollJob**

```ruby
class SourcePollJob < ApplicationJob
  queue_as :polling

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  discard_on Stray::YtDlp::Error do |job, error|
    source = Source.find_by(id: job.arguments.first)
    return unless source

    source.update!(last_error: error.message, last_error_at: Time.current)
  end

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source&.active?

    domain = Stray::DomainMutex.domain_for(source.url)

    Stray::DomainMutex.with_lock(domain) do
      extract_and_persist(source)
    end
  end

  private

  def extract_and_persist(source)
    extractor = Stray::ExtractorRegistry.find_for(source.url)
    raise Stray::YtDlp::ExtractionFailed, "No extractor found for #{source.url}" unless extractor

    contents = extractor.extract(source.url)
    contents = Array(contents)

    upsert_items(source, contents)
    source.recalculate_next_crawl!
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil)
  end

  def upsert_items(source, contents)
    return if contents.empty?

    rows = contents.map do |content|
      {
        source_id: source.id,
        user_id: source.user_id,
        external_id: content.external_id,
        title: content.title,
        url: build_item_url(source, content),
        content_text: content.content_text,
        content_html: content.content_html,
        thumbnail_url: content.thumbnail_url,
        duration: content.duration,
        published_at: content.published_at,
        fetched_at: Time.current,
        state: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    Item.upsert_all(rows, unique_by: [:source_id, :external_id])
  end

  def build_item_url(source, content)
    return content.external_id if content.external_id&.start_with?("http")

    case source.kind
    when "youtube_channel"
      "https://www.youtube.com/watch?v=#{content.external_id}"
    else
      "https://example.com/watch/#{content.external_id}"
    end
  end
end
```

Note: `build_item_url` constructs the item's canonical URL from the external_id. For YouTube, `external_id` is the video ID (`dQw4w9WgXcQ`) → `https://www.youtube.com/watch?v=dQw4w9WgXcQ`. The extractor's `ExtractedContent` doesn't carry the full URL for RSS entries (the entry URL is in the feed, but the `external_id` is the video ID). If the extractor already provides a full URL, adjust the struct to include it. For now, this constructs it from the source kind + external_id.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/source_poll_job.rb test/jobs/source_poll_job_test.rb
git commit -m "feat: add SourcePollJob with extractor dispatch and item upsert"
```

---

## Task 6: SourcePollSweepJob — recurring hourly sweep

**Files:**
- Create: `app/jobs/source_poll_sweep_job.rb`
- Create: `test/jobs/source_poll_sweep_job_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class SourcePollSweepJobTest < ActiveJob::TestCase
  test "enqueues SourcePollJob for due sources only" do
    due_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC1",
      external_id: "UC1", next_crawl_at: 1.hour.ago
    )
    not_due_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC2",
      external_id: "UC2", next_crawl_at: 1.hour.from_now
    )
    inactive_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC3",
      external_id: "UC3", next_crawl_at: 1.hour.ago, active: false
    )

    assert_enqueued_with(job: SourcePollJob, args: [ due_source.id ]) do
      SourcePollSweepJob.perform_now
    end

    assert_no_enqueued_jobs(only: [ SourcePollJob, args: [ not_due_source.id ] ])
    assert_no_enqueued_jobs(only: [ SourcePollJob, args: [ inactive_source.id ] })
  end

  test "handles empty due set without error" do
    assert_nothing_raised do
      SourcePollSweepJob.perform_now
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/source_poll_sweep_job_test.rb`
Expected: FAIL with `NameError: uninitialized constant SourcePollSweepJob`

- [ ] **Step 3: Write SourcePollSweepJob**

```ruby
class SourcePollSweepJob < ApplicationJob
  queue_as :default

  def perform
    Source.due_for_poll.in_batches(of: 100) do |batch|
      batch.each do |source|
        SourcePollJob.perform_later(source.id)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/source_poll_sweep_job_test.rb`
Expected: all 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/source_poll_sweep_job.rb test/jobs/source_poll_sweep_job_test.rb
git commit -m "feat: add SourcePollSweepJob for hourly source polling"
```

---

## Task 7: LinkIntakeJob — classify, extract, create source + items, broadcast

**Files:**
- Create: `app/jobs/link_intake_job.rb`
- Create: `test/jobs/link_intake_job_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class LinkIntakeJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
  end

  test "creates source + follow + items for YouTube channel URL" do
    contents = [
      Stray::ExtractedContent.new(
        title: "Video 1", content_text: "Desc 1", content_html: nil,
        thumbnail_url: "https://example.com/t1.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Test Channel", url: "https://www.youtube.com/channel/UC123",
          external_id: "UC123", thumbnail_url: nil
        )
      )
    ]

    resolver_result = Stray::Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123"
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ resolver_result.rss_url ])

    Stray::Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::ExtractorRegistry.stub(:find_for, extractor, [ resolver_result.rss_url ]) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/channel/UC123")
      end
    end

    source = Source.find_by(external_id: "UC123", user_id: @user.id)
    assert_not_nil source
    assert_equal "youtube_channel", source.kind
    assert_equal resolver_result.rss_url, source.url
    assert_equal "Test Channel", source.name

    assert_not_nil source.follow
    assert_equal 1.0, source.follow.weight

    assert_equal 1, source.items.count
    assert_equal "Video 1", source.items.first.title
  end

  test "creates source + follow + single item for YouTube video URL" do
    video_content = Stray::ExtractedContent.new(
      title: "Test Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "vid123", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Test Channel", url: "https://www.youtube.com/channel/UC123",
        external_id: "UC123", thumbnail_url: nil
      )
    )

    ytdlp_extractor = Minitest::Mock.new
    ytdlp_extractor.expect(:extract, video_content, [ "https://www.youtube.com/watch?v=vid123" ])

    rss_contents = [ video_content ]
    rss_extractor = Minitest::Mock.new
    rss_extractor.expect(:extract, rss_contents, [ "https://www.youtube.com/feeds/videos.xml?channel_id=UC123" ])

    Stray::ExtractorRegistry.stub(:find_for, ->(url) {
      if url.include?("feeds/videos.xml")
        rss_extractor
      else
        ytdlp_extractor
      end
    }) do
      LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/watch?v=vid123")
    end

    source = Source.find_by(external_id: "UC123", user_id: @user.id)
    assert_not_nil source
    assert_equal "youtube_channel", source.kind
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UC123", source.url
    assert_equal 1.0, source.follow.weight
    assert_equal 1, source.items.count
  end

  test "creates source for non-YouTube video URL" do
    content = Stray::ExtractedContent.new(
      title: "Bitchute Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "bcvid123", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "BC Channel", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      )
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/bcvid123" ])

    Stray::ExtractorRegistry.stub(:find_for, extractor) do
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid123")
    end

    source = Source.find_by(external_id: "abc", user_id: @user.id)
    assert_not_nil source
    assert_equal "video_channel", source.kind
    assert_equal "BC Channel", source.name
    assert_equal 1.0, source.follow.weight
    assert_equal 1, source.items.count
  end

  test "broadcasts success via Turbo Stream" do
    content = Stray::ExtractedContent.new(
      title: "Video", content_text: nil, content_html: nil,
      thumbnail_url: nil, published_at: 1.day.ago,
      external_id: "v1", duration: nil,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Chan", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      )
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/v1" ])

    broadcast_called = false
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args) { broadcast_called = true }) do
      Stray::ExtractorRegistry.stub(:find_for, extractor) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/v1")
      end
    end

    assert broadcast_called
  end

  test "broadcasts error on extraction failure" do
    extractor = Minitest::Mock.new
    extractor.expect(:extract, ->(*) { raise Stray::YtDlp::ExtractionFailed, "failed" }, [ "https://bitchute.com/video/v1" ])

    broadcast_called = false
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args) { broadcast_called = true }) do
      Stray::ExtractorRegistry.stub(:find_for, extractor) do
        begin
          LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/v1")
        rescue Stray::YtDlp::ExtractionFailed
          # First attempt raises; retry would be next, but in test we catch it
        end
      end
    end

    # The discard_on handler should broadcast the error
    # In test, retry_on will re-raise on the first attempt since attempts: 2 means 1 retry
    # The broadcast happens in the discard_on block
    # This test verifies broadcast was called during the failed attempt
    assert broadcast_called
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/link_intake_job_test.rb`
Expected: FAIL with `NameError: uninitialized constant LinkIntakeJob`

- [ ] **Step 3: Write LinkIntakeJob**

```ruby
class LinkIntakeJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  discard_on Stray::YtDlp::Error do |job, error|
    user_id = job.arguments.first
    url = job.arguments.second
    broadcast_error(user_id, "Could not add #{url}: #{error.message}")
  end

  def perform(user_id, url)
    @user_id = user_id
    @url = url

    content, source = extract_and_create

    broadcast_success(source, content)
  rescue Stray::YtDlp::Error => e
    broadcast_error(user_id, "Could not add #{url}: #{e.message}")
    raise
  end

  private

  def extract_and_create
    if youtube_channel_url?
      resolve_youtube_channel
    elsif youtube_video_url?
      extract_youtube_video
    else
      extract_generic_video
    end
  end

  def youtube_channel_url?
    uri = URI.parse(@url)
    uri.host&.end_with?("youtube.com") &&
      uri.path&.match?(%r{^/(channel/UC|@|c/|user/)})
  rescue URI::InvalidURIError
    false
  end

  def youtube_video_url?
    uri = URI.parse(@url)
    (uri.host == "youtu.be" && uri.path.present?) ||
      (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
  rescue URI::InvalidURIError
    false
  end

  def resolve_youtube_channel
    result = Stray::Youtube::ChannelResolver.resolve(@url)
    extractor = Stray::ExtractorRegistry.find_for(result.rss_url)
    contents = Array(extractor.extract(result.rss_url))

    source = create_source(
      kind: :youtube_channel,
      url: result.rss_url,
      external_id: result.channel_id,
      name: result.channel_name,
      channel_url: result.channel_url
    )

    create_items(source, contents)
    [ contents, source ]
  end

  def extract_youtube_video
    extractor = Stray::ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    rss_url = Stray::Youtube::ChannelResolver.build_rss_url(creator.external_id)

    source = create_source(
      kind: :youtube_channel,
      url: rss_url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )

    create_items(source, [ content ])
    [ [ content ], source ]
  end

  def extract_generic_video
    extractor = Stray::ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    source = create_source(
      kind: :video_channel,
      url: creator.url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )

    create_items(source, [ content ])
    [ [ content ], source ]
  end

  def create_source(kind:, url:, external_id:, name:, channel_url:)
    source = Source.find_or_create_by!(
      user_id: @user_id,
      external_id: external_id,
      kind: kind
    ) do |s|
      s.url = url
      s.name = name
      s.icon_url = nil
      s.next_crawl_at = 1.hour.from_now
    end

    source.update!(url: url, name: name)

    Follow.find_or_create_by!(user_id: @user_id, source_id: source.id)
    source
  end

  def create_items(source, contents)
    return if contents.empty?

    rows = contents.map do |content|
      {
        source_id: source.id,
        user_id: @user_id,
        external_id: content.external_id,
        title: content.title,
        url: build_item_url(source, content),
        content_text: content.content_text,
        content_html: content.content_html,
        thumbnail_url: content.thumbnail_url,
        duration: content.duration,
        published_at: content.published_at,
        fetched_at: Time.current,
        state: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    Item.upsert_all(rows, unique_by: [:source_id, :external_id])
  end

  def build_item_url(source, content)
    case source.kind
    when "youtube_channel"
      "https://www.youtube.com/watch?v=#{content.external_id}"
    else
      "#{source.url}/video/#{content.external_id}"
    end
  end

  def broadcast_success(source, contents)
    count = Array(contents).size
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{@user_id}_intake",
      target: "intake_status",
      html: "<div id=\"intake_status\" class=\"rounded-lg border p-4\">\n" \
            "  <p class=\"font-semibold\">Following #{source.name || 'channel'}</p>\n" \
            "  <p class=\"text-sm text-gray-500\">#{count} new video#{'s' if count != 1}</p>\n" \
            "</div>"
    )
  end

  def broadcast_error(user_id, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{user_id}_intake",
      target: "intake_status",
      html: "<div id=\"intake_status\" class=\"rounded-lg border border-red-500 p-4\">\n" \
            "  <p class=\"text-red-700\">#{ERB::Util.html_escape(message)}</p>\n" \
            "</div>"
    )
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/link_intake_job_test.rb`
Expected: all 5 tests PASS.

If the error broadcast test fails because `retry_on` catches the error before `rescue` in `perform`, adjust: the `discard_on` handler runs after all retry attempts are exhausted. In test mode with `perform_now`, `retry_on` will raise on the first attempt. The `rescue` in `perform` catches it and broadcasts, then re-raises. The `discard_on` then catches the re-raised error. This means `broadcast_error` may be called twice (once from `rescue`, once from `discard_on`). To avoid double broadcast, remove the `rescue` in `perform` and rely solely on `discard_on`:

```ruby
  def perform(user_id, url)
    @user_id = user_id
    @url = url

    content, source = extract_and_create
    broadcast_success(source, content)
  end
```

The `discard_on` handler handles all error broadcasting. Update the test to expect the error to propagate on first attempt (no rescue in perform), and verify broadcast happens via the discard handler.

- [ ] **Step 5: Fix double-broadcast issue**

Remove the `rescue Stray::YtDlp::Error` block from `perform`. The `discard_on` handler is the single place for error broadcasting:

```ruby
  def perform(user_id, url)
    @user_id = user_id
    @url = url

    content, source = extract_and_create
    broadcast_success(source, content)
  end
```

Update the error test to not expect `rescue` in perform — instead test that after retries are exhausted, `discard_on` broadcasts:

```ruby
  test "broadcasts error on extraction failure after retries exhausted" do
    extractor = Minitest::Mock.new
    extractor.expect(:extract, ->(*) { raise Stray::YtDlp::ExtractionFailed, "failed" }, [ "https://bitchute.com/video/v1" ])

    broadcast_called = false
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*) { broadcast_called = true }) do
      Stray::ExtractorRegistry.stub(:find_for, extractor) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/v1")
      end
    end

    # With retry_on attempts: 2, first attempt raises, retry scheduled
    # perform_now with retry_on will re-raise immediately (no wait in test)
    # discard_on catches the final raise and broadcasts
    assert broadcast_called
  end
```

- [ ] **Step 6: Run tests again**

Run: `bin/rails test test/jobs/link_intake_job_test.rb`
Expected: all 5 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/link_intake_job.rb test/jobs/link_intake_job_test.rb
git commit -m "feat: add LinkIntakeJob with YouTube channel/video and generic video support"
```

---

## Task 8: Configure queue topology — add :polling queue

**Files:**
- Modify: `config/queue.yml`

- [ ] **Step 1: Read current queue.yml**

Run: `cat config/queue.yml` (or use Read tool)
Expected: single worker pool with `queues: "*"`, 3 threads.

- [ ] **Step 2: Update queue.yml to add polling queue**

Replace the workers section to have two worker pools — one for polling (1 thread) and one for default (2 threads):

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "polling"
      threads: 1
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 1
    - queues: "default"
      threads: 2
      processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
      polling_interval: 1

development:
  <<: *default
test:
  <<: *default
production:
  <<: *default
```

- [ ] **Step 3: Verify config loads**

Run: `bin/rails runner "puts SolidQueue::Configuration.new.workers.size"`
Expected: no error. (If this command doesn't work, just verify `bin/rails runner "puts 'OK'"` runs.)

- [ ] **Step 4: Commit**

```bash
git add config/queue.yml
git commit -m "feat: add polling queue with 1 thread, default with 2 threads"
```

---

## Task 9: Configure recurring schedule — add source_poll_sweep

**Files:**
- Modify: `config/recurring.yml`

- [ ] **Step 1: Read current recurring.yml**

Run: use Read tool on `config/recurring.yml`
Expected: production-only entries for `clear_solid_queue_finished_jobs` and `full_search_optimize`.

- [ ] **Step 2: Add source_poll_sweep entry**

Add to the production section:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
  full_search_optimize:
    class: FullSearch::OptimizeJob
    schedule: every day at 3am
  source_poll_sweep:
    class: SourcePollSweepJob
    schedule: every hour at minute 0
```

- [ ] **Step 3: Verify config parses**

Run: `bin/rails runner "puts 'OK'"`
Expected: `OK` — no YAML parse errors.

- [ ] **Step 4: Commit**

```bash
git add config/recurring.yml
git commit -m "feat: add SourcePollSweepJob to hourly recurring schedule"
```

---

## Task 10: Add Solid Queue worker to Procfile.dev

**Files:**
- Modify: `Procfile.dev`

- [ ] **Step 1: Read current Procfile.dev**

Current content:
```
web: bin/rails server
css: bin/rails tailwindcss:watch
```

- [ ] **Step 2: Add worker line**

```
web: bin/rails server
css: bin/rails tailwindcss:watch
worker: bin/jobs
```

- [ ] **Step 3: Verify bin/jobs exists**

Run: `ls -la bin/jobs`
Expected: file exists (Rails 8 generates it). If not, run `bin/rails g solid_queue:install` or check that solid_queue gem is installed.

- [ ] **Step 4: Commit**

```bash
git add Procfile.dev
git commit -m "feat: add Solid Queue worker to Procfile.dev"
```

---

## Task 11: Integration test — full poll cycle with mocked extractor

**Files:**
- Create: `test/integration/source_poll_flow_test.rb`

- [ ] **Step 1: Write integration test**

```ruby
require "test_helper"

class SourcePollFlowTest < ActionDispatch::IntegrationTest
  test "full poll cycle: create source, poll, items appear" do
    user = users(:one)

    source = Source.create!(
      user: user,
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123",
      next_crawl_at: 1.hour.ago
    )

    contents = [
      Stray::ExtractedContent.new(
        title: "Integration Test Video", content_text: "Test description",
        content_html: nil, thumbnail_url: "https://example.com/t.jpg",
        published_at: 1.hour.ago, external_id: "inttest1", duration: 60,
        creator_identity: nil
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ source.url ])

    Stray::ExtractorRegistry.stub(:find_for, extractor, [ source.url ]) do
      Stray::DomainMutex.stub(:with_lock, ->(_domain) { yield }) do
        SourcePollJob.perform_now(source.id)
      end
    end

    source.reload
    assert_equal 1, source.items.count
    assert_equal "Integration Test Video", source.items.first.title
    assert_not_nil source.last_polled_at
    assert_not_nil source.next_crawl_at
    assert source.next_crawl_at > Time.current
  end

  test "sweep enqueues poll jobs for due sources" do
    user = users(:one)

    Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep1",
      external_id: "UCsweep1", next_crawl_at: 1.hour.ago
    )
    Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep2",
      external_id: "UCsweep2", next_crawl_at: 1.hour.ago
    )

    assert_difference -> { enqueued_jobs.size }, 2 do
      SourcePollSweepJob.perform_now
    end

    enqueued_source_polls = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }
    assert_equal 2, enqueued_source_polls.size
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bin/rails test test/integration/source_poll_flow_test.rb`
Expected: 2 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/source_poll_flow_test.rb
git commit -m "test: add integration test for full poll cycle and sweep"
```

---

## Task 12: Commit uncommitted source_test.rb from Phase 1

**Files:**
- `test/models/source_test.rb` (already exists, untracked)

- [ ] **Step 1: Check git status**

Run: `git status`
Expected: `test/models/source_test.rb` shows as untracked.

- [ ] **Step 2: Commit it**

```bash
git add test/models/source_test.rb
git commit -m "test: add Source model tests from Phase 1"
```

---

## Task 13: Final verification — full test suite + lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: all tests PASS (existing + Phase 2).

- [ ] **Step 2: Run RuboCop**

Run: `bin/rubocop`
Expected: no offenses. Fix any and re-run.

- [ ] **Step 3: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: no new warnings.

- [ ] **Step 4: Verify console workflow**

Run: `bin/rails console`

```ruby
# Create a source and poll it (with real extractor if yt-dlp is installed)
s = Source.create!(user: User.first, kind: :youtube_channel, url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", external_id: "UCuAXFkgsw1L7xaCfnd5JJOw")
Follow.create!(user: User.first, source: s)
SourcePollJob.perform_later(s.id)

# Check sweep
SourcePollSweepJob.perform_now

# Check recurring config
puts SolidQueue::Configuration.new.inspect
```

Expected: jobs enqueue without errors.

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint and verification fixes for Phase 2"
```

If no fixes needed, skip.

---

## Long-Term Roadmap (Phases 3-5)

### Phase 3 — Add-link UI + homepage feed (next plan)

**Add-link flow:**
- `SourcesController#new` — URL input form
- `SourcesController#create` — enqueue `LinkIntakeJob`, respond with Turbo Stream "checking..." status
- Client subscribes to `user_#{id}_intake` via Solid Cable — `LinkIntakeJob` broadcasts result
- On success: source card appears; on failure: error + retry

**Homepage:**
- `FeedController#index` replaces `pages#index` as root for authenticated users
- Items from followed sources, reverse-chron, `where.not(state: :hidden)`
- Item cards: thumbnail, title, source name, time, state buttons

**Per-source view:**
- `SourcesController#show` — items for one source, poll status, follow weight + reset

**Item interactions:**
- `ItemsController#update` — PATCH state (seen/saved/hidden), Turbo Stream response
- "Why is this here" expandable

**Routes:**
```ruby
root "feed#index"
resources :sources, only: [:index, :new, :create, :show]
resources :items, only: [:update]
```

### Phase 4 — Tagging + search

**Embedding pipeline:**
- `EmbeddingJob(item_id)` — async, `Stray::Embeddings::Provider` abstraction (NONE/OLLAMA/OPENAI_COMPATIBLE)
- Brute-force cosine similarity in Ruby (`Stray::Embeddings::Cosine`)
- `NONE` provider = no-op (Principle 3: works without AI)

**Zero-shot tagging:**
- `TaggingJob(item_id)` — embed item → cosine against `Tag` embeddings → top-N above threshold → `Tagging` with `source: :ai_embedding`
- Sub-threshold → uncategorized → user tags manually → seeds new tag embedding

**LLM tagging (optional):**
- `LlmTaggingJob(item_id)` — only if `AppConfig.ai_provider.name != "NONE"`
- Small instruct model proposes tags → `Tagging` with `source: :ai_llm`

**Search:**
- FTS5 via `Item.search(query)` (already wired)
- Semantic: embed query → cosine against `Item.embedding` → "related" section
- "Search by meaning" toggle (off by default)

**Tag provenance UI:**
- Colored dots per tag source (blue=ai_embedding, green=ai_llm, gray=user)
- Manual tagging with autocomplete

### Phase 5 — Future adapters

**Generic RSS/Atom** (`Stray::Extractors::RssAtom`):
- `feedjira` (already in Gemfile), `matches?` probes for RSS/Atom content-type or path patterns
- Source kind: `rss_feed`

**Generic page** (`Stray::Extractors::GenericPage`):
- Readability-style extraction, fallback for non-video non-feed URLs
- Source kind: `generic_page`

**GitHub awesome list** (`Stray::Extractors::GithubAwesomeList`):
- Parse README markdown links into items
- `matches?` for `github.com/*/awesome-*` URLs
- Source kind: `github_user` (add to enum)

**Adding a new adapter = new class + one registry line. No core code changes.**

### Future: yt-dlp gem extraction

Once `Stray::YtDlp::Runner` API is stable:
1. Extract `lib/stray/yt_dlp/` → standalone MIT gem (`yt-dlp-rb`)
2. Pure Ruby, zero Rails deps (already enforced in Phase 1)
3. Other Ruby projects can adopt it (including stray_video)
4. Stray's `Stray::Extractors::YtDlp` becomes a thin adapter

---

## Summary

After completing all 13 tasks, Phase 2 delivers:

| Deliverable | Location |
|---|---|
| Error tracking migration | `db/migrate/` |
| DomainMutex (per-domain fetch lock) | `lib/stray/domain_mutex.rb` |
| YouTube ChannelResolver | `lib/stray/youtube/channel_resolver.rb` |
| LinkIntakeJob (classify + extract + broadcast) | `app/jobs/link_intake_job.rb` |
| SourcePollJob (per-source poll + domain mutex) | `app/jobs/source_poll_job.rb` |
| SourcePollSweepJob (hourly recurring sweep) | `app/jobs/source_poll_sweep_job.rb` |
| Queue topology (polling + default queues) | `config/queue.yml` |
| Recurring schedule | `config/recurring.yml` |
| Procfile.dev worker | `Procfile.dev` |
| Full test suite (jobs + integration) | `test/jobs/`, `test/integration/` |

No UI — that's Phase 3. The pipeline is fully functional via `bin/rails console` and `LinkIntakeJob.perform_later(user_id, url)`.
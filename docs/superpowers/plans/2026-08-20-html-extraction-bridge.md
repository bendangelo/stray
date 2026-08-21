# Bridge Abstraction & Generic HTML Extraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Extractor system to `Stray::Bridge` with bridge metadata, add per-source encrypted secrets, a generic-list extractor kind, RSS feed auto-discovery, conditional GET, uniform SSRF protection, and selector-rot alerting — making Stray a community-maintainable bridge ecosystem supporting all sites.

**Architecture:** Mechanical rename of `Extractor` → `Stray::Bridge` (base class, registry, namespace, initializer) preserving the runtime interface and adding metadata class methods. New `GenericListBridge` decomposes HTML list pages (JSON-LD → repeating-element detection). New `SourceSecret` model stores per-source encrypted auth secrets. `PoliteCrawl` gains conditional GET and uniform `UrlGuard`. `Source` gains `consecutive_empty_polls` counter and `degraded` status for rot alerting.

**Tech Stack:** Rails 8, Ruby 4.0.5, SQLite, Minitest, VCR, Nokogiri, Feedjira, Faraday, ActiveRecord Encryption (`encrypts` + `STRAY_ENCRYPTION_KEY`).

**Spec:** `docs/superpowers/specs/2026-08-20-html-extraction-bridge-design.md`

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `app/bridges/stray/bridge.rb` | `Stray::Bridge` base class with runtime interface + metadata | Create (rename from `app/services/extractor.rb`) |
| `lib/stray/bridge_registry.rb` | `Stray::BridgeRegistry` with video fallback | Create (rename from `app/services/extractor_registry.rb`) |
| `lib/stray/bridge/feed_result.rb` | `Stray::Bridge::FeedResult` data class | Create (rename from `app/services/extractor/feed_result.rb`) |
| `app/bridges/*.rb` | Rails-tier bridge adapters (Rumble, Bitchute, etc.) | Create (rename from `app/services/extractors/*.rb`) |
| `lib/stray/bridges/*.rb` | Pure-Ruby bridge cores | Create (rename from `lib/stray/extractors/*.rb`) |
| `app/bridges/hash_mapper.rb` | Hash→ExtractedContent mapping module | Create (rename from `app/services/extractors/hash_mapper.rb`) |
| `app/bridges/generic_list.rb` | New `Bridges::GenericList` — HTML list-page extractor | Create |
| `config/initializers/bridges.rb` | Bridge registration | Create (rename from `config/initializers/extractors.rb`) |
| `app/services/polite_crawl.rb` | Add conditional GET + uniform UrlGuard | Modify |
| `app/services/url_guard.rb` | No change (called from PoliteCrawl now) | — |
| `app/services/url_classifier.rb` | Add `generic_list` routing | Modify |
| `app/services/feed_discovery.rb` | New — `<link rel="alternate">` feed auto-discovery | Create |
| `app/models/source.rb` | Add `generic_list` kind, `degraded` status, `consecutive_empty_polls`, `etag`, `last_modified`, `bridge_class`, `has_many :secrets` | Modify |
| `app/models/source_secret.rb` | New — encrypted per-source auth secrets | Create |
| `app/jobs/source_poll_job.rb` | Use `BridgeRegistry`, hydrate secrets, track empty polls, conditional GET | Modify |
| `app/jobs/link_intake_job.rb` | Use `BridgeRegistry`, add `generic_list` intake | Modify |
| `db/migrate/<ts>_add_generic_list_to_source_kind.rb` | No-op migration documenting enum value 9 | Create |
| `db/migrate/<ts>_add_poll_metadata_to_sources.rb` | Add `consecutive_empty_polls`, `etag`, `last_modified` | Create |
| `db/migrate/<ts>_add_degraded_to_source_status.rb` | No-op migration documenting status enum value 3 | Create |
| `db/migrate/<ts>_create_source_secrets.rb` | `source_secrets` table | Create |
| `test/bridges/**`, `test/lib/stray/bridges/**` | Renamed test files | Create (rename) |
| `test/bridges/generic_list_test.rb` | New | Create |
| `test/models/source_secret_test.rb` | New | Create |
| `test/services/feed_discovery_test.rb` | New | Create |
| `test/services/polite_crawl_test.rb` | Add conditional GET + UrlGuard tests | Modify |
| `test/services/url_classifier_test.rb` | Add generic_list routing tests | Modify |
| `test/services/bridge_registry_test.rb` | Renamed + video fallback test | Create (rename) |
| `test/jobs/source_poll_job_test.rb` | Update `BridgeRegistry` refs + empty-poll + secret tests | Modify |
| `test/jobs/link_intake_job_test.rb` | Update `BridgeRegistry` refs + generic_list intake | Modify |
| `test/fixtures/sources.yml` | Add `generic_list` fixture | Modify |
| `test/fixtures/source_secrets.yml` | New | Create |
| `AGENTS.md` | Update "Extractor" → "Bridge" terminology | Modify |

Order: rename (§1) → video metadata (§2) → RSS politeness (§3) → generic HTML (§4) → governance (§5).

---

## Phase 1 — Bridge Rename & Metadata (§1)

This is a mechanical rename. Do it in one task to avoid a broken intermediate state. The rename preserves all method names (`matches?`, `handles_kind?`, `extract`, `extract_feed`, `enrich_tags`); only the class/module names change.

### Task 1: Create `Stray::Bridge` base class with metadata

**Files:**
- Create: `app/bridges/stray/bridge.rb`
- Delete: `app/services/extractor.rb`

- [ ] **Step 1: Write the new base class**

Create `app/bridges/stray/bridge.rb`:

```ruby
module Stray
  class Bridge
    def self.matches?(url)        = raise NotImplementedError
    def self.handles_kind?(kind)  = false
    def extract(url)              = raise NotImplementedError
    def extract_feed(url)         = raise NotImplementedError
    def enrich_tags(url)          = nil

    def self.trust_level          = :scraped_html
    def self.site_homepage        = nil
    def self.last_tested_against  = nil
    def self.requires_auth?       = false
    def self.secret_fields         = []
    def self.author               = nil
    def self.source_url           = nil
    def self.license              = "AGPL-3.0"
  end
end
```

- [ ] **Step 2: Write the failing test for metadata defaults**

Create `test/bridges/stray/bridge_test.rb`:

```ruby
require "test_helper"

class Stray::BridgeTest < ActiveSupport::TestCase
  test "default trust_level is :scraped_html" do
    assert_equal :scraped_html, Stray::Bridge.trust_level
  end

  test "default requires_auth? is false" do
    assert_not Stray::Bridge.requires_auth?
  end

  test "default secret_fields is empty array" do
    assert_equal [], Stray::Bridge.secret_fields
  end

  test "default license is AGPL-3.0" do
    assert_equal "AGPL-3.0", Stray::Bridge.license
  end

  test "default metadata fields are nil" do
    assert_nil Stray::Bridge.site_homepage
    assert_nil Stray::Bridge.last_tested_against
    assert_nil Stray::Bridge.author
    assert_nil Stray::Bridge.source_url
  end

  test "runtime interface raises NotImplementedError" do
    assert_raises(NotImplementedError) { Stray::Bridge.matches?("x") }
    bridge = Stray::Bridge.new
    assert_raises(NotImplementedError) { bridge.extract("x") }
    assert_raises(NotImplementedError) { bridge.extract_feed("x") }
  end

  test "enrich_tags defaults to nil" do
    assert_nil Stray::Bridge.new.enrich_tags("x")
  end

  test "handles_kind? defaults to false" do
    assert_not Stray::Bridge.handles_kind?("anything")
  end
end
```

- [ ] **Step 3: Run test to verify it passes**

Run: `bin/rails test test/bridges/stray/bridge_test.rb`
Expected: PASS (the class is already written in step 1).

- [ ] **Step 4: Delete the old `Extractor` base class**

```sh
rm app/services/extractor.rb
```

- [ ] **Step 5: Commit**

```sh
git add app/bridges/stray/bridge.rb test/bridges/stray/bridge_test.rb
git rm app/services/extractor.rb
git commit -m "refactor: rename Extractor to Stray::Bridge with metadata

Adds bridge metadata class methods (trust_level, site_homepage,
last_tested_against, requires_auth?, secret_fields, author,
source_url, license) to the base class. Runtime interface unchanged."
```

### Task 2: Create `Stray::BridgeRegistry` with video fallback

**Files:**
- Create: `lib/stray/bridge_registry.rb`
- Delete: `app/services/extractor_registry.rb`

- [ ] **Step 1: Write the new registry**

Create `lib/stray/bridge_registry.rb`:

```ruby
module Stray
  class BridgeRegistry
    @bridges = []

    class << self
      def register(bridge_class)
        @bridges << bridge_class unless @bridges.include?(bridge_class)
      end

      def find_for(url)
        @bridges.find { |klass| klass.matches?(url) }&.new
      end

      def find_for_source(source)
        bridge = @bridges.find { |klass| klass.handles_kind?(source.kind) }&.new
        return bridge if bridge
        return Bridges::YtDlp.new if source.kind == "video_channel"
        nil
      end

      def all
        @bridges.dup
      end

      def reset!
        @bridges = []
      end
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

Create `test/lib/stray/bridge_registry_test.rb`:

```ruby
require "test_helper"

class Stray::BridgeRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Stray::Bridge
    def self.matches?(url)
      URI.parse(url).path == "/feeds/videos.xml"
    rescue URI::InvalidURIError
      false
    end

    def self.handles_kind?(kind)
      kind == "youtube_channel"
    end

    def extract(url)
      Stray::ExtractedContent.new(url: "https://example.com/video", title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end

    def extract_feed(url) = extract(url)
  end

  class FakeYtDlp < Stray::Bridge
    def self.matches?(url) = true
    def self.handles_kind?(kind) = kind == "video_channel"
    def extract(url) = FakeYoutubeRss.new.extract(url)
    def extract_feed(url) = extract(url)
  end

  def setup
    @original = Stray::BridgeRegistry.instance_variable_get(:@bridges)
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    Stray::BridgeRegistry.register(FakeYtDlp)
  end

  def teardown
    Stray::BridgeRegistry.reset!
    @original&.each { |b| Stray::BridgeRegistry.register(b) }
  end

  test "find_for returns first matching bridge" do
    bridge = Stray::BridgeRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYoutubeRss, bridge.class
  end

  test "find_for falls back to universal bridge" do
    bridge = Stray::BridgeRegistry.find_for("https://bitchute.com/video/abc123")
    assert_equal FakeYtDlp, bridge.class
  end

  test "find_for returns nil when nothing matches" do
    Stray::BridgeRegistry.reset!
    assert_nil Stray::BridgeRegistry.find_for("https://example.com")
  end

  test "registration order determines priority" do
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYtDlp)
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    bridge = Stray::BridgeRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYtDlp, bridge.class
  end

  test "find_for_source returns bridge matching source kind" do
    source = Source.new(kind: :youtube_channel, url: "https://example.com")
    assert_equal FakeYoutubeRss, Stray::BridgeRegistry.find_for_source(source).class
  end

  test "find_for_source returns nil when no bridge handles kind" do
    Stray::BridgeRegistry.reset!
    source = Source.new(kind: :generic_page, url: "https://example.com")
    assert_nil Stray::BridgeRegistry.find_for_source(source)
  end

  test "find_for_source falls back to YtDlp for video_channel with no dedicated bridge" do
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    source = Source.new(kind: :video_channel, url: "https://somesite.com/channel/foo")
    assert_nil Stray::BridgeRegistry.find_for_source(source)
  end

  test "find_for_source returns YtDlp for video_channel when YtDlp is registered" do
    source = Source.new(kind: :video_channel, url: "https://somesite.com/channel/foo")
    assert_equal FakeYtDlp, Stray::BridgeRegistry.find_for_source(source).class
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/bridge_registry_test.rb`
Expected: FAIL — `Stray::BridgeRegistry` is an uninitialized constant because the file isn't loaded yet (autoloader doesn't know about `lib/stray/`).

- [ ] **Step 4: Ensure `lib/stray/` is autoloaded**

Check `config/application.rb` for `config.autoload_lib` or `autoload_paths`. If `lib/stray/` is not already autoloaded, add it. Most Rails 8 apps use `config.autoload_lib(ignore: "assets")`. Check the current setting:

```sh
grep -n "autoload_lib\|autoload_paths" config/application.rb
```

If missing, add to `config/application.rb` inside the `class Application` block (if not already present):

```ruby
config.autoload_lib(ignore: %w[assets tasks])
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/bridge_registry_test.rb`
Expected: PASS

- [ ] **Step 6: Delete old registry and commit**

```sh
git rm app/services/extractor_registry.rb
git add lib/stray/bridge_registry.rb test/lib/stray/bridge_registry_test.rb
git commit -m "refactor: rename ExtractorRegistry to Stray::BridgeRegistry

Adds video_channel fallback to YtDlp when no dedicated bridge
handles the kind, making 'add a new video site' require zero new code."
```

### Task 3: Move `FeedResult` to `Stray::Bridge::FeedResult`

**Files:**
- Create: `lib/stray/bridge/feed_result.rb`
- Delete: `app/services/extractor/feed_result.rb`

- [ ] **Step 1: Write the new file**

Create `lib/stray/bridge/feed_result.rb`:

```ruby
module Stray
  class Bridge
    FeedResult = Data.define(:items, :next_cursor, :has_more, :collection_name, :producer_instance_name) do
      def initialize(items:, next_cursor:, has_more: false, collection_name: nil, producer_instance_name: nil)
        super(items: items, next_cursor: next_cursor, has_more: has_more,
              collection_name: collection_name, producer_instance_name: producer_instance_name)
      end
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

Create `test/lib/stray/bridge/feed_result_test.rb`:

```ruby
require "test_helper"

class Stray::Bridge::FeedResultTest < ActiveSupport::TestCase
  test "has items, next_cursor, has_more" do
    item = Stray::ExtractedContent.new(url: "https://x", title: "T", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "x",
      duration: nil, creator_identity: nil, tags: [])
    result = Stray::Bridge::FeedResult.new(items: [ item ], next_cursor: "cur", has_more: true)
    assert_equal [ item ], result.items
    assert_equal "cur", result.next_cursor
    assert result.has_more
  end

  test "has_more defaults to false" do
    result = Stray::Bridge::FeedResult.new(items: [], next_cursor: nil)
    assert_not result.has_more
  end

  test "collection metadata defaults to nil" do
    result = Stray::Bridge::FeedResult.new(items: [], next_cursor: nil)
    assert_nil result.collection_name
    assert_nil result.producer_instance_name
  end

  test "collection metadata can be set" do
    result = Stray::Bridge::FeedResult.new(items: [], next_cursor: nil, collection_name: "Econ", producer_instance_name: "Alice")
    assert_equal "Econ", result.collection_name
    assert_equal "Alice", result.producer_instance_name
  end
end
```

- [ ] **Step 3: Run test, verify pass, delete old, commit**

```sh
bin/rails test test/lib/stray/bridge/feed_result_test.rb
git rm -r app/services/extractor/
git add lib/stray/bridge/feed_result.rb test/lib/stray/bridge/feed_result_test.rb
git commit -m "refactor: move FeedResult to Stray::Bridge::FeedResult"
```

### Task 4: Rename all bridge adapters and update call sites

This is the bulk mechanical rename. Do it in one commit to keep the tree green.

**Files:**
- Move: `app/services/extractors/*.rb` → `app/bridges/*.rb`
- Move: `lib/stray/extractors/*.rb` → `lib/stray/bridges/*.rb`
- Move: `test/services/extractors/*` → `test/bridges/*`
- Move: `test/lib/stray/extractors/*` → `test/lib/stray/bridges/*`
- Modify: `config/initializers/extractors.rb` → `config/initializers/bridges.rb`
- Modify: `app/models/source.rb`, `app/jobs/source_poll_job.rb`, `app/jobs/link_intake_job.rb`, `app/services/url_classifier.rb`, `app/jobs/metadata_enrichment_job.rb`

- [ ] **Step 1: Move and rename adapter files**

```sh
mkdir -p app/bridges lib/stray/bridges test/bridges test/lib/stray/bridges
git mv app/services/extractors/rumble.rb app/bridges/rumble.rb
git mv app/services/extractors/bitchute.rb app/bridges/bitchute.rb
git mv app/services/extractors/odysee.rb app/bridges/odysee.rb
git mv app/services/extractors/peertube.rb app/bridges/peertube.rb
git mv app/services/extractors/youtube_rss.rb app/bridges/youtube_rss.rb
git mv app/services/extractors/rss_atom.rb app/bridges/rss_atom.rb
git mv app/services/extractors/remote_collection.rb app/bridges/remote_collection.rb
git mv app/services/extractors/yt_dlp.rb app/bridges/yt_dlp.rb
git mv app/services/extractors/generic_page.rb app/bridges/generic_page.rb
git mv app/services/extractors/hash_mapper.rb app/bridges/hash_mapper.rb
git mv lib/stray/extractors/rumble.rb lib/stray/bridges/rumble.rb
git mv lib/stray/extractors/bitchute.rb lib/stray/bridges/bitchute.rb
git mv lib/stray/extractors/odysee.rb lib/stray/bridges/odysee.rb
git mv lib/stray/extractors/peertube.rb lib/stray/bridges/peertube.rb
git mv lib/stray/extractors/helpers.rb lib/stray/bridges/helpers.rb
git mv test/services/extractors/generic_page_test.rb test/bridges/generic_page_test.rb
git mv test/services/extractors/rss_atom_test.rb test/bridges/rss_atom_test.rb
git mv test/services/extractors/youtube_rss_test.rb test/bridges/youtube_rss_test.rb
git mv test/services/extractors/yt_dlp_test.rb test/bridges/yt_dlp_test.rb
git mv test/services/extractors/rumble_test.rb test/bridges/rumble_test.rb
git mv test/services/extractors/remote_collection_test.rb test/bridges/remote_collection_test.rb
git mv test/lib/stray/extractors/rumble_test.rb test/lib/stray/bridges/rumble_test.rb
git mv test/lib/stray/extractors/bitchute_test.rb test/lib/stray/bridges/bitchute_test.rb
git mv test/lib/stray/extractors/odysee_test.rb test/lib/stray/bridges/odysee_test.rb
git mv test/lib/stray/extractors/peertube_test.rb test/lib/stray/bridges/peertube_test.rb
git mv test/lib/stray/extractors/helpers_test.rb test/lib/stray/bridges/helpers_test.rb
```

- [ ] **Step 2: Update all `module Extractors` → `module Bridges` and `< Extractor` → `< Stray::Bridge` in every moved adapter**

In every file under `app/bridges/` and `lib/stray/bridges/`, replace:
- `module Extractors` → `module Bridges`
- `< Extractor` → `< Stray::Bridge`
- `Stray::Extractors::` → `Stray::Bridges::`

Also in `app/bridges/hash_mapper.rb`, change `module Extractors` → `module Bridges`.

Also in `app/bridges/remote_collection.rb`, change `Extractor::FeedResult` → `Stray::Bridge::FeedResult`.

- [ ] **Step 3: Create the new initializer**

Create `config/initializers/bridges.rb`:

```ruby
Rails.application.config.to_prepare do
  Stray::BridgeRegistry.reset!
  Stray::BridgeRegistry.register(Bridges::Rumble)
  Stray::BridgeRegistry.register(Bridges::Bitchute)
  Stray::BridgeRegistry.register(Bridges::Odysee)
  Stray::BridgeRegistry.register(Bridges::Peertube)
  Stray::BridgeRegistry.register(Bridges::YoutubeRss)
  Stray::BridgeRegistry.register(Bridges::RssAtom)
  Stray::BridgeRegistry.register(Bridges::RemoteCollection)
  Stray::BridgeRegistry.register(Bridges::YtDlp)
  Stray::BridgeRegistry.register(Bridges::GenericPage)
end
```

Delete the old initializer:

```sh
git rm config/initializers/extractors.rb
```

- [ ] **Step 4: Update all call sites**

In `app/models/source.rb`, replace `ExtractorRegistry` → `Stray::BridgeRegistry` and rename `extractor_class` → `bridge_class`:

```ruby
def bridge_class
  Stray::BridgeRegistry.find_for_source(self)&.class
end
```

Remove the old `extractor_class` method.

In `app/jobs/source_poll_job.rb`, replace all `ExtractorRegistry` → `Stray::BridgeRegistry` and `Extractor::FeedResult` → `Stray::Bridge::FeedResult`.

In `app/jobs/link_intake_job.rb`, replace all `ExtractorRegistry` → `Stray::BridgeRegistry` and `Extractors::` → `Bridges::`.

In `app/services/url_classifier.rb`, replace all `Extractors::` → `Bridges::`.

In `app/jobs/metadata_enrichment_job.rb`, replace any `ExtractorRegistry` or `Extractors::` references.

- [ ] **Step 5: Update all test files**

In every test file under `test/bridges/` and `test/lib/stray/bridges/`:
- Replace `Extractors::` → `Bridges::`
- Replace `ExtractorRegistry` → `Stray::BridgeRegistry`
- Replace `Extractor::FeedResult` → `Stray::Bridge::FeedResult`
- Replace `< Extractor` → `< Stray::Bridge`

In `test/lib/stray/bridge_registry_test.rb` (already written in Task 2), no changes needed.

Delete the old test directories:

```sh
git rm -r test/services/extractor/ test/services/extractors/ test/services/extractor_registry_test.rb 2>/dev/null || true
git rm -r test/lib/stray/extractors/ 2>/dev/null || true
```

- [ ] **Step 6: Run the full test suite to verify the rename is complete**

Run: `bin/rails test`
Expected: All tests pass (or only pre-existing failures unrelated to the rename). If there are `NameError` for `Extractor` or `ExtractorRegistry` or `Extractors::`, find and fix the remaining reference.

- [ ] **Step 7: Commit**

```sh
git add -A
git commit -m "refactor: rename all Extractors to Bridges across codebase

Moves app/services/extractors/ → app/bridges/, lib/stray/extractors/ →
lib/stray/bridges/, updates SourcePollJob, LinkIntakeJob, UrlClassifier,
Source#bridge_class, and all tests. Runtime interface unchanged."
```

### Task 5: Retrofit bridge metadata onto existing video adapters

**Files:**
- Modify: `app/bridges/rumble.rb`, `app/bridges/bitchute.rb`, `app/bridges/odysee.rb`, `app/bridges/peertube.rb`, `app/bridges/youtube_rss.rb`, `app/bridges/yt_dlp.rb`

- [ ] **Step 1: Add metadata to each video bridge**

In `app/bridges/rumble.rb`, add inside the class body:

```ruby
def self.trust_level = :scraped_html
def self.site_homepage = "https://rumble.com"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

In `app/bridges/bitchute.rb`:

```ruby
def self.trust_level = :scraped_html
def self.site_homepage = "https://www.bitchute.com"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

In `app/bridges/odysee.rb`:

```ruby
def self.trust_level = :hidden_rss
def self.site_homepage = "https://odysee.com"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

In `app/bridges/peertube.rb`:

```ruby
def self.trust_level = :scraped_html
def self.site_homepage = "https://joinpeertube.org"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

In `app/bridges/youtube_rss.rb`:

```ruby
def self.trust_level = :hidden_rss
def self.site_homepage = "https://www.youtube.com"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

In `app/bridges/yt_dlp.rb`:

```ruby
def self.trust_level = :official_api
def self.site_homepage = "https://github.com/yt-dlp/yt-dlp"
def self.last_tested_against = "2026-08"
def self.author = "Stray"
```

- [ ] **Step 2: Write a test asserting metadata on each video bridge**

Create `test/bridges/video_metadata_test.rb`:

```ruby
require "test_helper"

class Bridges::VideoMetadataTest < ActiveSupport::TestCase
  { "Rumble" => [ :scraped_html, "https://rumble.com" ],
    "Bitchute" => [ :scraped_html, "https://www.bitchute.com" ],
    "Odysee" => [ :hidden_rss, "https://odysee.com" ],
    "Peertube" => [ :scraped_html, "https://joinpeertube.org" ],
    "YoutubeRss" => [ :hidden_rss, "https://www.youtube.com" ],
    "YtDlp" => [ :official_api, "https://github.com/yt-dlp/yt-dlp" ] }.each do |name, (trust, homepage)|
    test "#{name} bridge has trust_level #{trust} and homepage #{homepage}" do
      bridge = "Bridges::#{name}".constantize
      assert_equal trust, bridge.trust_level
      assert_equal homepage, bridge.site_homepage
      assert_not_nil bridge.last_tested_against
      assert_not_nil bridge.author
    end
  end
end
```

- [ ] **Step 3: Run test, verify pass, commit**

```sh
bin/rails test test/bridges/video_metadata_test.rb
git add -A
git commit -m "feat: retrofit bridge metadata onto all video adapters

Declares trust_level, site_homepage, last_tested_against, and author
on Rumble, Bitchute, Odysee, Peertube, YoutubeRss, and YtDlp bridges."
```

---

## Phase 2 — RSS Discovery & Politeness (§3)

### Task 6: Add conditional GET to `PoliteCrawl`

**Files:**
- Modify: `app/services/polite_crawl.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/polite_crawl_test.rb`:

```ruby
test "get_with_cache sends If-None-Match and If-Modified-Since headers when provided" do
  client = Minitest::Mock.new
  client.expect(:get, :response, [ "https://example.com", { headers: { "If-None-Match" => "etag123", "If-Modified-Since" => "Wed, 01 Jan 2025 00:00:00 GMT" } } ])

  PoliteCrawl.stub(:sleep, -> {}) do
    result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: "etag123", last_modified: "Wed, 01 Jan 2025 00:00:00 GMT")
    assert_equal :response, result
  end
  client.verify
end

test "get_with_cache returns :not_modified when response status is 304" do
  response = Struct.new(:status, :body, :headers).new(304, "", {})
  client = Minitest::Mock.new
  client.expect(:get, response, [ "https://example.com", { headers: { "If-None-Match" => "etag123", "If-Modified-Since" => nil } } ])

  PoliteCrawl.stub(:sleep, -> {}) do
    result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: "etag123", last_modified: nil)
    assert_equal :not_modified, result
  end
  client.verify
end

test "get_with_cache extracts ETag and Last-Modified from response headers" do
  response = Struct.new(:status, :body, :headers).new(200, "content", { "etag" => "new-etag", "last-modified" => "Thu, 02 Jan 2025 00:00:00 GMT" })
  client = Minitest::Mock.new
  client.expect(:get, response, [ "https://example.com", { headers: { "If-None-Match" => nil, "If-Modified-Since" => nil } } ])

  PoliteCrawl.stub(:sleep, -> {}) do
    result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: nil, last_modified: nil)
    assert_equal :response, result.response
    assert_equal "new-etag", result.etag
    assert_equal "Thu, 02 Jan 2025 00:00:00 GMT", result.last_modified
  end
  client.verify
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/polite_crawl_test.rb`
Expected: FAIL — `get_with_cache` is not defined.

- [ ] **Step 3: Implement `get_with_cache`**

Replace `app/services/polite_crawl.rb` with:

```ruby
class PoliteCrawl
  CachedResponse = Data.define(:response, :etag, :last_modified)

  class << self
    def delay_seconds
      (Setting.get(:polite_crawl_delay) || 1.0).to_f
    end

    def sleep
      secs = delay_seconds
      Kernel.sleep(secs) if secs.positive?
    end

    def get(url, http_client:)
      sleep
      http_client.get(url)
    end

    def get_with_cache(url, http_client:, etag: nil, last_modified: nil)
      sleep
      headers = {}
      headers["If-None-Match"] = etag if etag.present?
      headers["If-Modified-Since"] = last_modified if last_modified.present?

      response = http_client.get(url, { headers: headers }.compact_blank)
      return :not_modified if response.status == 304

      CachedResponse.new(
        response: response,
        etag: response.headers["etag"] || response.headers["ETag"],
        last_modified: response.headers["last-modified"] || response.headers["Last-Modified"]
      )
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/polite_crawl_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/services/polite_crawl.rb test/services/polite_crawl_test.rb
git commit -m "feat: add conditional GET to PoliteCrawl

get_with_cache sends If-None-Match/If-Modified-Since headers and
returns :not_modified on 304, or a CachedResponse with extracted
ETag/Last-Modified on 200."
```

### Task 7: Add uniform `UrlGuard` to `PoliteCrawl`

**Files:**
- Modify: `app/services/polite_crawl.rb`
- Modify: `app/bridges/generic_page.rb`, `app/bridges/remote_collection.rb` (remove per-bridge UrlGuard calls)

- [ ] **Step 1: Write the failing test**

Add to `test/services/polite_crawl_test.rb`:

```ruby
test "get raises UrlGuard::Blocked for localhost URLs" do
  client = Minitest::Mock.new
  assert_raises(UrlGuard::Blocked) do
    PoliteCrawl.stub(:sleep, -> {}) do
      PoliteCrawl.get("http://localhost:3000/admin", http_client: client)
    end
  end
end

test "get_with_cache raises UrlGuard::Blocked for private IP URLs" do
  client = Minitest::Mock.new
  assert_raises(UrlGuard::Blocked) do
    PoliteCrawl.stub(:sleep, -> {}) do
      PoliteCrawl.get_with_cache("http://192.168.1.1/secret", http_client: client)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/polite_crawl_test.rb`
Expected: FAIL — no UrlGuard check in PoliteCrawl.

- [ ] **Step 3: Add UrlGuard to PoliteCrawl**

Update `app/services/polite_crawl.rb` — add `UrlGuard.allowed?` check to both `get` and `get_with_cache`:

```ruby
def get(url, http_client:)
  raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
  sleep
  http_client.get(url)
end

def get_with_cache(url, http_client:, etag: nil, last_modified: nil)
  raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
  sleep
  headers = {}
  headers["If-None-Match"] = etag if etag.present?
  headers["If-Modified-Since"] = last_modified if last_modified.present?

  response = http_client.get(url, { headers: headers }.compact_blank)
  return :not_modified if response.status == 304

  CachedResponse.new(
    response: response,
    etag: response.headers["etag"] || response.headers["ETag"],
    last_modified: response.headers["last-modified"] || response.headers["Last-Modified"]
  )
end
```

- [ ] **Step 4: Remove per-bridge UrlGuard calls**

In `app/bridges/generic_page.rb`, remove from the `fetch` method:

```ruby
raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
```

In `app/bridges/remote_collection.rb`, remove from `extract_feed`:

```ruby
raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
```

- [ ] **Step 5: Run full test suite to verify no double-check breakage**

Run: `bin/rails test`
Expected: PASS. The `generic_page_test.rb` test "extract raises when URL blocked by UrlGuard" should still pass because `PoliteCrawl.get` now raises `UrlGuard::Blocked` before the HTTP call.

- [ ] **Step 6: Commit**

```sh
git add app/services/polite_crawl.rb app/bridges/generic_page.rb app/bridges/remote_collection.rb test/services/polite_crawl_test.rb
git commit -m "feat: move UrlGuard into PoliteCrawl for uniform SSRF protection

All bridges are now SSRF-protected by default. Removes per-bridge
UrlGuard calls from GenericPage and RemoteCollection (no double-check)."
```

### Task 8: Add `etag` and `last_modified` columns to `Source`

**Files:**
- Create: `db/migrate/<ts>_add_poll_metadata_to_sources.rb`
- Modify: `app/models/source.rb`
- Modify: `test/fixtures/sources.yml`

- [ ] **Step 1: Generate and write the migration**

```sh
bin/rails g migration AddPollMetadataToSources etag:string last_modified:string consecutive_empty_polls:integer
```

Edit the generated file to add defaults:

```ruby
class AddPollMetadataToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :etag, :string
    add_column :sources, :last_modified, :string
    add_column :sources, :consecutive_empty_polls, :integer, null: false, default: 0
  end
end
```

- [ ] **Step 2: Run the migration**

```sh
bin/rails db:migrate
```

- [ ] **Step 3: Commit**

```sh
git add db/migrate/*_add_poll_metadata_to_sources.rb db/schema.rb
git commit -m "db: add etag, last_modified, consecutive_empty_polls to sources"
```

### Task 9: Add `degraded` status to `Source`

**Files:**
- Create: `db/migrate/<ts>_add_degraded_to_source_status.rb`
- Modify: `app/models/source.rb`

- [ ] **Step 1: Write the no-op migration**

```sh
bin/rails g migration AddDegradedToSourceStatus
```

Edit:

```ruby
class AddDegradedToSourceStatus < ActiveRecord::Migration[8.1]
  def up; end
  def down; end
end
```

- [ ] **Step 2: Run migration**

```sh
bin/rails db:migrate
```

- [ ] **Step 3: Update the `Source` model**

In `app/models/source.rb`, change the status enum:

```ruby
enum :status, { pending: 0, ok: 1, failed: 2, degraded: 3 }
```

Add a scope:

```ruby
scope :degraded, -> { where(status: :degraded) }
```

- [ ] **Step 4: Write a test**

Add to `test/models/source_test.rb` (or create if it doesn't exist):

```ruby
test "status enum includes degraded" do
  source = Source.new(kind: :generic_page, url: "https://example.com", external_id: "x")
  source.status = :degraded
  assert_equal "degraded", source.status
end
```

- [ ] **Step 5: Run test, verify pass, commit**

```sh
bin/rails test test/models/source_test.rb
git add -A
git commit -m "feat: add degraded status to Source enum

Documents enum value 3 (:degraded) for selector-rot alerting.
Distinct from :failed — the bridge ran without error but found nothing."
```

### Task 10: Create `FeedDiscovery` service

**Files:**
- Create: `app/services/feed_discovery.rb`
- Create: `test/services/feed_discovery_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/feed_discovery_test.rb`:

```ruby
require "test_helper"

class FeedDiscoveryTest < ActiveSupport::TestCase
  test "find_feed_url returns RSS link when present in HTML head" do
    html = %(<html><head><link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml" title="RSS"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/feed.xml", result
  end

  test "find_feed_url returns Atom link when present" do
    html = %(<html><head><link rel="alternate" type="application/atom+xml" href="https://example.com/atom" title="Atom"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/atom", result
  end

  test "find_feed_url returns nil when no feed link present" do
    html = %(<html><head></head><body>just a page</body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_nil result
  end

  test "find_feed_url resolves relative URLs against the base URL" do
    html = %(<html><head><link rel="alternate" type="application/rss+xml" href="/blog/feed.xml"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com/blog/")
    assert_equal "https://example.com/blog/feed.xml", result
  end

  test "find_feed_url prefers RSS over Atom when both present" do
    html = %(<html><head>
      <link rel="alternate" type="application/atom+xml" href="https://example.com/atom">
      <link rel="alternate" type="application/rss+xml" href="https://example.com/rss">
    </head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/rss", result
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/feed_discovery_test.rb`
Expected: FAIL — `FeedDiscovery` not defined.

- [ ] **Step 3: Implement `FeedDiscovery`**

Create `app/services/feed_discovery.rb`:

```ruby
require "nokogiri"

class FeedDiscovery
  FEED_TYPES = %w[application/rss+xml application/atom+xml].freeze

  class << self
    def find_feed_url(html, base_url)
      doc = Nokogiri::HTML(html)
      links = doc.css('link[rel="alternate"]').select { |l| FEED_TYPES.include?(l["type"]) }
      return nil if links.empty?

      rss_link = links.find { |l| l["type"] == "application/rss+xml" } || links.first
      href = rss_link["href"]
      return nil unless href

      absolute_url(href, base_url)
    end

    private

    def absolute_url(href, base_url)
      URI.join(base_url, href).to_s
    rescue URI::InvalidURIError
      href
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/feed_discovery_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/services/feed_discovery.rb test/services/feed_discovery_test.rb
git commit -m "feat: add FeedDiscovery service for RSS auto-discovery

Parses <link rel='alternate'> tags in HTML head to find RSS/Atom
feed URLs. Resolves relative URLs. Prefers RSS over Atom."
```

---

## Phase 3 — Generic HTML List Extraction (§4)

### Task 11: Add `generic_list` Source kind

**Files:**
- Create: `db/migrate/<ts>_add_generic_list_to_source_kind.rb`
- Modify: `app/models/source.rb`

- [ ] **Step 1: Write the no-op migration**

```sh
bin/rails g migration AddGenericListToSourceKind
```

Edit:

```ruby
class AddGenericListToSourceKind < ActiveRecord::Migration[8.1]
  def up; end
  def down; end
end
```

- [ ] **Step 2: Run migration**

```sh
bin/rails db:migrate
```

- [ ] **Step 3: Update the `Source` kind enum**

In `app/models/source.rb`, change:

```ruby
enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4, rumble_channel: 5, bitchute_channel: 6, odysee_channel: 7, peertube_channel: 8, generic_list: 9 }
```

- [ ] **Step 4: Write a test**

Add to `test/models/source_test.rb`:

```ruby
test "kind enum includes generic_list" do
  source = Source.new(kind: :generic_list, url: "https://example.com", external_id: "x")
  assert_equal "generic_list", source.kind
end
```

- [ ] **Step 5: Run test, verify pass, commit**

```sh
bin/rails test test/models/source_test.rb
git add -A
git commit -m "db: add generic_list (9) to Source kind enum"
```

### Task 12: Create `Bridges::GenericList` — JSON-LD `ItemList` detection

**Files:**
- Create: `app/bridges/generic_list.rb`
- Create: `test/bridges/generic_list_test.rb`

- [ ] **Step 1: Write the failing test for JSON-LD detection**

Create `test/bridges/generic_list_test.rb`:

```ruby
require "test_helper"

class Bridges::GenericListTest < ActiveSupport::TestCase
  test "handles_kind? returns true for generic_list" do
    assert Bridges::GenericList.handles_kind?("generic_list")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Bridges::GenericList.handles_kind?("generic_page")
    assert_not Bridges::GenericList.handles_kind?("rss_feed")
  end

  test "matches? returns true for any http/https URL" do
    assert Bridges::GenericList.matches?("https://example.com/blog")
    assert Bridges::GenericList.matches?("http://example.com")
  end

  test "trust_level is :scraped_html" do
    assert_equal :scraped_html, Bridges::GenericList.trust_level
  end

  test "detect returns item count when JSON-LD ItemList is present" do
    html = %(<html><head>
      <script type="application/ld+json">
      {"@type":"ItemList","itemListElement":[
        {"@type":"ListItem","position":1,"url":"https://example.com/post-1","name":"Post 1"},
        {"@type":"ListItem","position":2,"url":"https://example.com/post-2","name":"Post 2"},
        {"@type":"ListItem","position":3,"url":"https://example.com/post-3","name":"Post 3"}
      ]}
      </script>
    </head><body></body></html>)
    assert_equal 3, Bridges::GenericList.detect(html)
  end

  test "detect returns nil when no list structure found" do
    html = %(<html><head></head><body><p>Just a single article page with no list.</p></body></html>)
    assert_nil Bridges::GenericList.detect(html)
  end

  test "extract_feed parses JSON-LD ItemList into ExtractedContent array" do
    html = %(<html><head>
      <script type="application/ld+json">
      {"@type":"ItemList","itemListElement":[
        {"@type":"ListItem","position":1,"url":"https://example.com/post-1","name":"Post 1","image":"https://example.com/img1.jpg","datePublished":"2025-01-01T00:00:00Z"},
        {"@type":"ListItem","position":2,"url":"https://example.com/post-2","name":"Post 2","image":"https://example.com/img2.jpg","datePublished":"2025-01-02T00:00:00Z"}
      ]}
      </script>
    </head><body></body></html>)
    PoliteCrawl.stub(:sleep, -> {}) do
      VCR.use_cassette("bridges/generic_list/json_ld") do
        bridge = Bridges::GenericList.new
        results = bridge.extract_feed_from_html(html, "https://example.com")
        assert_equal 2, results.size
        assert_equal "Post 1", results[0].title
        assert_equal "https://example.com/post-1", results[0].url
        assert_equal "https://example.com/img1.jpg", results[0].thumbnail_url
        assert_equal Digest::SHA256.hexdigest("https://example.com/post-1"), results[0].external_id
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/bridges/generic_list_test.rb`
Expected: FAIL — `Bridges::GenericList` not defined.

- [ ] **Step 3: Implement `Bridges::GenericList` with JSON-LD detection**

Create `app/bridges/generic_list.rb`:

```ruby
require "digest"
require "faraday"
require "nokogiri"

module Bridges
  class GenericList < Stray::Bridge
    MIN_ITEMS = 3

    def self.matches?(url)
      uri = URI.parse(url)
      uri.scheme.in?(%w[http https]) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def self.handles_kind?(kind)
      kind == "generic_list"
    end

    def self.detect(html_or_url)
      html = fetch_html(html_or_url)
      return nil unless html

      count = json_ld_item_count(html)
      return count if count && count >= MIN_ITEMS

      count = repeating_element_count(html)
      return count if count && count >= MIN_ITEMS

      nil
    end

    def extract_feed(url)
      html = fetch_html(url)
      raise Stray::ExtractionError, "page fetch failed" unless html

      extract_feed_from_html(html, url)
    end

    def extract_feed_from_html(html, base_url)
      items = extract_json_ld_items(html, base_url)
      return items if items.any?

      extract_repeating_elements(html, base_url)
    end

    private

    def fetch_html(url_or_html)
      return url_or_html if url_or_html.include?("<html") || url_or_html.include?("<!DOCTYPE")

      response = PoliteCrawl.get(url_or_html, http_client: http_client)
      raise Stray::ExtractionError, "page fetch failed: #{response.status}" unless response.status == 200

      response.body
    end

    def http_client
      Faraday.new do |conn|
        conn.response :follow_redirects, max: 3
        conn.options.timeout = 30
        conn.options.open_timeout = 10
        conn.adapter :net_http
      end
    end

    def json_ld_item_count(html)
      items = extract_json_ld_items(html, "https://example.com")
      items.size if items.any?
    end

    def extract_json_ld_items(html, base_url)
      doc = Nokogiri::HTML(html)
      doc.css('script[type="application/ld+json"]').flat_map do |script|
        data = JSON.parse(script.content) rescue next
        arrays = data.is_a?(Array) ? data : [ data ]
        arrays.select { |d| d.is_a?(Hash) && d["@type"] == "ItemList" }
          .flat_map { |d| d["itemListElement"] || [] }
      end.compact.map do |element|
        map_json_ld_item(element, base_url)
      end.compact
    end

    def map_json_ld_item(element, base_url)
      return nil unless element.is_a?(Hash)

      url = element["url"]
      return nil unless url

      url = absolute_url(url, base_url)
      Stray::ExtractedContent.new(
        url: url,
        title: element["name"],
        content_text: nil,
        content_html: nil,
        thumbnail_url: element["image"],
        published_at: parse_date(element["datePublished"]),
        external_id: Digest::SHA256.hexdigest(url),
        duration: nil,
        creator_identity: nil,
        tags: []
      )
    end

    def repeating_element_count(html)
      items = extract_repeating_elements(html, "https://example.com")
      items.size if items.any?
    end

    def extract_repeating_elements(html, base_url)
      doc = Nokogiri::HTML(html)
      groups = doc.css("article, li, div").group_by { |el| "#{el.name}.#{el["class"]}" }
      best_group = groups.values.max_by { |group| group.size }

      return [] unless best_group && best_group.size >= MIN_ITEMS

      best_group.map { |el| map_repeating_element(el, base_url) }.compact
    end

    def map_repeating_element(element, base_url)
      link = element.at_css("a[href]")
      return nil unless link

      url = absolute_url(link["href"], base_url)
      title = element.at_css("h1, h2, h3, h4, .title")&.text&.strip || link.text&.strip
      thumbnail = element.at_css("img")&.[]("src")
      thumbnail = absolute_url(thumbnail, base_url) if thumbnail
      published = element.at_css("time[datetime]")&.[]("datetime")

      Stray::ExtractedContent.new(
        url: url,
        title: title,
        content_text: nil,
        content_html: nil,
        thumbnail_url: thumbnail,
        published_at: parse_date(published),
        external_id: Digest::SHA256.hexdigest(url),
        duration: nil,
        creator_identity: nil,
        tags: []
      )
    end

    def absolute_url(href, base_url)
      return nil unless href
      URI.join(base_url, href).to_s
    rescue URI::InvalidURIError
      href
    end

    def parse_date(value)
      return nil unless value
      Time.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/bridges/generic_list_test.rb`
Expected: PASS

- [ ] **Step 5: Register the bridge and commit**

In `config/initializers/bridges.rb`, add before `Bridges::GenericPage`:

```ruby
Stray::BridgeRegistry.register(Bridges::GenericList)
```

```sh
git add app/bridges/generic_list.rb test/bridges/generic_list_test.rb config/initializers/bridges.rb
git commit -m "feat: add Bridges::GenericList for HTML list-page extraction

Detects JSON-LD ItemList structures and repeating DOM elements.
external_id is the permalink hash (SHA256), never array position.
detect() returns item count or nil for use at intake time."
```

### Task 13: Add `generic_list` routing to `UrlClassifier`

**Files:**
- Modify: `app/services/url_classifier.rb`
- Modify: `test/services/url_classifier_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/url_classifier_test.rb`:

```ruby
test "classifies generic list page when GenericList detects a list" do
  Bridges::GenericList.stub(:detect, 5) do
    c = UrlClassifier.classify("https://example.com/blog")
    assert_equal :generic_list, c.category
    assert_equal "generic_list", c.source_kind
    assert_equal Bridges::GenericList, c.extractor_class
  end
end

test "classifies generic page (bookmark) when GenericList detects no list" do
  Bridges::GenericList.stub(:detect, nil) do
    c = UrlClassifier.classify("https://example.com/blog")
    assert_equal :generic_page, c.category
    assert_equal "generic_page", c.source_kind
    assert_equal Bridges::GenericPage, c.extractor_class
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/url_classifier_test.rb`
Expected: FAIL — `generic_list` category not returned.

- [ ] **Step 3: Update `UrlClassifier`**

In `app/services/url_classifier.rb`, change the `else` branch to try `GenericList` first:

```ruby
else
  list_count = Bridges::GenericList.detect(uri.to_s)
  if list_count
    classification(:generic_list, "generic_list", Bridges::GenericList)
  else
    classification(:generic_page, "generic_page", Bridges::GenericPage)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/url_classifier_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/services/url_classifier.rb test/services/url_classifier_test.rb
git commit -m "feat: route generic list pages to GenericList bridge

UrlClassifier tries GenericList.detect before falling back to
GenericPage (bookmark). Source kind is set at intake; no runtime
sniffing on subsequent polls."
```

### Task 14: Add `generic_list` intake to `LinkIntakeJob`

**Files:**
- Modify: `app/jobs/link_intake_job.rb`
- Modify: `test/jobs/link_intake_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/link_intake_job_test.rb`:

```ruby
test "creates generic_list source when list page detected" do
  contents = [ Stray::ExtractedContent.new(url: "https://example.com/post-1", title: "Post 1", content_text: nil, content_html: nil,
    thumbnail_url: nil, published_at: nil, external_id: Digest::SHA256.hexdigest("https://example.com/post-1"), duration: nil, creator_identity: nil, tags: []) ]
  extractor = Minitest::Mock.new
  extractor.expect(:extract_feed, contents, [ "https://example.com/blog" ])
  extractor.expect(:enrich_tags, nil, [ String ]) if extractor.respond_to?(:enrich_tags)

  Stray::BridgeRegistry.stub(:find_for, extractor, [ "https://example.com/blog" ]) do
    perform_enqueued_jobs do
      LinkIntakeJob.perform_later(@user.id, "https://example.com/blog")
    end
  end

  source = Source.find_by(url: "https://example.com/blog")
  assert source
  assert_equal "generic_list", source.kind
  assert_equal 1, source.items.count
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/link_intake_job_test.rb`
Expected: FAIL — `generic_list` category not handled in `LinkIntakeJob`.

- [ ] **Step 3: Add `generic_list` handling to `LinkIntakeJob`**

In `app/jobs/link_intake_job.rb`, add to the `case` statement in `extract_and_create`, before `when :generic_page`:

```ruby
when :generic_list    then extract_generic_list
```

Add the method:

```ruby
def extract_generic_list
  extractor = Stray::BridgeRegistry.find_for(@url)
  contents = Array(extractor.extract_feed(@url))

  source = create_source(
    kind: :generic_list,
    url: @url,
    external_id: Digest::SHA256.hexdigest(@url)[0, 16],
    name: extract_list_name(contents, @url)
  )

  create_items(source, contents)
  enqueue_full_poll(source)
  [ contents, source ]
end

def extract_list_name(contents, url)
  creator = contents.map(&:creator_identity).compact.find { |c| c.name }
  return creator.name if creator

  uri = URI.parse(url)
  uri.host&.sub(/^www\./, "")
rescue URI::InvalidURIError
  nil
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/link_intake_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/jobs/link_intake_job.rb test/jobs/link_intake_job_test.rb
git commit -m "feat: add generic_list intake to LinkIntakeJob"
```

### Task 15: Create `SourceSecret` model

**Files:**
- Create: `db/migrate/<ts>_create_source_secrets.rb`
- Create: `app/models/source_secret.rb`
- Modify: `app/models/source.rb`
- Create: `test/fixtures/source_secrets.yml`
- Create: `test/models/source_secret_test.rb`

- [ ] **Step 1: Generate and write the migration**

```sh
bin/rails g migration CreateSourceSecrets
```

Edit:

```ruby
class CreateSourceSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :source_secrets do |t|
      t.references :source, null: false, foreign_key: true
      t.string :field_name, null: false
      t.text :value
      t.timestamps
    end
    add_index :source_secrets, [ :source_id, :field_name ], unique: true
  end
end
```

- [ ] **Step 2: Run the migration**

```sh
bin/rails db:migrate
```

- [ ] **Step 3: Write the model**

Create `app/models/source_secret.rb`:

```ruby
class SourceSecret < ApplicationRecord
  belongs_to :source

  encrypts :value

  validates :source_id, :field_name, presence: true
  validates :field_name, uniqueness: { scope: :source_id }
end
```

- [ ] **Step 4: Add association to `Source`**

In `app/models/source.rb`, add:

```ruby
has_many :secrets, class_name: "SourceSecret", dependent: :destroy
```

- [ ] **Step 5: Write the test**

Create `test/models/source_secret_test.rb`:

```ruby
require "test_helper"

class SourceSecretTest < ActiveSupport::TestCase
  test "value is encrypted at rest" do
    source = sources(:youtube)
    secret = SourceSecret.create!(source: source, field_name: "api_key", value: "secret-key-123")

    raw = SourceSecret.connection.execute("SELECT value FROM source_secrets WHERE id = #{secret.id}").first["value"]
    assert_not_includes raw, "secret-key-123"
    assert_equal "secret-key-123", secret.reload.value
  end

  test "field_name must be unique per source" do
    source = sources(:youtube)
    SourceSecret.create!(source: source, field_name: "cookies", value: "cookie1")
    assert_raises(ActiveRecord::RecordInvalid) do
      SourceSecret.create!(source: source, field_name: "cookies", value: "cookie2")
    end
  end

  test "requires source_id and field_name" do
    secret = SourceSecret.new(field_name: "api_key", value: "x")
    assert_not secret.valid?
    assert_includes secret.errors[:source_id], "can't be blank"
  end
end
```

Create `test/fixtures/source_secrets.yml`:

```yaml
one:
  source: youtube
  field_name: "api_key"
  value: "test-api-key"
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/models/source_secret_test.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```sh
git add -A
git commit -m "feat: add SourceSecret model for per-source encrypted auth

Stores per-source secrets (cookies, API keys, auth headers) encrypted
via Rails ActiveRecord Encryption (STRAY_ENCRYPTION_KEY). Unique
field_name per source. Reuses the same encryption infra as Setting."
```

### Task 16: Hydrate secrets in `SourcePollJob`

**Files:**
- Modify: `app/jobs/source_poll_job.rb`
- Modify: `test/jobs/source_poll_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/source_poll_job_test.rb`:

```ruby
test "hydrates secrets onto bridge when requires_auth?" do
  source = sources(:youtube)
  SourceSecret.create!(source: source, field_name: "api_key", value: "secret123")

  bridge = Minitest::Mock.new
  bridge.expect(:extract_feed, [], [ source.url ])
  bridge_class = Struct.new(:requires_auth?, :secret_fields).new(true, [ :api_key ])

  Stray::BridgeRegistry.stub(:find_for_source, bridge) do
    bridge.singleton_class.define_method(:class) { bridge_class }
    bridge.singleton_class.define_method(:requires_auth?) { true }
    bridge.singleton_class.define_method(:secret_fields) { [ :api_key ] }
    bridge.expect(:secrets=, nil, [ { "api_key" => anything } ])

    SourcePollJob.new.send(:extract_and_persist, source)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: FAIL — secrets not hydrated.

- [ ] **Step 3: Add secret hydration to `SourcePollJob#extract_and_persist`**

In `app/jobs/source_poll_job.rb`, modify `extract_and_persist`:

```ruby
def extract_and_persist(source)
  extractor = Stray::BridgeRegistry.find_for_source(source)
  raise Stray::YtDlp::ExtractionFailed, "No bridge for kind=#{source.kind} url=#{source.url}" unless extractor

  if extractor.class.requires_auth?
    secrets = source.secrets.index_by(&:field_name)
    missing = extractor.class.secret_fields - secrets.keys
    if missing.any?
      raise Stray::ExtractionError, "Bridge requires #{missing.join(', ')} secret(s); none configured"
    end
    extractor.secrets = secrets
  end

  contents = extractor.extract_feed(source.url)
  contents = Array(contents)

  upsert_items(source, contents, extractor)
  backfill_source_metadata(source, contents)
  source.recalculate_next_crawl!
  source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil, status: :ok)
rescue NotImplementedError => e
  source.update!(last_error: "Bridge missing extract_feed: #{e.message}", last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
rescue Stray::YtDlp::Error, Stray::ExtractionError
  raise
rescue StandardError => e
  source.update!(last_error: e.message, last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/jobs/source_poll_job.rb test/jobs/source_poll_job_test.rb
git commit -m "feat: hydrate SourceSecret onto bridge in SourcePollJob

When a bridge declares requires_auth?, secrets are loaded and
hydrated before extract_feed. Missing secrets fail fast with a
user-actionable error."
```

---

## Phase 4 — Governance (§5)

### Task 17: Wire conditional GET into `SourcePollJob`

**Files:**
- Modify: `app/jobs/source_poll_job.rb`
- Modify: `test/jobs/source_poll_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/source_poll_job_test.rb`:

```ruby
test "skips parsing and refreshes last_polled_at on 304 Not Modified" do
  source = sources(:youtube)
  source.update!(etag: "etag-abc", last_modified: "Wed, 01 Jan 2025 00:00:00 GMT")

  cached_response = PoliteCrawl::CachedResponse.new(response: nil, etag: "etag-abc", last_modified: "Wed, 01 Jan 2025 00:00:00 GMT")

  extractor = Minitest::Mock.new

  PoliteCrawl.stub(:get_with_cache, :not_modified) do
    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      SourcePollJob.new.send(:extract_and_persist, source)
    end
  end

  assert source.reload.last_polled_at.present?
  assert_equal "ok", source.status
  assert_not extractor.verify_called
end

test "updates etag and last_modified on Source after successful fetch" do
  source = sources(:youtube)
  response = Struct.new(:status, :body, :headers).new(200, "<html>feed</html>", { "etag" => "new-etag", "last-modified" => "Thu, 02 Jan 2025 00:00:00 GMT" })
  cached_response = PoliteCrawl::CachedResponse.new(response: response, etag: "new-etag", last_modified: "Thu, 02 Jan 2025 00:00:00 GMT")

  bridge = Minitest::Mock.new
  bridge.expect(:extract_feed, [], [ source.url ])

  PoliteCrawl.stub(:get_with_cache, cached_response) do
    Stray::BridgeRegistry.stub(:find_for_source, bridge) do
      SourcePollJob.new.send(:extract_and_persist, source)
    end
  end

  assert_equal "new-etag", source.reload.etag
  assert_equal "Thu, 02 Jan 2025 00:00:00 GMT", source.reload.last_modified
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: FAIL — `extract_and_persist` still uses `extractor.extract_feed` directly without conditional GET.

- [ ] **Step 3: Wire conditional GET into `extract_and_persist`**

In `app/jobs/source_poll_job.rb`, modify `extract_and_persist` to use `PoliteCrawl.get_with_cache` and handle `:not_modified`. Note: the bridge's `extract_feed` currently fetches internally via `PoliteCrawl.get`. To enable conditional GET without rewriting every bridge, add an optional `etag`/`last_modified` accessor on `Stray::Bridge` that bridges can use. For the initial wiring, handle the 304 case at the job level by checking before delegating to the bridge:

```ruby
def extract_and_persist(source)
  extractor = Stray::BridgeRegistry.find_for_source(source)
  raise Stray::YtDlp::ExtractionFailed, "No bridge for kind=#{source.kind} url=#{source.url}" unless extractor

  if extractor.class.requires_auth?
    secrets = source.secrets.index_by(&:field_name)
    missing = extractor.class.secret_fields - secrets.keys
    if missing.any?
      raise Stray::ExtractionError, "Bridge requires #{missing.join(', ')} secret(s); none configured"
    end
    extractor.secrets = secrets
  end

  cached = PoliteCrawl.get_with_cache(
    source.url,
    http_client: http_client,
    etag: source.etag,
    last_modified: source.last_modified
  )

  if cached == :not_modified
    source.recalculate_next_crawl!
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil, status: :ok)
    return
  end

  contents = extractor.extract_feed_from_response(cached.response, source.url)
  contents = Array(contents)

  new_count = upsert_items(source, contents, extractor)
  track_empty_polls(source, new_count)
  backfill_source_metadata(source, contents)
  source.recalculate_next_crawl!
  status = new_count > 0 || source.consecutive_empty_polls < 3 ? :ok : :degraded
  source.update!(
    last_polled_at: Time.current,
    last_error: nil,
    last_error_at: nil,
    status: status,
    etag: cached.etag,
    last_modified: cached.last_modified
  )
rescue NotImplementedError => e
  source.update!(last_error: "Bridge missing extract_feed: #{e.message}", last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
rescue Stray::YtDlp::Error, Stray::ExtractionError
  raise
rescue StandardError => e
  source.update!(last_error: e.message, last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
end

def http_client
  Faraday.new do |conn|
    conn.response :follow_redirects, max: 3
    conn.options.timeout = 30
    conn.options.open_timeout = 10
    conn.adapter :net_http
  end
end
```

Add a default `extract_feed_from_response` to `Stray::Bridge` that falls back to `extract_feed` (so existing bridges work without modification):

In `app/bridges/stray/bridge.rb`, add:

```ruby
def extract_feed_from_response(response, url)
  extract_feed(url)
end
```

This is a transitional default — bridges that want to benefit from conditional GET (avoiding a double fetch) override `extract_feed_from_response` to parse the already-fetched response body. For now, the job-level 304 check saves the parse even if the bridge re-fetches on a 200.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/jobs/source_poll_job.rb app/bridges/stray/bridge.rb test/jobs/source_poll_job_test.rb
git commit -m "feat: wire conditional GET into SourcePollJob

Sends If-None-Match/If-Modified-Since from Source.etag/last_modified.
On 304, skips parsing entirely. On 200, stores new etag/last_modified.
Adds Stray::Bridge#extract_feed_from_response default for backwards
compatibility (bridges can override to avoid double-fetch)."
```

### Task 18: Per-domain rate budget in `PoliteCrawl`

**Files:**
- Modify: `app/services/polite_crawl.rb`
- Modify: `test/services/polite_crawl_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/polite_crawl_test.rb`:

```ruby
test "rate budget blocks request when domain bucket is exhausted" do
  Rails.cache.clear
  DomainMutex.stub(:domain_for, "example.com") do
    client = Minitest::Mock.new
    client.expect(:get, :response, [ "https://example.com/1" ])

    PoliteCrawl.stub(:sleep, -> {}) do
      PoliteCrawl.get("https://example.com/1", http_client: client)
    end

    assert_raises(Stray::RateBudgetExhausted) do
      PoliteCrawl.stub(:sleep, -> {}) do
        PoliteCrawl.get("https://example.com/2", http_client: client)
      end
    end
  end
end

test "rate budget allows requests after refill" do
  Rails.cache.clear
  DomainMutex.stub(:domain_for, "example.com") do
    client = Minitest::Mock.new
    client.expect(:get, :response, [ "https://example.com/1" ])

    PoliteCrawl.stub(:sleep, -> {}) do
      PoliteCrawl.get("https://example.com/1", http_client: client)
    end

    travel_to 11.seconds.from_now do
      client.expect(:get, :response, [ "https://example.com/2" ])
      PoliteCrawl.stub(:sleep, -> {}) do
        result = PoliteCrawl.get("https://example.com/2", http_client: client)
        assert_equal :response, result
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/polite_crawl_test.rb`
Expected: FAIL — `Stray::RateBudgetExhausted` not defined.

- [ ] **Step 3: Implement the rate budget**

Add to `app/services/polite_crawl.rb`:

```ruby
module Stray
  class RateBudgetExhausted < StandardError; end
end

class PoliteCrawl
  RATE_BUDGET_PER_MINUTE = 6
  RATE_BUDGET_INTERVAL = 60.0 / RATE_BUDGET_PER_MINUTE

  CachedResponse = Data.define(:response, :etag, :last_modified)

  class << self
    def delay_seconds
      (Setting.get(:polite_crawl_delay) || 1.0).to_f
    end

    def sleep
      secs = delay_seconds
      Kernel.sleep(secs) if secs.positive?
    end

    def get(url, http_client:)
      raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
      check_rate_budget(url)
      sleep
      http_client.get(url)
    end

    def get_with_cache(url, http_client:, etag: nil, last_modified: nil)
      raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
      check_rate_budget(url)
      sleep
      headers = {}
      headers["If-None-Match"] = etag if etag.present?
      headers["If-Modified-Since"] = last_modified if last_modified.present?

      response = http_client.get(url, { headers: headers }.compact_blank)
      return :not_modified if response.status == 304

      CachedResponse.new(
        response: response,
        etag: response.headers["etag"] || response.headers["ETag"],
        last_modified: response.headers["last-modified"] || response.headers["Last-Modified"]
      )
    end

    private

    def check_rate_budget(url)
      domain = DomainMutex.domain_for(url)
      return unless domain

      key = "stray:rate:#{domain}"
      last = Rails.cache.read(key)
      now = Time.current.to_f
      if last && (now - last) < RATE_BUDGET_INTERVAL
        raise Stray::RateBudgetExhausted, "Rate budget exhausted for #{domain}"
      end
      Rails.cache.write(key, now, expires_in: 1.hour)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/polite_crawl_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/services/polite_crawl.rb test/services/polite_crawl_test.rb
git commit -m "feat: add per-domain rate budget to PoliteCrawl

Token-bucket per domain (6 req/min default), Solid Cache-backed.
Prevents Stray from hammering small sites across many Sources sharing
a host. Raises Stray::RateBudgetExhausted when the bucket is empty."
```

### Task 19: Track `consecutive_empty_polls` and set `degraded` status

**Files:**
- Modify: `app/jobs/source_poll_job.rb`
- Modify: `test/jobs/source_poll_job_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/jobs/source_poll_job_test.rb`:

```ruby
test "increments consecutive_empty_polls when no new items created" do
  source = sources(:youtube)
  source.update!(consecutive_empty_polls: 1)

  existing_content = Stray::ExtractedContent.new(url: "https://example.com/v1", title: "Existing", content_text: nil,
    content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "existing-id", duration: nil, creator_identity: nil, tags: [])
  Item.create!(source: source, user: source.user, external_id: "existing-id", title: "Existing", url: "https://example.com/v1")

  extractor = Minitest::Mock.new
  extractor.expect(:extract_feed, [ existing_content ], [ source.url ])

  Stray::BridgeRegistry.stub(:find_for_source, extractor) do
    SourcePollJob.new.send(:extract_and_persist, source)
  end

  assert_equal 2, source.reload.consecutive_empty_polls
  assert_equal "ok", source.status
end

test "sets status to degraded after 3 consecutive empty polls" do
  source = sources(:youtube)
  source.update!(consecutive_empty_polls: 2)

  existing_content = Stray::ExtractedContent.new(url: "https://example.com/v1", title: "Existing", content_text: nil,
    content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "existing-id", duration: nil, creator_identity: nil, tags: [])
  Item.create!(source: source, user: source.user, external_id: "existing-id", title: "Existing", url: "https://example.com/v1")

  extractor = Minitest::Mock.new
  extractor.expect(:extract_feed, [ existing_content ], [ source.url ])

  Stray::BridgeRegistry.stub(:find_for_source, extractor) do
    SourcePollJob.new.send(:extract_and_persist, source)
  end

  assert_equal 3, source.reload.consecutive_empty_polls
  assert_equal "degraded", source.status
end

test "resets consecutive_empty_polls when new items are created" do
  source = sources(:youtube)
  source.update!(consecutive_empty_polls: 2)

  new_content = Stray::ExtractedContent.new(url: "https://example.com/new", title: "New", content_text: nil,
    content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "new-id", duration: nil, creator_identity: nil, tags: [])

  extractor = Minitest::Mock.new
  extractor.expect(:extract_feed, [ new_content ], [ source.url ])

  Stray::BridgeRegistry.stub(:find_for_source, extractor) do
    SourcePollJob.new.send(:extract_and_persist, source)
  end

  assert_equal 0, source.reload.consecutive_empty_polls
  assert_equal "ok", source.status
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: FAIL — empty-poll tracking not implemented.

- [ ] **Step 3: Implement empty-poll tracking**

In `app/jobs/source_poll_job.rb`, modify `extract_and_persist` to track new vs. existing items. After `upsert_items`, add:

```ruby
def extract_and_persist(source)
  extractor = Stray::BridgeRegistry.find_for_source(source)
  raise Stray::YtDlp::ExtractionFailed, "No bridge for kind=#{source.kind} url=#{source.url}" unless extractor

  if extractor.class.requires_auth?
    secrets = source.secrets.index_by(&:field_name)
    missing = extractor.class.secret_fields - secrets.keys
    if missing.any?
      raise Stray::ExtractionError, "Bridge requires #{missing.join(', ')} secret(s); none configured"
    end
    extractor.secrets = secrets
  end

  contents = extractor.extract_feed(source.url)
  contents = Array(contents)

  new_count = upsert_items(source, contents, extractor)
  track_empty_polls(source, new_count)
  backfill_source_metadata(source, contents)
  source.recalculate_next_crawl!
  status = new_count > 0 || source.consecutive_empty_polls < 3 ? :ok : :degraded
  source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil, status: status)
rescue NotImplementedError => e
  source.update!(last_error: "Bridge missing extract_feed: #{e.message}", last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
rescue Stray::YtDlp::Error, Stray::ExtractionError
  raise
rescue StandardError => e
  source.update!(last_error: e.message, last_error_at: Time.current, status: :failed)
  reschedule_on_failure!(source)
end

def track_empty_polls(source, new_count)
  if new_count > 0
    source.update!(consecutive_empty_polls: 0)
  else
    source.update!(consecutive_empty_polls: source.consecutive_empty_polls + 1)
  end
end
```

Modify `upsert_items` to return the count of new items (not just `id_by_external_id`):

```ruby
def upsert_items(source, contents, extractor = nil)
  return 0 if contents.empty?

  complete, incomplete = contents.partition { |c| c.duration.present? && c.thumbnail_url.present? && c.published_at.present? }

  id_by_external_id = {}
  id_by_external_id.merge!(upsert_rows(source, complete)) if complete.any?
  id_by_external_id.merge!(upsert_rows(source, incomplete, update_only: NO_MISSING_METADATA_UPDATE)) if incomplete.any?

  existing_ids = source.items.where(external_id: id_by_external_id.keys).pluck(:external_id).to_set
  new_count = id_by_external_id.keys.count { |id| !existing_ids.include?(id) }

  needs_enrichment_ids = []
  contents.each do |content|
    item_id = id_by_external_id[content.external_id]
    apply_extractor_tags(source, item_id, content, extractor)
    EmbeddingJob.perform_later("Item", item_id)
    needs_enrichment_ids << item_id if content.duration.blank? || content.thumbnail_url.blank? || content.published_at.blank?
  end

  MetadataEnrichmentJob.perform_later(source.id, needs_enrichment_ids) if needs_enrichment_ids.any?
  new_count
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```sh
git add app/jobs/source_poll_job.rb test/jobs/source_poll_job_test.rb
git commit -m "feat: track consecutive empty polls and set degraded status

Increments consecutive_empty_polls when a poll produces no new items.
After 3 consecutive empty polls, sets status: :degraded (distinct
from :failed — the bridge ran without error but found nothing).
Resets to 0 and :ok when new items appear."
```

### Task 20: Update `AGENTS.md` terminology

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update all Extractor references to Bridge**

In `AGENTS.md`, find the "Extractor adapter interface" section and rename it to "Bridge interface". Update the code example to show `Stray::Bridge` instead of `Stray::Extractor`. Update the `Stray::ExtractedContent` struct (unchanged, just the namespace context). Update any other references to "extractor" or "Extractors" throughout the file.

- [ ] **Step 2: Commit**

```sh
git add AGENTS.md
git commit -m "docs: update AGENTS.md to use Bridge terminology"
```

### Task 21: Final full test suite run

- [ ] **Step 1: Run the complete test suite**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 2: Run lint and security scans**

Run: `bin/rubocop`
Expected: No new offenses.

Run: `bin/brakeman --no-pager`
Expected: No new warnings.

- [ ] **Step 3: Fix any issues and commit**

```sh
git add -A
git commit -m "test: verify full suite passes after Bridge rename + features"
```
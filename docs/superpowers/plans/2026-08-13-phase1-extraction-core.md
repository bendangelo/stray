# Phase 1: Data Model + Extraction Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data model, extractor interface, yt-dlp runner, and two extractors (YouTube RSS + yt-dlp universal) with a full test suite — no jobs or UI.

**Architecture:** Extractor registry plugin pattern per AGENTS.md. `Stray::YtDlp::Runner` is a pure-Ruby subprocess wrapper (zero Rails deps, future gem extraction). `Stray::Extractors::YoutubeRss` handles YouTube channel RSS feeds. `Stray::Extractors::YtDlp` is the universal fallback for any video site. Models carry `user_id` per the updated AGENTS.md principle. FTS5 via `full_search` gem on `Item` (gem manages the virtual table; we only declare the DSL in the model).

**Tech Stack:** Rails 8.1, Ruby 4.0.5, SQLite, Minitest, faraday + feedjira + nokogiri (new gems), yt-dlp (subprocess), `full_search` gem (already installed).

**Spec:** `docs/superpowers/specs/2026-08-13-extractor-design.md`

---

## File Map

### Migrations (db/migrate/)
- `create_sources.rb` — sources table
- `create_items.rb` — items table
- `create_follows.rb` — follows table
- `create_tags.rb` — tags table
- `create_taggings.rb` — taggings table

### Models (app/models/)
- `source.rb` — Source model with kind enum, due_for_poll scope, recalculate_next_crawl!
- `item.rb` — Item model with state enum, full_search DSL
- `follow.rb` — Follow model
- `tag.rb` — Tag model
- `tagging.rb` — Tagging model with source enum

### Extractor core (lib/stray/)
- `lib/stray/extractor.rb` — Extractor base class, ExtractedContent + CreatorIdentity structs
- `lib/stray/extractor_registry.rb` — registry, find_for(url)
- `lib/stray/yt_dlp/runner.rb` — pure Ruby subprocess wrapper (no Rails deps)
- `lib/stray/yt_dlp/error.rb` — error classes
- `lib/stray/extractors/youtube_rss.rb` — YouTube RSS extractor
- `lib/stray/extractors/yt_dlp.rb` — yt-dlp universal extractor

### Config
- `config/initializers/extractors.rb` — registry registration
- `Gemfile` — add faraday, faraday-follow_redirects, faraday-retry, nokogiri, feedjira
- `Dockerfile` — add Python + yt-dlp
- `AGENTS.md` — update Principle 1 re: user_id

### Tests (test/)
- `test/models/source_test.rb`
- `test/models/item_test.rb`
- `test/models/follow_test.rb`
- `test/models/tagging_test.rb`
- `test/lib/stray/yt_dlp/runner_test.rb`
- `test/lib/stray/extractor_registry_test.rb`
- `test/lib/stray/extractors/youtube_rss_test.rb`
- `test/lib/stray/extractors/yt_dlp_test.rb`
- `test/fixtures/files/youtube_rss.xml` — fixture RSS feed
- `test/fixtures/files/yt_dlp_video.json` — fixture yt-dlp --dump-json output

---

## Task 1: Add gems to Gemfile

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to Gemfile**

Add after the `full_search` gem line (line 26):

```ruby
gem "faraday", "~> 2.0"
gem "faraday-follow_redirects"
gem "faraday-retry"
gem "nokogiri"
gem "feedjira"
```

Add to the `group :test` section (after `selenium-webdriver`):

```ruby
gem "webmock"
```

- [ ] **Step 2: Install gems**

Run: `bundle install`
Expected: gems install successfully, Gemfile.lock updated.

- [ ] **Step 3: Add webmock to test helper**

In `test/test_helper.rb`, add after `require "rails/test_help"`:

```ruby
require "webmock/minitest"
```

Also add `WebMock.disable_net_connect!(allow_localhost: true)` after the require to block external HTTP in tests.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock test/test_helper.rb
git commit -m "feat: add faraday, nokogiri, feedjira, webmock gems for extraction"
```

---

## Task 2: Update AGENTS.md — Principle 1 re: user_id

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Update Principle 1**

In `AGENTS.md`, find the **Principles** section, item 1. Replace:

```
1. **Single user first.** Multi-user/groups is v3, not v1. Do not add user-scoping complexity unless v3 explicitly asks for it.
```

With:

```
1. **Single user first.** The app is built for one user to self-host and dogfood. Models carry `user_id` from v1 to avoid a painful v3 migration, but no multi-user UI, per-user isolation, or access control is built until v3. Treat the `user_id` as a forward-compatible schema decision, not an active feature.
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md principle 1 — user_id in v1 models"
```

---

## Task 3: Create sources table migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_sources.rb`
- Test: `test/models/source_test.rb` (created in Task 8)

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateSources`
Expected: creates `db/migrate/YYYYMMDDHHMMSS_create_sources.rb`

- [ ] **Step 2: Fill in the migration**

```ruby
class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :url, null: false
      t.string :name
      t.string :icon_url
      t.string :external_id
      t.datetime :last_polled_at
      t.datetime :next_crawl_at
      t.integer :poll_interval, default: 1800
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :sources, [:user_id, :external_id, :kind], unique: true
    add_index :sources, [:next_crawl_at, :active], where: "active = true"
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `== CreateSources: migrated` with no errors.

- [ ] **Step 4: Verify schema**

Run: `bin/rails db:migrate:status`
Expected: `CreateSources` shows as `up`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_sources.rb db/schema.rb
git commit -m "feat: add sources table migration"
```

---

## Task 4: Create items table migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_items.rb`
- Test: `test/models/item_test.rb` (created in Task 9)

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateItems`
Expected: creates `db/migrate/YYYYMMDDHHMMSS_create_items.rb`

- [ ] **Step 2: Fill in the migration**

```ruby
class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :source, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.text :content_text
      t.text :content_html
      t.text :summary
      t.string :thumbnail_url
      t.integer :duration
      t.datetime :published_at
      t.datetime :fetched_at
      t.binary :embedding
      t.integer :state, default: 0

      t.timestamps
    end
    add_index :items, [:source_id, :external_id], unique: true
    add_index :items, [:user_id, :state, :published_at]
  end
end
```

Note: `state` is `t.integer :state, default: 0` — Rails 8.1 enum with integer column. The model maps `0 => unseen, 1 => seen, 2 => saved, 3 => hidden`.

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `== CreateItems: migrated` with no errors.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_create_items.rb db/schema.rb
git commit -m "feat: add items table migration"
```

---

## Task 5: Create follows, tags, taggings migrations

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_follows.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_create_tags.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_create_taggings.rb`

- [ ] **Step 1: Generate and fill follows migration**

Run: `bin/rails generate migration CreateFollows`

Fill in:

```ruby
class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.float :weight, default: 1.0

      t.timestamps
    end
    add_index :follows, [:user_id, :source_id], unique: true
  end
end
```

- [ ] **Step 2: Generate and fill tags migration**

Run: `bin/rails generate migration CreateTags`

Fill in:

```ruby
class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.binary :embedding

      t.timestamps
    end
    add_index :tags, [:user_id, :name], unique: true
  end
end
```

- [ ] **Step 3: Generate and fill taggings migration**

Run: `bin/rails generate migration CreateTaggings`

Fill in:

```ruby
class CreateTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :taggings do |t|
      t.references :item, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.integer :source, null: false, default: 0

      t.timestamps
    end
    add_index :taggings, [:item_id, :tag_id, :source], unique: true
  end
end
```

Note: `source` on taggings is an integer enum: `0 => ai_embedding, 1 => ai_llm, 2 => user`.

- [ ] **Step 4: Run all migrations**

Run: `bin/rails db:migrate`
Expected: all three migrate successfully.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_follows.rb db/migrate/*_create_tags.rb db/migrate/*_create_taggings.rb db/schema.rb
git commit -m "feat: add follows, tags, taggings table migrations"
```

---

## Task 6: Create Source model

**Files:**
- Create: `app/models/source.rb`

- [ ] **Step 1: Write the Source model**

```ruby
class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_one :follow, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3 }

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [:user_id, :kind] }

  scope :due_for_poll, -> {
    where(active: true)
      .where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current)
  }

  def recalculate_next_crawl!
    recent = items.order(published_at: :desc).limit(5).pluck(:published_at).compact

    if recent.empty?
      update!(next_crawl_at: 1.hour.from_now)
    elsif recent.first < 1.year.ago
      update!(active: false)
    else
      intervals = recent.each_cons(2).map { |a, b| a - b }.compact
      avg = intervals.empty? ? 1.hour : intervals.sum / intervals.size
      predicted = recent.first + avg
      predicted = [predicted, Time.current + 30.minutes].max
      predicted = [predicted, Time.current + 24.hours].min
      update!(next_crawl_at: predicted)
    end
  end
end
```

- [ ] **Step 2: Verify it loads**

Run: `bin/rails runner "Source.reflect_on_association(:items); puts 'OK'"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add app/models/source.rb
git commit -m "feat: add Source model with kind enum and cadence polling"
```

---

## Task 7: Create Item, Follow, Tag, Tagging models

**Files:**
- Create: `app/models/item.rb`
- Create: `app/models/follow.rb`
- Create: `app/models/tag.rb`
- Create: `app/models/tagging.rb`

- [ ] **Step 1: Write the Item model**

```ruby
class Item < ApplicationRecord
  belongs_to :source
  belongs_to :user
  has_many :taggings, dependent: :destroy

  enum :state, { unseen: 0, seen: 1, saved: 2, hidden: 3 }

  validates :external_id, uniqueness: { scope: :source_id }
  validates :title, :url, presence: true

  full_search do
    field :title, weight: 5
    field :content_text, weight: 1
  end
end
```

The `full_search` block declares the FTS5 index. The gem creates the virtual table automatically (in dev/test via `auto_rebuild_schema = true`). Since `title` and `content_text` are real columns (no `source:` lambda), sync is via SQL triggers — no Ruby callbacks.

- [ ] **Step 2: Write the Follow model**

```ruby
class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :source

  validates :source_id, uniqueness: { scope: :user_id }
end
```

- [ ] **Step 3: Write the Tag model**

```ruby
class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy

  validates :name, uniqueness: { scope: :user_id }
end
```

- [ ] **Step 4: Write the Tagging model**

```ruby
class Tagging < ApplicationRecord
  belongs_to :item
  belongs_to :tag

  enum :source, { ai_embedding: 0, ai_llm: 1, user: 2 }

  validates :tag_id, uniqueness: { scope: [:item_id, :source] }
end
```

- [ ] **Step 5: Prepare FTS table**

Run: `bin/rails full_search:prepare`
Expected: creates the `items_fts` virtual table. No errors.

- [ ] **Step 6: Verify all models load**

Run: `bin/rails runner "Item; Follow; Tag; Tagging; puts 'OK'"`
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add app/models/item.rb app/models/follow.rb app/models/tag.rb app/models/tagging.rb
git commit -m "feat: add Item, Follow, Tag, Tagging models with FTS5 index"
```

---

## Task 8: Source model tests

**Files:**
- Create: `test/models/source_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "valid source with required attributes" do
    source = Source.new(
      user: users(:one),
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123"
    )
    assert source.valid?
  end

  test "invalid without url" do
    source = Source.new(user: users(:one), kind: :youtube_channel)
    assert_not source.valid?
    assert_includes source.errors[:url], "can't be blank"
  end

  test "invalid without kind" do
    source = Source.new(user: users(:one), url: "https://example.com")
    assert_not source.valid?
    assert_includes source.errors[:kind], "can't be blank"
  end

  test "external_id unique per user and kind" do
    Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    duplicate = Source.new(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed2", external_id: "UC123")
    assert_not duplicate.valid?
  end

  test "same external_id allowed for different user" do
    Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    other = Source.new(user: users(:two), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    assert other.valid?
  end

  test "due_for_poll scope returns active sources with past or null next_crawl_at" do
    due = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1", next_crawl_at: 1.hour.ago)
    not_due = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/2", external_id: "UC2", next_crawl_at: 1.hour.from_now)
    inactive = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/3", external_id: "UC3", next_crawl_at: 1.hour.ago, active: false)
    null_crawl = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/4", external_id: "UC4", next_crawl_at: nil)

    result = Source.due_for_poll.to_a
    assert_includes result, due
    assert_includes result, null_crawl
    assert_not_includes result, not_due
    assert_not_includes result, inactive
  end

  test "recalculate_next_crawl! sets 1 hour from now when no items" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    source.recalculate_next_crawl!
    assert_in_delta 1.hour.from_now, source.next_crawl_at, 5.seconds
  end

  test "recalculate_next_crawl! predicts from average interval of recent items" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    now = Time.current
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: now - 4.days)
    source.items.create!(user: users(:one), external_id: "v2", title: "V2", url: "https://example.com/v2", published_at: now - 3.days)
    source.items.create!(user: users(:one), external_id: "v3", title: "V3", url: "https://example.com/v3", published_at: now - 2.days)
    source.items.create!(user: users(:one), external_id: "v4", title: "V4", url: "https://example.com/v4", published_at: now - 1.day)

    source.recalculate_next_crawl!
    # avg interval = 1 day, last published = now - 1.day, predicted = now
    assert_in_delta now, source.next_crawl_at, 5.seconds
  end

  test "recalculate_next_crawl! caps at 24 hours max" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    now = Time.current
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: now - 1.hour)
    source.items.create!(user: users(:one), external_id: "v2", title: "V2", url: "https://example.com/v2", published_at: now - 30.minutes)

    source.recalculate_next_crawl!
    # avg interval = 30min, last = now-30min, predicted = now. But cap min is 30min from now.
    assert source.next_crawl_at <= 30.minutes.from_now + 5.seconds
  end

  test "recalculate_next_crawl! pauses dead sources" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: 2.years.ago)

    source.recalculate_next_crawl!
    assert_not source.active
  end
end
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `bin/rails test test/models/source_test.rb`
Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/models/source_test.rb
git commit -m "test: add Source model tests"
```

---

## Task 9: Item and Tagging model tests

**Files:**
- Create: `test/models/item_test.rb`
- Create: `test/models/tagging_test.rb`
- Create: `test/models/follow_test.rb`

- [ ] **Step 1: Write Item test**

```ruby
require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "valid item with required attributes" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.new(source:, user: users(:one), external_id: "vid1", title: "Test Video", url: "https://example.com/v1")
    assert item.valid?
  end

  test "invalid without title" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.new(source:, user: users(:one), external_id: "vid1", url: "https://example.com/v1")
    assert_not item.valid?
    assert_includes item.errors[:title], "can't be blank"
  end

  test "external_id unique per source" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    duplicate = Item.new(source:, user: users(:one), external_id: "vid1", title: "B", url: "https://example.com/b")
    assert_not duplicate.valid?
  end

  test "same external_id allowed for different source" do
    s1 = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/1", external_id: "UC1")
    s2 = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/2", external_id: "UC2")
    Item.create!(source: s1, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    other = Item.new(source: s2, user: users(:one), external_id: "vid1", title: "B", url: "https://example.com/b")
    assert other.valid?
  end

  test "default state is unseen" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    assert item.unseen?
  end

  test "state transitions" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    item.seen!
    assert item.seen?
    item.saved!
    assert item.saved?
    item.hidden!
    assert item.hidden?
  end

  test "full_search finds by title" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby on Rails Tutorial", url: "https://example.com/v1", content_text: "Learn web development")
    Item.create!(source:, user: users(:one), external_id: "v2", title: "Cooking Pasta", url: "https://example.com/v2", content_text: "Italian recipes")

    results = Item.search("ruby rails")
    assert_includes results.map(&:title), "Ruby on Rails Tutorial"
    assert_not_includes results.map(&:title), "Cooking Pasta"
  end
end
```

- [ ] **Step 2: Write Follow test**

```ruby
require "test_helper"

class FollowTest < ActiveSupport::TestCase
  test "valid follow" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    follow = Follow.new(user: users(:one), source:)
    assert follow.valid?
  end

  test "unique per user and source" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source:)
    duplicate = Follow.new(user: users(:one), source:)
    assert_not duplicate.valid?
  end

  test "default weight is 1.0" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    follow = Follow.create!(user: users(:one), source:)
    assert_equal 1.0, follow.weight
  end
end
```

- [ ] **Step 3: Write Tagging test**

```ruby
require "test_helper"

class TaggingTest < ActiveSupport::TestCase
  test "valid tagging" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    tagging = Tagging.new(item:, tag:, source: :user)
    assert tagging.valid?
  end

  test "tag unique per item and source type" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    Tagging.create!(item:, tag:, source: :user)
    duplicate = Tagging.new(item:, tag:, source: :user)
    assert_not duplicate.valid?
  end

  test "same tag allowed with different source type" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    Tagging.create!(item:, tag:, source: :user)
    other = Tagging.new(item:, tag:, source: :ai_embedding)
    assert other.valid?
  end
end
```

- [ ] **Step 4: Run all model tests**

Run: `bin/rails test test/models/`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add test/models/item_test.rb test/models/follow_test.rb test/models/tagging_test.rb
git commit -m "test: add Item, Follow, Tagging model tests"
```

---

## Task 10: Extractor base class and structs

**Files:**
- Create: `lib/stray/extractor.rb`

- [ ] **Step 1: Write the extractor base class**

```ruby
module Stray
  ExtractedContent = Data.define(
    :title, :content_text, :content_html,
    :thumbnail_url, :published_at,
    :external_id, :duration,
    :creator_identity
  )

  CreatorIdentity = Data.define(:name, :url, :external_id, :thumbnail_url)

  class Extractor
    def self.matches?(url)
      raise NotImplementedError
    end

    def extract(url)
      raise NotImplementedError
    end
  end
end
```

- [ ] **Step 2: Verify it loads**

Run: `bin/rails runner "Stray::Extractor; Stray::ExtractedContent; Stray::CreatorIdentity; puts 'OK'"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add lib/stray/extractor.rb
git commit -m "feat: add Extractor base class and ExtractedContent/CreatorIdentity structs"
```

---

## Task 11: Extractor registry

**Files:**
- Create: `lib/stray/extractor_registry.rb`
- Create: `test/lib/stray/extractor_registry_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Stray::ExtractorRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Stray::Extractor
    def self.matches?(url)
      URI.parse(url).path == "/feeds/videos.xml"
    rescue URI::InvalidURIError
      false
    end

    def extract(url)
      Stray::ExtractedContent.new(title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil)
    end
  end

  class FakeYtDlp < Stray::Extractor
    def self.matches?(url)
      true
    end

    def extract(url)
      Stray::ExtractedContent.new(title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil)
    end
  end

  def setup
    @original_extractors = Stray::ExtractorRegistry.instance_variable_get(:@extractors)
    Stray::ExtractorRegistry.reset!
    Stray::ExtractorRegistry.register(FakeYoutubeRss)
    Stray::ExtractorRegistry.register(FakeYtDlp)
  end

  def teardown
    Stray::ExtractorRegistry.reset!
    @original_extractors&.each { |e| Stray::ExtractorRegistry.register(e) }
  end

  test "find_for returns first matching extractor" do
    extractor = Stray::ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYoutubeRss, extractor.class
  end

  test "find_for falls back to universal extractor" do
    extractor = Stray::ExtractorRegistry.find_for("https://bitchute.com/video/abc123")
    assert_equal FakeYtDlp, extractor.class
  end

  test "find_for returns nil when nothing matches" do
    Stray::ExtractorRegistry.reset!
    assert_nil Stray::ExtractorRegistry.find_for("https://example.com")
  end

  test "registration order determines priority" do
    Stray::ExtractorRegistry.reset!
    Stray::ExtractorRegistry.register(FakeYtDlp)
    Stray::ExtractorRegistry.register(FakeYoutubeRss)
    extractor = Stray::ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYtDlp, extractor.class
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/extractor_registry_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::ExtractorRegistry`

- [ ] **Step 3: Write the registry**

```ruby
module Stray
  class ExtractorRegistry
    @extractors = []

    class << self
      def register(extractor_class)
        @extractors << extractor_class unless @extractors.include?(extractor_class)
      end

      def find_for(url)
        @extractors.find { |klass| klass.matches?(url) }&.new
      end

      def all
        @extractors.dup
      end

      def reset!
        @extractors = []
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/extractor_registry_test.rb`
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/extractor_registry.rb test/lib/stray/extractor_registry_test.rb
git commit -m "feat: add ExtractorRegistry with find_for URL matching"
```

---

## Task 12: yt-dlp error classes

**Files:**
- Create: `lib/stray/yt_dlp/error.rb`

- [ ] **Step 1: Write error classes**

```ruby
module Stray
  module YtDlp
    class Error < StandardError; end
    class Timeout < Error; end
    class NotFound < Error; end
    class ExtractionFailed < Error; end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/stray/yt_dlp/error.rb
git commit -m "feat: add yt-dlp error classes"
```

---

## Task 13: yt-dlp Runner — single_video

**Files:**
- Create: `lib/stray/yt_dlp/runner.rb`
- Create: `test/lib/stray/yt_dlp/runner_test.rb`
- Create: `test/fixtures/files/yt_dlp_video.json`

- [ ] **Step 1: Create fixture JSON file**

This is real yt-dlp `--dump-json` output (trimmed to fields we use):

```json
{
  "id": "dQw4w9WgXcQ",
  "title": "Rick Astley - Never Gonna Give You Up (Official Music Video)",
  "description": "The official video for Never Gonna Give You Up by Rick Astley.",
  "thumbnail": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
  "duration": 213,
  "upload_date": "20091025",
  "channel": "Rick Astley",
  "channel_id": "UCuAXFkgsw1L7xaCfnd5JJOw",
  "channel_url": "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
  "thumbnails": [
    {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg", "width": 1280, "height": 720}
  ]
}
```

- [ ] **Step 2: Write the failing test**

```ruby
require "test_helper"

class Stray::YtDlp::RunnerTest < ActiveSupport::TestCase
  FIXTURE_PATH = File.expand_path("../../../fixtures/files/yt_dlp_video.json", __dir__)

  def setup
    @json = File.read(FIXTURE_PATH)
    @runner = Stray::YtDlp::Runner.new
  end

  test "single_video parses JSON output" do
    Open3.stub(:capture3, ["", @json, Open3::Status.new(true)]) do
      result = @runner.single_video("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      assert_equal "dQw4w9WgXcQ", result["id"]
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", result["title"]
      assert_equal 213, result["duration"]
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result["channel_id"]
    end
  end

  test "single_video raises ExtractionFailed on non-zero exit" do
    Open3.stub(:capture3, ["", "", Open3::Status.new(false)]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "single_video raises ExtractionFailed on invalid JSON" do
    Open3.stub(:capture3, ["", "not json", Open3::Status.new(true)]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "constructor accepts binary and timeout options" do
    runner = Stray::YtDlp::Runner.new(binary: "/usr/local/bin/yt-dlp", timeout: 60)
    assert_equal "/usr/local/bin/yt-dlp", runner.binary
    assert_equal 60, runner.timeout
  end

  test "default binary is yt-dlp" do
    assert_equal "yt-dlp", @runner.binary
  end

  test "default timeout is 30" do
    assert_equal 30, @runner.timeout
  end
end
```

Note: `Open3::Status.new(true)` is a helper. If `Open3::Status` doesn't exist, use a stub object that responds to `success?`. We'll define a minimal status stub in the test helper or use `OpenStruct.new(success?: true)`.

- [ ] **Step 3: Adjust test to use a status stub**

If `Open3::Status` is not available, replace the `Open3::Status.new(true)` / `Open3::Status.new(false)` calls with `status_success` / `status_failure` helper methods:

```ruby
# Add to the test class:
def status_success
  OpenStruct.new(success?: true)
end

def status_failure
  OpenStruct.new(success?: false)
end
```

Then replace `Open3::Status.new(true)` with `status_success` and `Open3::Status.new(false)` with `status_failure` throughout the test. Also add `require "ostruct"` at the top.

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/yt_dlp/runner_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::YtDlp::Runner`

- [ ] **Step 5: Write the Runner**

```ruby
require "open3"
require "json"

require_relative "error"

module Stray
  module YtDlp
    class Runner
      attr_reader :binary, :timeout

      def initialize(binary: "yt-dlp", timeout: 30)
        @binary = binary
        @timeout = timeout
      end

      def single_video(url)
        stdout, _stderr, status = run_command("--dump-json", url)
        raise ExtractionFailed, "yt-dlp exited with non-zero status" unless status.success?

        parse_json(stdout)
      rescue Errno::ENOENT
        raise Error, "yt-dlp binary not found: #{binary}"
      end

      def channel_listings(url)
        stdout, _stderr, status = run_command("--flat-playlist", "--dump-json", url)
        raise ExtractionFailed, "yt-dlp exited with non-zero status" unless status.success?

        stdout.lines.map { |line| parse_json(line) }
      end

      private

      def run_command(*args)
        Open3.capture3(binary, *args)
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ExtractionFailed, "yt-dlp returned invalid JSON: #{e.message}"
      end
    end
  end
end
```

Note: this file has NO Rails dependencies. It uses only `open3`, `json`, and stdlib. The `require_relative "error"` keeps it standalone. In the Rails app it's also autoloaded via `config.autoload_lib`, but the `require` calls make it work outside Rails too (for future gem extraction).

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/yt_dlp/runner_test.rb`
Expected: all 6 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/stray/yt_dlp/runner.rb test/lib/stray/yt_dlp/runner_test.rb test/fixtures/files/yt_dlp_video.json
git commit -m "feat: add yt-dlp Runner with single_video and channel_listings"
```

---

## Task 14: yt-dlp Runner — channel_listings test

**Files:**
- Modify: `test/lib/stray/yt_dlp/runner_test.rb`

- [ ] **Step 1: Add channel_listings test to the existing test file**

Add these tests to `Stray::YtDlp::RunnerTest`:

```ruby
  test "channel_listings parses multiple JSON lines" do
    fixture1 = '{"id":"vid1","title":"Video 1","url":"https://example.com/v1"}'
    fixture2 = '{"id":"vid2","title":"Video 2","url":"https://example.com/v2"}'
    multi_json = "#{fixture1}\n#{fixture2}\n"

    Open3.stub(:capture3, ["", multi_json, status_success]) do
      result = @runner.channel_listings("https://bitchute.com/channel/abc")
      assert_equal 2, result.size
      assert_equal "vid1", result[0]["id"]
      assert_equal "vid2", result[1]["id"]
    end
  end

  test "channel_listings returns empty array for no output" do
    Open3.stub(:capture3, ["", "", status_success]) do
      result = @runner.channel_listings("https://example.com/channel/empty")
      assert_equal [], result
    end
  end

  test "channel_listings raises ExtractionFailed on non-zero exit" do
    Open3.stub(:capture3, ["", "", status_failure]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.channel_listings("https://example.com/channel/bad")
      end
    end
  end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/yt_dlp/runner_test.rb`
Expected: all tests PASS (existing + 3 new).

- [ ] **Step 3: Commit**

```bash
git add test/lib/stray/yt_dlp/runner_test.rb
git commit -m "test: add channel_listings tests for yt-dlp Runner"
```

---

## Task 15: YouTube RSS fixture

**Files:**
- Create: `test/fixtures/files/youtube_rss.xml`

- [ ] **Step 1: Create the fixture RSS file**

This is a real YouTube RSS feed structure (with test data):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/"
      xmlns="http://www.w3.org/2005/Atom">
  <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw"/>
  <id>yt:channel:UCuAXFkgsw1L7xaCfnd5JJOw</id>
  <yt:channelId>UCuAXFkgsw1L7xaCfnd5JJOw</yt:channelId>
  <title>Rick Astley</title>
  <link rel="alternate" href="https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"/>
  <author>
    <name>Rick Astley</name>
    <uri>https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw</uri>
  </author>
  <published>2009-10-25T00:00:00+00:00</published>

  <entry>
    <id>yt:video:dQw4w9WgXcQ</id>
    <yt:videoId>dQw4w9WgXcQ</yt:videoId>
    <yt:channelId>UCuAXFkgsw1L7xaCfnd5JJOw</yt:channelId>
    <title>Rick Astley - Never Gonna Give You Up (Official Music Video)</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"/>
    <author>
      <name>Rick Astley</name>
      <uri>https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw</uri>
    </author>
    <published>2009-10-25T00:00:00+00:00</published>
    <updated>2024-01-15T00:00:00+00:00</updated>
    <media:group>
      <media:title>Rick Astley - Never Gonna Give You Up (Official Music Video)</media:title>
      <media:content url="https://www.youtube.com/watch?v=dQw4w9WgXcQ" type="text/html" width="640" height="390"/>
      <media:thumbnail url="https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg" width="320" height="180"/>
      <media:description>The official video for Never Gonna Give You Up by Rick Astley.</media:description>
      <media:community>
        <media:starRating count="2000000" average="5.0" min="1" max="5"/>
        <media:statistics views="1500000000"/>
      </media:community>
    </media:group>
  </entry>

  <entry>
    <id>yt:video:abc123def</id>
    <yt:videoId>abc123def</yt:videoId>
    <yt:channelId>UCuAXFkgsw1L7xaCfnd5JJOw</yt:channelId>
    <title>Rick Astley - Together Forever</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=abc123def"/>
    <author>
      <name>Rick Astley</name>
      <uri>https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw</uri>
    </author>
    <published>2024-06-01T00:00:00+00:00</published>
    <updated>2024-06-01T00:00:00+00:00</updated>
    <media:group>
      <media:title>Rick Astley - Together Forever</media:title>
      <media:content url="https://www.youtube.com/watch?v=abc123def" type="text/html" width="640" height="390"/>
      <media:thumbnail url="https://i.ytimg.com/vi/abc123def/mqdefault.jpg" width="320" height="180"/>
      <media:description>Another great hit from Rick Astley.</media:description>
      <media:community>
        <media:starRating count="500000" average="4.8" min="1" max="5"/>
        <media:statistics views="50000000"/>
      </media:community>
    </media:group>
  </entry>
</feed>
```

- [ ] **Step 2: Commit**

```bash
git add test/fixtures/files/youtube_rss.xml
git commit -m "test: add YouTube RSS fixture"
```

---

## Task 16: YouTube RSS extractor

**Files:**
- Create: `lib/stray/extractors/youtube_rss.rb`
- Create: `test/lib/stray/extractors/youtube_rss_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Stray::Extractors::YoutubeRssTest < ActiveSupport::TestCase
  FIXTURE_PATH = File.expand_path("../../../fixtures/files/youtube_rss.xml", __dir__)

  test "matches? returns true for YouTube RSS feed URLs" do
    assert Stray::Extractors::YoutubeRss.matches?("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert Stray::Extractors::YoutubeRss.matches?("https://youtube.com/feeds/videos.xml?channel_id=UC123")
  end

  test "matches? returns false for non-RSS YouTube URLs" do
    assert_not Stray::Extractors::YoutubeRss.matches?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert_not Stray::Extractors::YoutubeRss.matches?("https://www.youtube.com/@channel")
    assert_not Stray::Extractors::YoutubeRss.matches?("https://www.youtube.com/channel/UC123")
  end

  test "matches? returns false for non-YouTube URLs" do
    assert_not Stray::Extractors::YoutubeRss.matches?("https://example.com/feed.xml")
    assert_not Stray::Extractors::YoutubeRss.matches?("https://bitchute.com/channel/abc")
  end

  test "extract returns array of ExtractedContent from RSS feed" do
    rss_xml = File.read(FIXTURE_PATH)
    stub_request(:get, /youtube\.com\/feeds\/videos\.xml/)
      .to_return(body: rss_xml, headers: { "Content-Type" => "application/atom+xml" })

    extractor = Stray::Extractors::YoutubeRss.new
    results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

    assert_equal 2, results.size
    first = results.first
    assert_equal "dQw4w9WgXcQ", first.external_id
    assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", first.title
    assert_equal "The official video for Never Gonna Give You Up by Rick Astley.", first.content_text
    assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg", first.thumbnail_url
    assert_equal Time.parse("2009-10-25T00:00:00+00:00"), first.published_at
    assert_nil first.duration
  end

  test "extract includes creator_identity from feed author" do
    rss_xml = File.read(FIXTURE_PATH)
    stub_request(:get, /youtube\.com\/feeds\/videos\.xml/)
      .to_return(body: rss_xml, headers: { "Content-Type" => "application/atom+xml" })

    extractor = Stray::Extractors::YoutubeRss.new
    results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

    creator = results.first.creator_identity
    assert_equal "Rick Astley", creator.name
    assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", creator.url
    assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", creator.external_id
  end
end
```

Note: `stub_request` is from the `webmock` gem, added in Task 1. The test helper already requires `webmock/minitest`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/extractors/youtube_rss_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::Extractors::YoutubeRss`

- [ ] **Step 3: Write the YoutubeRss extractor**

```ruby
require "feedjira"

module Stray
  module Extractors
    class YoutubeRss < Stray::Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("youtube.com") && uri.path == "/feeds/videos.xml"
      rescue URI::InvalidURIError
        false
      end

      def extract(url)
        response = http_client.get(url)
        feed = Feedjira.parse(response.body)

        feed.entries.map do |entry|
          ExtractedContent.new(
            title: entry.title,
            content_text: entry.content || entry.summary,
            content_html: nil,
            thumbnail_url: extract_thumbnail(entry),
            published_at: entry.published,
            external_id: entry.entry_id.sub("yt:video:", ""),
            duration: nil,
            creator_identity: extract_creator(feed)
          )
        end
      end

      private

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects
          conn.adapter :net_http
        end
      end

      def extract_thumbnail(entry)
        entry.image&.url || entry.media&.thumbnail&.url
      rescue NoMethodError
        nil
      end

      def extract_creator(feed)
        CreatorIdentity.new(
          name: feed.title,
          url: feed.url,
          external_id: feed.channel_id,
          thumbnail_url: nil
        )
      rescue NoMethodError
        nil
      end
    end
  end
end
```

Note: Feedjira's YouTube RSS parsing may differ from the generic Feedjira API. The `entry.entry_id` for YouTube RSS is `yt:video:VIDEO_ID`. Feedjira may expose `entry.url` or `entry.links` for the watch URL. If Feedjira doesn't parse YouTube's media extensions natively, we may need Nokogiri parsing as a fallback. The test will reveal the exact API.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/extractors/youtube_rss_test.rb`
Expected: all 5 tests PASS.

If Feedjira doesn't expose `feed.channel_id` or `entry.entry_id` in the expected way, adjust the extractor to use Nokogiri directly on the RSS XML. A Nokogiri fallback would look like:

```ruby
def extract(url)
  response = http_client.get(url)
  doc = Nokogiri::XML(response.body)
  doc.remove_namespaces!

  channel_id = doc.at_css("channelId")&.text
  channel_name = doc.at_css("feed > title")&.text
  channel_url = doc.at_css("feed > link[rel=alternate]")&.[]("href")

  doc.css("entry").map do |entry|
    ExtractedContent.new(
      title: entry.at_css("title")&.text,
      content_text: entry.at_css("description")&.text,
      content_html: nil,
      thumbnail_url: entry.at_css("thumbnail")&.[]("url"),
      published_at: Time.parse(entry.at_css("published")&.text),
      external_id: entry.at_css("videoId")&.text,
      duration: nil,
      creator_identity: CreatorIdentity.new(name: channel_name, url: channel_url, external_id: channel_id, thumbnail_url: nil)
    )
  end
end
```

Use whichever approach passes the tests. The Nokogiri approach is more robust for YouTube's custom extensions.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/extractors/youtube_rss.rb test/lib/stray/extractors/youtube_rss_test.rb
git commit -m "feat: add YouTube RSS extractor with Feedjira"
```

---

## Task 17: yt-dlp extractor

**Files:**
- Create: `lib/stray/extractors/yt_dlp.rb`
- Create: `test/lib/stray/extractors/yt_dlp_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"
require "ostruct"

class Stray::Extractors::YtDlpTest < ActiveSupport::TestCase
  FIXTURE_PATH = File.expand_path("../../../fixtures/files/yt_dlp_video.json", __dir__)

  def setup
    @json = File.read(FIXTURE_PATH)
    @data = JSON.parse(@json)
  end

  def status_success
    OpenStruct.new(success?: true)
  end

  test "matches? returns true for any URL (universal fallback)" do
    assert Stray::Extractors::YtDlp.matches?("https://bitchute.com/video/abc123")
    assert Stray::Extractors::YtDlp.matches?("https://rumble.com/vabc123.html")
    assert Stray::Extractors::YtDlp.matches?("https://vimeo.com/12345")
  end

  test "matches? returns false for YouTube RSS feed URLs (handled by YoutubeRss)" do
    assert_not Stray::Extractors::YtDlp.matches?("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
  end

  test "extract returns ExtractedContent with video metadata" do
    Open3.stub(:capture3, ["", @json, status_success]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://bitchute.com/video/abc123")

      assert_equal "dQw4w9WgXcQ", result.external_id
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", result.title
      assert_equal "The official video for Never Gonna Give You Up by Rick Astley.", result.content_text
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg", result.thumbnail_url
      assert_equal 213, result.duration
      assert_equal Time.strptime("20091025", "%Y%m%d"), result.published_at
    end
  end

  test "extract includes creator_identity" do
    Open3.stub(:capture3, ["", @json, status_success]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://bitchute.com/video/abc123")

      creator = result.creator_identity
      assert_equal "Rick Astley", creator.name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", creator.url
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", creator.external_id
    end
  end

  test "extract raises ExtractionFailed when yt-dlp fails" do
    Open3.stub(:capture3, ["", "", OpenStruct.new(success?: false)]) do
      extractor = Stray::Extractors::YtDlp.new
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        extractor.extract("https://example.com/video")
      end
    end
  end

  test "extract_channel returns array of lightweight ExtractedContent" do
    listing1 = '{"id":"vid1","title":"Video 1","url":"https://example.com/v1","channel":"Test","channel_id":"C1","channel_url":"https://example.com/c1"}'
    listing2 = '{"id":"vid2","title":"Video 2","url":"https://example.com/v2","channel":"Test","channel_id":"C1","channel_url":"https://example.com/c1"}'
    multi_json = "#{listing1}\n#{listing2}\n"

    Open3.stub(:capture3, ["", multi_json, status_success]) do
      extractor = Stray::Extractors::YtDlp.new
      results = extractor.extract_channel("https://bitchute.com/channel/abc")

      assert_equal 2, results.size
      assert_equal "vid1", results[0].external_id
      assert_equal "Video 1", results[0].title
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/extractors/yt_dlp_test.rb`
Expected: FAIL with `NameError: uninitialized constant Stray::Extractors::YtDlp`

- [ ] **Step 3: Write the YtDlp extractor**

```ruby
require "time"

module Stray
  module Extractors
    class YtDlp < Stray::Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        return false if uri.host&.end_with?("youtube.com") && uri.path == "/feeds/videos.xml"

        true
      rescue URI::InvalidURIError
        false
      end

      def extract(url)
        data = runner.single_video(url)

        ExtractedContent.new(
          title: data["title"],
          content_text: data["description"],
          content_html: nil,
          thumbnail_url: data["thumbnail"],
          published_at: parse_upload_date(data["upload_date"]),
          external_id: data["id"],
          duration: data["duration"],
          creator_identity: extract_creator(data)
        )
      end

      def extract_channel(url)
        entries = runner.channel_listings(url)

        entries.map do |data|
          ExtractedContent.new(
            title: data["title"],
            content_text: nil,
            content_html: nil,
            thumbnail_url: data.dig("thumbnails", 0, "url"),
            published_at: parse_upload_date(data["upload_date"]),
            external_id: data["id"],
            duration: data["duration"],
            creator_identity: extract_creator(data)
          )
        end
      end

      private

      def runner
        @runner ||= Stray::YtDlp::Runner.new
      end

      def extract_creator(data)
        return nil unless data["channel_id"] || data["channel"]

        CreatorIdentity.new(
          name: data["channel"],
          url: data["channel_url"],
          external_id: data["channel_id"],
          thumbnail_url: nil
        )
      end

      def parse_upload_date(date_str)
        return nil unless date_str

        Time.strptime(date_str, "%Y%m%d").utc
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/extractors/yt_dlp_test.rb`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/stray/extractors/yt_dlp.rb test/lib/stray/extractors/yt_dlp_test.rb
git commit -m "feat: add yt-dlp universal video extractor"
```

---

## Task 18: Extractor registry initializer

**Files:**
- Create: `config/initializers/extractors.rb`

- [ ] **Step 1: Write the initializer**

```ruby
Rails.application.config.to_prepare do
  Stray::ExtractorRegistry.reset!
  Stray::ExtractorRegistry.register(Stray::Extractors::YoutubeRss)
  Stray::ExtractorRegistry.register(Stray::Extractors::YtDlp)
end
```

The `to_prepare` block runs on every request in development and once in production. `reset!` ensures a clean state before re-registering (important for dev reloads).

- [ ] **Step 2: Verify it loads**

Run: `bin/rails runner "puts Stray::ExtractorRegistry.all.inspect"`
Expected: `[Stray::Extractors::YoutubeRss, Stray::Extractors::YtDlp]`

- [ ] **Step 3: Verify find_for dispatches correctly**

Run: `bin/rails runner "puts Stray::ExtractorRegistry.find_for('https://www.youtube.com/feeds/videos.xml?channel_id=UC123').class; puts Stray::ExtractorRegistry.find_for('https://bitchute.com/video/abc').class"`
Expected:
```
Stray::Extractors::YoutubeRss
Stray::Extractors::YtDlp
```

- [ ] **Step 4: Commit**

```bash
git add config/initializers/extractors.rb
git commit -m "feat: add extractors initializer with registry registration"
```

---

## Task 19: Dockerfile — add Python + yt-dlp

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Add Python + yt-dlp to the base stage**

In `Dockerfile`, find the "Install base packages" RUN block (around line 18-21). Add `python3 python3-pip` to the apt-get install list, then add a pip install for yt-dlp:

Change:
```dockerfile
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

To:
```dockerfile
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 python3 python3-pip && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    pip3 install --break-system-packages yt-dlp && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

- [ ] **Step 2: Verify Docker build (optional — only if Docker is available)**

Run: `docker build -t stray-test .`
Expected: build succeeds. If Docker is not available locally, skip this step — CI will catch it.

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Python and yt-dlp to Dockerfile"
```

---

## Task 20: Final verification — full test suite + lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: all tests PASS (existing auth tests + new model/lib tests).

- [ ] **Step 2: Run RuboCop**

Run: `bin/rubocop`
Expected: no offenses. If there are offenses, fix them and re-run.

- [ ] **Step 3: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: no security warnings related to new code.

- [ ] **Step 4: Verify console workflow**

Run: `bin/rails console`

```ruby
# Create a source
s = Source.create!(user: User.first, kind: :youtube_channel, url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest", external_id: "UCtest")
s.recalculate_next_crawl!
puts s.next_crawl_at

# Check registry
Stray::ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UCtest").class
Stray::ExtractorRegistry.find_for("https://bitchute.com/video/abc").class

# Check FTS
Item.create!(source: s, user: User.first, external_id: "v1", title: "Test Video", url: "https://example.com/v1", content_text: "test content")
Item.search("test").to_a
```

Expected: all commands work without errors.

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint and verification fixes for Phase 1"
```

If no fixes needed, skip this step.

---

## Summary

After completing all 20 tasks, Phase 1 delivers:

| Deliverable | Location |
|---|---|
| 5 migrations (sources, items, follows, tags, taggings) | `db/migrate/` |
| 5 models with enums, validations, associations, FTS5 | `app/models/` |
| Extractor base + structs | `lib/stray/extractor.rb` |
| ExtractorRegistry | `lib/stray/extractor_registry.rb` |
| yt-dlp Runner (pure Ruby) | `lib/stray/yt_dlp/runner.rb` |
| yt-dlp error classes | `lib/stray/yt_dlp/error.rb` |
| YoutubeRss extractor | `lib/stray/extractors/youtube_rss.rb` |
| YtDlp extractor | `lib/stray/extractors/yt_dlp.rb` |
| Registry initializer | `config/initializers/extractors.rb` |
| Gemfile additions | `Gemfile` |
| Dockerfile change | `Dockerfile` |
| AGENTS.md update | `AGENTS.md` |
| Test suite (models + lib) | `test/` |

No jobs or UI — that's Phase 2 and Phase 3. Everything is verifiable via `bin/rails console` and `bin/rails test`.
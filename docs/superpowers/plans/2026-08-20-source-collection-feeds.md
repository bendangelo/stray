# Source Feeds + Collection Feed Consistency — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add unauthenticated, slug-gated RSS 2.0 + Stray JSON manifest endpoints for every `Source` (mirroring the existing `Collection` output), and make collection + source feeds include all item states (no longer exclude `hidden`).

**Architecture:** Add a 24-char `slug` to `Source` via `has_secure_token`, backfill existing rows with a data migration, expose `/s/:slug/feed.xml` and `/s/:slug/manifest.json` under `allow_unauthenticated_access`. Extract the shared manifest item-payload and cursor logic into two modules (`FeedItemPayload`, `ManifestCursor`) used by both `CollectionManifest` and a new `SourceManifest` service. Drop `where.not(state: :hidden)` from `CollectionManifest` and the collection `feed` action.

**Tech Stack:** Rails 8, Ruby 4.0.5, SQLite, Minitest, Builder (XML), `has_secure_token`, `data_migrate` gem.

**Spec:** `docs/superpowers/specs/2026-08-20-source-collection-feeds-design.md`

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `db/migrate/<ts>_add_slug_to_sources.rb` | Add `slug` column + unique index | Create |
| `db/data/<ts>_backfill_source_slugs.rb` | Assign 24-char tokens to existing sources | Create |
| `app/models/source.rb` | `has_secure_token :slug`, validations | Modify |
| `app/services/feed_item_payload.rb` | Shared item → hash payload module | Create |
| `app/services/manifest_cursor.rb` | Shared cursor encode/decode + next_url module | Create |
| `app/services/collection_manifest.rb` | Use both modules; drop hidden filter | Modify |
| `app/services/source_manifest.rb` | Source-side manifest, format `stray-source` | Create |
| `app/controllers/sources_controller.rb` | `public_show`, `feed`, `manifest`, `rotate_slug` | Modify |
| `app/views/sources/feed.xml.builder` | RSS 2.0 for a source | Create |
| `app/views/sources/public_show.html.erb` | Public source landing (minimal) | Create |
| `config/routes.rb` | `/s/:slug/...` routes + `rotate_slug` | Modify |
| `test/fixtures/sources.yml` | Add `slug` to fixtures | Modify |
| `test/fixtures/items.yml` | Ensure a `hidden` item on a collection's source | (exists) |
| `test/services/collection_manifest_test.rb` | Update hidden-item assertion | Modify |
| `test/services/source_manifest_test.rb` | New | Create |
| `test/services/feed_item_payload_test.rb` | New | Create |
| `test/services/manifest_cursor_test.rb` | New | Create |
| `test/controllers/sources_controller_test.rb` | Add feed/manifest/rotate tests | Modify |
| `test/controllers/collections_controller_test.rb` | Add hidden-included assertion | Modify |

Order of tasks follows dependency: schema → model → shared modules → collection manifest refactor → source manifest → controllers/views → routes → fixture + test updates.

---

### Task 1: Add `slug` column to sources

**Files:**
- Create: `db/migrate/<ts>_add_slug_to_sources.rb`

- [ ] **Step 1: Generate the migration**

Run:
```sh
bin/rails g migration AddSlugToSources slug:string
```

Expected: a new file under `db/migrate/` named `..._add_slug_to_sources.rb`.

- [ ] **Step 2: Edit the migration to enforce NOT NULL and uniqueness**

Open the generated file and replace its body with:

```ruby
class AddSlugToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :slug, :string
    add_index :sources, :slug, unique: true
  end
end
```

We do NOT mark the column `null: false` in the schema migration because existing rows would fail the constraint before the data migration backfills them. The model validation + backfill enforce non-nullability in practice; a follow-up schema migration could harden this if desired (out of scope here).

- [ ] **Step 3: Run the migration**

Run:
```sh
bin/rails db:migrate
```

Expected: `add_column :sources, :slug, :string` and `add_index :sources, :slug, unique: true` succeed.

- [ ] **Step 4: Verify schema**

Run:
```sh
bin/rails db:migrate:status
```

Expected: the new migration is up. Inspect `db/schema.rb` — the `sources` table should now list `t.string "slug"` and `t.index [...], name: "index_sources_on_slug", unique: true`.

- [ ] **Step 5: Commit**

```sh
git add db/migrate/<ts>_add_slug_to_sources.rb db/schema.rb
git commit -m "db: add slug column to sources"
```

---

### Task 2: Backfill slugs for existing sources

**Files:**
- Create: `db/data/<ts>_backfill_source_slugs.rb`

- [ ] **Step 1: Generate the data migration**

Run:
```sh
bin/rails g data_migration BackfillSourceSlugs
```

Expected: a new file under `db/data/` named `..._backfill_source_slugs.rb`.

- [ ] **Step 2: Write the backfill**

Replace the file's body with:

```ruby
# frozen_string_literal: true

class BackfillSourceSlugs < ActiveRecord::Migration[8.1]
  def up
    Source.where(slug: nil).find_each do |source|
      source.regenerate_token(:slug)
      source.save!(validate: false)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

`validate: false` because the model validations (added in Task 3) may not be loaded yet at migration time and because we want the backfill to be robust to any unrelated validation failures. `regenerate_token(:slug)` is the `has_secure_token` helper for a named token — it works whether or not the model has declared `has_secure_token` yet, because it just sets the column to a new SecureRandom token of the configured length. To be safe, Task 3 (model change) is committed before this migration runs in production; but the backfill is defensive.

Actually — `regenerate_token(:slug)` requires `has_secure_token :slug` to be declared on the model to know the token length. Since Task 3 declares it, and migrations run after the model file is updated, this is fine. But to be fully independent of model state, use a direct token assignment:

```ruby
# frozen_string_literal: true

class BackfillSourceSlugs < ActiveRecord::Migration[8.1]
  TOKEN_LENGTH = 24

  def up
    Source.where(slug: nil).find_each do |source|
      source.update_column(:slug, SecureRandom.alphanumeric(TOKEN_LENGTH))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

`SecureRandom.alphanumeric(24)` gives 24 chars from `[A-Za-z0-9]` (~142 bits entropy), matching `has_secure_token`'s default generator. `update_column` skips validations and callbacks, which is what we want in a data migration.

- [ ] **Step 3: Run the data migration**

Run:
```sh
bin/rails data:migrate
```

Expected: no output errors. Verify with `bin/rails runner 'puts Source.where(slug: nil).count'` — should print `0`.

- [ ] **Step 4: Commit**

```sh
git add db/data/<ts>_backfill_source_slugs.rb
git commit -m "db: backfill source slugs"
```

---

### Task 3: Declare `has_secure_token :slug` on Source

**Files:**
- Modify: `app/models/source.rb:1-12`

- [ ] **Step 1: Add the secure token and validation**

In `app/models/source.rb`, immediately after the `enum :status, ...` line (line 9), add:

```ruby
  has_secure_token :slug, length: 24
  validates :slug, presence: true, uniqueness: true
```

The file's top should now read:

```ruby
class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :collection_memberships, dependent: :destroy
  has_one :remote_collection, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4, rumble_channel: 5, bitchute_channel: 6, odysee_channel: 7, peertube_channel: 8 }
  enum :status, { pending: 0, ok: 1, failed: 2 }

  has_secure_token :slug, length: 24
  validates :slug, presence: true, uniqueness: true

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [ :user_id, :kind ] }
  # ... rest unchanged
```

- [ ] **Step 2: Verify new sources get a slug automatically**

Run:
```sh
bin/rails runner 's = Source.create!(user: User.first, kind: :rss_feed, url: "https://example.com/tok-test", external_id: "tok-test"); puts s.slug.inspect; s.destroy'
```

Expected: a 24-char string is printed (not `nil`).

- [ ] **Step 3: Verify existing sources still validate**

Run:
```sh
bin/rails runner 'puts Source.first.valid?'
```

Expected: `true` (the backfilled slug is present).

- [ ] **Step 4: Commit**

```sh
git add app/models/source.rb
git commit -m "models: source has secure token slug"
```

---

### Task 4: Extract `ManifestCursor` module

**Files:**
- Create: `app/services/manifest_cursor.rb`
- Create: `test/services/manifest_cursor_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/manifest_cursor_test.rb`:

```ruby
require "test_helper"

class ManifestCursorTest < ActiveSupport::TestCase
  setup do
    @mod = ManifestCursor
  end

  test "decode_offset returns 0 for nil/blank cursor" do
    assert_equal 0, @mod.decode_offset(nil)
    assert_equal 0, @mod.decode_offset("")
  end

  test "decode_offset returns 0 for invalid base64 or json" do
    assert_equal 0, @mod.decode_offset("!!!notbase64!!!")
    assert_equal 0, @mod.decode_offset(Base64.urlsafe_encode64("not json"))
  end

  test "encode_offset then decode_offset round-trips" do
    encoded = @mod.encode_offset(42)
    assert_equal 42, @mod.decode_offset(encoded)
  end

  test "encode_offset emits base64 json with header sc1" do
    decoded = JSON.parse(Base64.urlsafe_decode64(@mod.encode_offset(7)))
    assert_equal "sc1", decoded["h"]
    assert_equal 7, decoded["o"]
  end

  test "next_url builds absolute url with base_url and cursor" do
    url = @mod.next_url(base_url: "https://stray.example.com",
                        path: "/c/slug/manifest.json",
                        cursor: "abc")
    assert_equal "https://stray.example.com/c/slug/manifest.json?cursor=abc", url
  end

  test "next_url builds relative url when base_url is nil" do
    url = @mod.next_url(base_url: nil, path: "/s/slug/manifest.json", cursor: "xyz")
    assert_equal "/s/slug/manifest.json?cursor=xyz", url
  end

  test "next_url returns nil when cursor is nil" do
    assert_nil @mod.next_url(base_url: "https://x", path: "/p", cursor: nil)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
bin/rails test test/services/manifest_cursor_test.rb
```

Expected: FAIL with `NameError: uninitialized constant ManifestCursor` (or similar).

- [ ] **Step 3: Write the module**

Create `app/services/manifest_cursor.rb`:

```ruby
require "json"
require "base64"

module ManifestCursor
  CURSOR_HEADER = "sc1"

  module_function

  def decode_offset(cursor)
    return 0 if cursor.blank?
    decoded = Base64.urlsafe_decode64(cursor.to_s)
    payload = JSON.parse(decoded)
    return 0 unless payload["h"] == CURSOR_HEADER
    payload["o"].to_i
  rescue ArgumentError, JSON::ParserError
    0
  end

  def encode_offset(offset)
    Base64.urlsafe_encode64(JSON.generate({ h: CURSOR_HEADER, o: offset }))
  end

  def next_url(base_url:, path:, cursor:)
    return nil if cursor.nil?
    if base_url
      "#{base_url}#{path}?cursor=#{cursor}"
    else
      "#{path}?cursor=#{cursor}"
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```sh
bin/rails test test/services/manifest_cursor_test.rb
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```sh
git add app/services/manifest_cursor.rb test/services/manifest_cursor_test.rb
git commit -m "services: extract ManifestCursor module"
```

---

### Task 5: Extract `FeedItemPayload` module

**Files:**
- Create: `app/services/feed_item_payload.rb`
- Create: `test/services/feed_item_payload_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/feed_item_payload_test.rb`:

```ruby
require "test_helper"

class FeedItemPayloadTest < ActiveSupport::TestCase
  setup do
    @mod = FeedItemPayload
    @item = items(:video_one)
  end

  test "payload includes required fields" do
    payload = @mod.payload(@item)
    assert_equal @item.external_id, payload[:external_id]
    assert_equal @item.title, payload[:title]
    assert_equal @item.url, payload[:url]
    assert_equal @item.content_text, payload[:content_text]
    assert_equal @item.content_html, payload[:content_html]
    assert_equal @item.thumbnail_url, payload[:thumbnail_url]
    assert_equal @item.published_at&.iso8601, payload[:published_at]
    assert_equal @item.duration, payload[:duration]
    assert_equal [], payload[:tags]
  end

  test "payload excludes summary, embedding, state" do
    @item.update!(summary: "secret")
    payload = @mod.payload(@item)
    assert_not payload.key?(:summary)
    assert_not payload.key?(:embedding)
    assert_not payload.key?(:state)
  end

  test "payload includes tag names from taggings" do
    tag = Tag.create!(user: users(:one), name: "ruby")
    Tagging.create!(item: @item, tag: tag, source: :user)
    payload = @mod.payload(@item)
    assert_equal [ "ruby" ], payload[:tags]
  end

  test "published_at is iso8601 string when present, nil when absent" do
    @item.update!(published_at: nil)
    assert_nil @mod.payload(@item)[:published_at]
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
bin/rails test test/services/feed_item_payload_test.rb
```

Expected: FAIL with `NameError: uninitialized constant FeedItemPayload`.

- [ ] **Step 3: Write the module**

Create `app/services/feed_item_payload.rb`:

```ruby
module FeedItemPayload
  module_function

  def payload(item)
    {
      external_id: item.external_id,
      title: item.title,
      url: item.url,
      content_text: item.content_text,
      content_html: item.content_html,
      thumbnail_url: item.thumbnail_url,
      published_at: item.published_at&.iso8601,
      duration: item.duration,
      tags: item.tags.pluck(:name)
    }
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```sh
bin/rails test test/services/feed_item_payload_test.rb
```

Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```sh
git add app/services/feed_item_payload.rb test/services/feed_item_payload_test.rb
git commit -m "services: extract FeedItemPayload module"
```

---

### Task 6: Refactor `CollectionManifest` to use both modules and drop the hidden filter

**Files:**
- Modify: `app/services/collection_manifest.rb`
- Modify: `test/services/collection_manifest_test.rb`

- [ ] **Step 1: Update the test that asserts hidden items are excluded**

In `test/services/collection_manifest_test.rb`, find the test `"excludes hidden items"` (lines 65–70) and replace it with:

```ruby
  test "includes hidden items" do
    @item2.update!(state: :hidden)
    manifest = CollectionManifest.build(@collection, cursor: nil)
    ids = manifest[:items].map { |i| i[:external_id] }
    assert_includes ids, "manifest-new-2"
  end
```

This flips the assertion: hidden items are now expected to appear.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
bin/rails test test/services/collection_manifest_test.rb
```

Expected: the renamed test `"includes hidden items"` FAILS (current `CollectionManifest` still filters out hidden), while the rest still PASS.

- [ ] **Step 3: Refactor `CollectionManifest` to use the shared modules**

Replace the entire contents of `app/services/collection_manifest.rb` with:

```ruby
require "json"
require "base64"
require "stray"

class CollectionManifest
  DEFAULT_PAGE_SIZE = 100
  NEXT_URL_PATH = "/c/%<slug>s/manifest.json"

  def self.build(collection, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
    new(collection, cursor, page_size, base_url).build
  end

  def initialize(collection, cursor, page_size, base_url)
    @collection = collection
    @page_size = page_size
    @base_url = base_url
    @offset = ManifestCursor.decode_offset(cursor)
  end

  def build
    items_scope = @collection.items.order(published_at: :desc)

    total = items_scope.count
    page_items = items_scope.offset(@offset).limit(@page_size).to_a

    has_more = (@offset + page_items.size) < total
    next_offset = @offset + page_items.size
    next_cursor = has_more ? ManifestCursor.encode_offset(next_offset) : nil
    path = format(NEXT_URL_PATH, slug: @collection.slug)

    {
      format: "stray-collection",
      version: 1,
      collection: {
        name: @collection.name,
        description: @collection.description,
        slug: @collection.slug,
        item_count: total
      },
      producer: {
        instance_name: Setting.get(:instance_name),
        instance_domain: Setting.get(:instance_domain),
        stray_version: Stray::VERSION
      },
      sources: sources_payload,
      items: page_items.map { |item| FeedItemPayload.payload(item) },
      pagination: {
        next_cursor: next_cursor,
        next_url: has_more ? ManifestCursor.next_url(base_url: @base_url, path: path, cursor: next_cursor) : nil,
        has_more: has_more
      }
    }
  end

  private

  def sources_payload
    @collection.sources.map do |source|
      { url: source.url, kind: source.kind, name: source.display_name, icon_url: source.icon_url }
    end
  end
end
```

Key changes:
- Removed `require "json"` and `require "base64"` usages of local methods (kept the requires for safety since `Stray` constant may need them, but the cursor logic now lives in `ManifestCursor`).
- Dropped `.where.not(state: :hidden)` from `items_scope`.
- Replaced `item_payload(item)` and `item_tags(item)` with `FeedItemPayload.payload(item)`.
- Replaced `decode_offset`/`encode_offset`/`next_url` with `ManifestCursor.*` calls.
- `NEXT_URL_PATH` is a format string so the path can be built per-instance.

- [ ] **Step 4: Run the manifest tests to verify they pass**

Run:
```sh
bin/rails test test/services/collection_manifest_test.rb
```

Expected: all tests pass, including `"includes hidden items"`. If `"excludes summary and embedding and state"` fails because of a key ordering issue, confirm the test checks `item.key?(:summary)` (it does — this should still pass since `FeedItemPayload` does not emit those keys).

- [ ] **Step 5: Commit**

```sh
git add app/services/collection_manifest.rb test/services/collection_manifest_test.rb
git commit -m "services: collection manifest uses shared modules, includes hidden items"
```

---

### Task 7: Create `SourceManifest` service

**Files:**
- Create: `app/services/source_manifest.rb`
- Create: `test/services/source_manifest_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/source_manifest_test.rb`:

```ruby
require "test_helper"

class SourceManifestTest < ActiveSupport::TestCase
  def setup
    @source = sources(:youtube)
    @source.items.destroy_all
    @item1 = @source.items.create!(
      user: users(:one), external_id: "sm-1", title: "Older", url: "https://x/1",
      content_text: "old", published_at: 2.days.ago, state: 0
    )
    @item2 = @source.items.create!(
      user: users(:one), external_id: "sm-2", title: "Newer", url: "https://x/2",
      content_text: "new", content_html: "<p>new</p>",
      thumbnail_url: "https://x/2.jpg", published_at: 1.day.ago, state: 0
    )
  end

  test "format is stray-source, not stray-collection" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert_equal "stray-source", manifest[:format]
    assert_equal 1, manifest[:version]
  end

  test "source block has name, url, kind, icon_url, slug, item_count" do
    manifest = SourceManifest.build(@source, cursor: nil)
    src = manifest[:source]
    assert_equal @source.display_name, src[:name]
    assert_equal @source.url, src[:url]
    assert_equal @source.kind, src[:kind]
    assert_equal @source.icon_url, src[:icon_url]
    assert_equal @source.slug, src[:slug]
    assert_equal 2, src[:item_count]
  end

  test "has no sources array (single source)" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert_not manifest.key?(:sources)
  end

  test "producer block is present" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert manifest[:producer][:instance_name].present?
    assert manifest[:producer][:stray_version].present?
  end

  test "items ordered by published_at desc with full payload" do
    manifest = SourceManifest.build(@source, cursor: nil)
    titles = manifest[:items].map { |i| i[:title] }
    assert_equal [ "Newer", "Older" ], titles
    item = manifest[:items].find { |i| i[:external_id] == "sm-2" }
    assert_equal "<p>new</p>", item[:content_html]
    assert_equal "https://x/2.jpg", item[:thumbnail_url]
  end

  test "includes hidden items" do
    @item2.update!(state: :hidden)
    manifest = SourceManifest.build(@source, cursor: nil)
    ids = manifest[:items].map { |i| i[:external_id] }
    assert_includes ids, "sm-2"
  end

  test "pagination next_url uses /s/<slug>/manifest.json path" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1)
    assert first[:pagination][:has_more]
    url = first[:pagination][:next_url]
    assert_includes url, "/s/#{@source.slug}/manifest.json"
    assert_includes url, "cursor="
  end

  test "pagination with base_url is absolute" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1, base_url: "https://stray.example.com")
    assert first[:pagination][:next_url].start_with?("https://stray.example.com/s/")
  end

  test "second page returns remaining items" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1)
    second = SourceManifest.build(@source, cursor: first[:pagination][:next_cursor], page_size: 1)
    assert_not second[:pagination][:has_more]
    assert_equal 1, second[:items].size
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
bin/rails test test/services/source_manifest_test.rb
```

Expected: FAIL with `NameError: uninitialized constant SourceManifest`.

- [ ] **Step 3: Write the service**

Create `app/services/source_manifest.rb`:

```ruby
require "stray"

class SourceManifest
  DEFAULT_PAGE_SIZE = 100
  NEXT_URL_PATH = "/s/%<slug>s/manifest.json"

  def self.build(source, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
    new(source, cursor, page_size, base_url).build
  end

  def initialize(source, cursor, page_size, base_url)
    @source = source
    @page_size = page_size
    @base_url = base_url
    @offset = ManifestCursor.decode_offset(cursor)
  end

  def build
    items_scope = @source.items.order(published_at: :desc)

    total = items_scope.count
    page_items = items_scope.offset(@offset).limit(@page_size).to_a

    has_more = (@offset + page_items.size) < total
    next_offset = @offset + page_items.size
    next_cursor = has_more ? ManifestCursor.encode_offset(next_offset) : nil
    path = format(NEXT_URL_PATH, slug: @source.slug)

    {
      format: "stray-source",
      version: 1,
      source: {
        name: @source.display_name,
        url: @source.url,
        kind: @source.kind,
        icon_url: @source.icon_url,
        slug: @source.slug,
        item_count: total
      },
      producer: {
        instance_name: Setting.get(:instance_name),
        instance_domain: Setting.get(:instance_domain),
        stray_version: Stray::VERSION
      },
      items: page_items.map { |item| FeedItemPayload.payload(item) },
      pagination: {
        next_cursor: next_cursor,
        next_url: has_more ? ManifestCursor.next_url(base_url: @base_url, path: path, cursor: next_cursor) : nil,
        has_more: has_more
      }
    }
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```sh
bin/rails test test/services/source_manifest_test.rb
```

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```sh
git add app/services/source_manifest.rb test/services/source_manifest_test.rb
git commit -m "services: add SourceManifest (stray-source format)"
```

---

### Task 8: Add source feed routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the public source routes and rotate_slug**

In `config/routes.rb`, find the `resources :sources do ... end` block (currently lines 23–29). Replace that block with:

```ruby
  resources :sources do
    member do
      post :pull
      post :mute
      post :unmute
      post :rotate_slug
    end
  end
  get "s/:slug",          to: "sources#public_show", as: :public_source
  get "s/:slug/feed",     to: "sources#feed",        as: :source_feed,     defaults: { format: :xml }
  get "s/:slug/manifest", to: "sources#manifest",    as: :source_manifest, defaults: { format: :json }
```

The `get "s/:slug/..."` routes must live outside the `resources :sources` block because `:slug` is not `:id`.

- [ ] **Step 2: Verify routes**

Run:
```sh
bin/rails routes | grep -E "(source_feed|source_manifest|public_source|rotate_slug)"
```

Expected: four lines showing `source_feed`, `source_manifest`, `public_source`, and `rotate_slug` paths.

- [ ] **Step 3: Commit**

```sh
git add config/routes.rb
git commit -m "routes: add /s/:slug public source feed/manifest + rotate_slug"
```

---

### Task 9: Add source feed, manifest, public_show, and rotate_slug actions

**Files:**
- Modify: `app/controllers/sources_controller.rb`
- Create: `app/views/sources/feed.xml.builder`
- Create: `app/views/sources/public_show.html.erb`

- [ ] **Step 1: Write failing controller tests**

Append to `test/controllers/sources_controller_test.rb` (before the final `end`):

```ruby
  test "feed serves RSS unauthenticated" do
    source = sources(:youtube)
    get source_feed_path(slug: source.slug)
    assert_response :success
    assert_includes response.body, "<rss"
    assert_includes response.body, source.display_name
  end

  test "feed 404 for unknown slug" do
    get source_feed_path(slug: "nonexistentslug00000000")
    assert_response :not_found
  end

  test "feed includes hidden items" do
    source = sources(:bitchute)
    get source_feed_path(slug: source.slug)
    assert_response :success
    assert_includes response.body, "Hidden Video"
  end

  test "manifest serves JSON unauthenticated" do
    source = sources(:youtube)
    get source_manifest_path(slug: source.slug)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "stray-source", json["format"]
    assert_equal source.display_name, json["source"]["name"]
  end

  test "manifest 404 for unknown slug" do
    get source_manifest_path(slug: "nonexistentslug00000000")
    assert_response :not_found
  end

  test "manifest paginates with cursor" do
    source = sources(:youtube)
    first = get source_manifest_path(slug: source.slug, cursor: nil)
    json = JSON.parse(first.body)
    # youtube fixture has 5 items (video_one..video_four + video_three); page_size default 100 so no next page here
    assert_not json["pagination"]["has_more"]
  end

  test "public_show renders unauthenticated" do
    source = sources(:youtube)
    get public_source_path(slug: source.slug)
    assert_response :success
    assert_includes response.body, source.display_name
  end

  test "public_show 404 for unknown slug" do
    get public_source_path(slug: "nonexistentslug00000000")
    assert_response :not_found
  end

  test "rotate_slug requires authentication" do
    source = sources(:youtube)
    post rotate_source_slug_path(source)
    assert_redirected_to new_session_path
  end

  test "rotate_slug regenerates slug and invalidates old URL" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    old_slug = source.slug

    post rotate_source_slug_path(source)

    assert_redirected_to source_path(source)
    source.reload
    assert_not_equal old_slug, source.slug

    # old slug 404s
    get source_feed_path(slug: old_slug)
    assert_response :not_found
    # new slug works
    get source_feed_path(slug: source.slug)
    assert_response :success
  end

  test "rotate_slug 404 for source the user does not follow" do
    sign_in_as(users(:two))
    post rotate_source_slug_path(sources(:bitchute))
    assert_response :not_found
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
bin/rails test test/controllers/sources_controller_test.rb
```

Expected: the new tests FAIL (actions + views don't exist yet). Existing tests should still pass.

- [ ] **Step 3: Add `allow_unauthenticated_access` and the four actions**

At the top of `app/controllers/sources_controller.rb`, immediately after the `include Pagy::Method` line (line 2), add:

```ruby
  allow_unauthenticated_access only: %i[public_show feed manifest]
```

Add the four new actions. Place them after the `unmute` action (before `edit`), grouped together:

```ruby
  def public_show
    @source = Source.find_by!(slug: params[:slug])
  end

  def feed
    @source = Source.find_by!(slug: params[:slug])
    @items = @source.items.order(published_at: :desc).limit(50)
    render formats: :xml
  end

  def manifest
    source = Source.find_by!(slug: params[:slug])
    render json: SourceManifest.build(source, cursor: params[:cursor], base_url: request.base_url)
  end

  def rotate_slug
    source = scoped_source
    source.regenerate_token(:slug)
    redirect_to source_path(source), notice: "Feed link rotated."
  end
```

`regenerate_token(:slug)` is the `has_secure_token` method for a named token; it sets and saves the new value.

- [ ] **Step 4: Create the RSS builder view**

Create `app/views/sources/feed.xml.builder`:

```ruby
xml.instruct!
xml.rss(version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom") do
  xml.channel do
    xml.title @source.display_name
    xml.link @source.url
    xml.description @source.display_name
    xml.atom(:link, href: request.url, rel: "self", type: "application/rss+xml")

    @items.each do |item|
      xml.item do
        xml.title item.title
        xml.link item.url
        xml.guid item.url
        xml.pubDate item.published_at&.rfc2822
        xml.description item.content_text || item.title
        xml.enclosure(url: item.thumbnail_url, type: "image/jpeg") if item.thumbnail_url
      end
    end
  end
end
```

- [ ] **Step 5: Create the public_show view**

Create `app/views/sources/public_show.html.erb`:

```erb
<div class="mx-auto max-w-2xl px-4 py-8">
  <h1 class="text-2xl font-bold"><%= @source.display_name %></h1>

  <p class="mt-2 text-sm text-stone-600">
    A source on <%= Setting.get(:instance_name) || "this Stray instance" %>.
  </p>

  <ul class="mt-6 space-y-2 text-sm">
    <li>
      <%= phosphor_icon "rss", class: "inline h-4 w-4 align-text-bottom" %>
      <%= link_to "RSS feed", source_feed_path(slug: @source.slug, format: :xml), class: "ml-1 text-blue-600 hover:underline" %>
    </li>
    <li>
      <%= phosphor_icon "code", class: "inline h-4 w-4 align-text-bottom" %>
      <%= link_to "Stray manifest (JSON)", source_manifest_path(slug: @source.slug, format: :json), class: "ml-1 text-blue-600 hover:underline" %>
    </li>
  </ul>
</div>
```

- [ ] **Step 6: Run the controller tests to verify they pass**

Run:
```sh
bin/rails test test/controllers/sources_controller_test.rb
```

Expected: all tests pass, including the 11 new ones. If `feed includes hidden items` fails, double-check the bitchute fixture's items include `video_hidden` (it does — see `test/fixtures/items.yml` lines 35–43, source: bitchute).

- [ ] **Step 7: Commit**

```sh
git add app/controllers/sources_controller.rb app/views/sources/feed.xml.builder app/views/sources/public_show.html.erb test/controllers/sources_controller_test.rb
git commit -m "sources: add public feed, manifest, public_show, rotate_slug"
```

---

### Task 10: Drop the hidden filter from the collection `feed` action

**Files:**
- Modify: `app/controllers/collections_controller.rb:59-65`
- Modify: `test/controllers/collections_controller_test.rb`

- [ ] **Step 1: Add a failing test asserting hidden items appear in the collection RSS feed**

In `test/controllers/collections_controller_test.rb`, after the existing `"feed serves RSS unauthenticated"` test (lines 115–119), add:

```ruby
  test "feed includes hidden items" do
    # econ collection includes the bitchute source, which has video_hidden (state: 3)
    get collection_feed_path(slug: collections(:econ).slug)
    assert_response :success
    assert_includes response.body, "Hidden Video"
  end

  test "manifest includes hidden items" do
    get collection_manifest_path(slug: collections(:econ).slug)
    assert_response :success
    json = JSON.parse(response.body)
    titles = json["items"].map { |i| i["title"] }
    assert_includes titles, "Hidden Video"
  end
```

Confirm the `econ` collection includes the `bitchute` source. If it does not, add the membership in `test/fixtures/collection_memberships.yml`. First check:

```sh
grep -A3 "econ:" test/fixtures/collections.yml test/fixtures/collection_memberships.yml
```

If the `bitchute` source is not a member of `econ`, add a membership row. (The existing collection manifest test setup in `test/services/collection_manifest_test.rb` uses `@collection = collections(:econ)` and `@source = sources(:youtube)`, then creates items on `youtube` — so `econ` already includes `youtube`. To make the hidden-item test meaningful, `econ` must also include `bitchute`. Add to `test/fixtures/collection_memberships.yml` if missing:

```yaml
econ_bitchute:
  collection: econ
  source: bitchute
```

)

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```sh
bin/rails test test/controllers/collections_controller_test.rb
```

Expected: the two new tests FAIL (controller still filters hidden). Other tests pass.

- [ ] **Step 3: Drop the hidden filter in the collection feed action**

In `app/controllers/collections_controller.rb`, change the `feed` action (line 63) from:

```ruby
    @items = @collection.items.where.not(state: :hidden).order(published_at: :desc).limit(50)
```

to:

```ruby
    @items = @collection.items.order(published_at: :desc).limit(50)
```

The manifest action delegates to `CollectionManifest`, which we already updated in Task 6.

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```sh
bin/rails test test/controllers/collections_controller_test.rb
```

Expected: all tests pass, including the two new ones.

- [ ] **Step 5: Commit**

```sh
git add app/controllers/collections_controller.rb test/controllers/collections_controller_test.rb test/fixtures/collection_memberships.yml
git commit -m "collections: feed and manifest include hidden items"
```

(Only stage `collection_memberships.yml` if you modified it.)

---

### Task 11: Update source fixtures with explicit slugs

Fixtures don't trigger `has_secure_token` callbacks, so without explicit `slug` values the test DB would have NULL slugs and break every source test. We add stable, explicit 24-char slugs.

**Files:**
- Modify: `test/fixtures/sources.yml`

- [ ] **Step 1: Add slugs to each fixture**

In `test/fixtures/sources.yml`, add a `slug:` line to each fixture. Use 24-char alphanumeric strings. Final file:

```yaml
youtube:
  user: one
  kind: 0
  url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfeed"
  name: "Test Channel"
  external_id: "UCfeed"
  icon_url: "https://example.com/youtube-avatar.png"
  active: true
  status: 1
  next_crawl_at: <%= 1.hour.from_now %>
  slug: "youtubeslug00000000000000"

bitchute:
  user: one
  kind: 1
  url: "https://bitchute.com/channel/feedbc"
  name: "BC Channel"
  external_id: "feedbc"
  icon_url: "https://example.com/bitchute-avatar.png"
  active: true
  status: 1
  next_crawl_at: <%= 1.hour.from_now %>
  slug: "bitchuteslug0000000000000"

inactive:
  user: one
  kind: 0
  url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCold"
  name: "Dead Channel"
  external_id: "UCold"
  active: false
  status: 1
  slug: "inactiveslug0000000000000"

remote:
  user: one
  kind: 4
  url: "https://stray.example.com/c/econblogssecrettoken1234/manifest.json"
  name: "Economics Blogs (remote)"
  external_id: "econblogssecrettoken1234"
  active: true
  status: 1
  next_crawl_at: <%= 1.hour.from_now %>
  slug: "remotecollectionslug000000"
```

Each `slug` value is exactly 24 chars (`[A-Za-z0-9]`). Count carefully — e.g. `"youtubeslug00000000000000"` is `youtube` (7) + `slug` (4) + 13 zeros = 24. Adjust padding if needed.

- [ ] **Step 2: Verify slug lengths**

Run:
```sh
bin/rails runner 'Source.all.each { |s| raise "#{s.name}: #{s.slug&.length}" unless s.slug&.length == 24 }'
```

In test env this requires `RAILS_ENV=test`. Instead, run the test suite (next step) which will surface any length issue.

- [ ] **Step 3: Run the full test suite to catch regressions**

Run:
```sh
bin/rails test
```

Expected: all tests pass. If any test references `sources(:youtube).slug` and the slug is nil/wrong length, it will fail here — fix the fixture.

- [ ] **Step 4: Commit**

```sh
git add test/fixtures/sources.yml
git commit -m "test: add explicit 24-char slugs to source fixtures"
```

---

### Task 12: Full suite + lint

**Files:** none

- [ ] **Step 1: Run the full test suite**

Run:
```sh
bin/rails test
```

Expected: all tests pass. Pay attention to:
- `test/services/collection_manifest_test.rb` — `"includes hidden items"` passes.
- `test/services/source_manifest_test.rb` — all 9 pass.
- `test/controllers/sources_controller_test.rb` — all pass, including feed/manifest/rotate.
- `test/controllers/collections_controller_test.rb` — all pass, including hidden-included.

- [ ] **Step 2: Run RuboCop**

Run:
```sh
bin/rubocop
```

Expected: no new offenses in the files touched:
- `app/models/source.rb`
- `app/services/feed_item_payload.rb`
- `app/services/manifest_cursor.rb`
- `app/services/collection_manifest.rb`
- `app/services/source_manifest.rb`
- `app/controllers/sources_controller.rb`
- `app/controllers/collections_controller.rb`
- `app/views/sources/feed.xml.builder`
- `app/views/sources/public_show.html.erb`
- `config/routes.rb`
- `db/migrate/<ts>_add_slug_to_sources.rb`
- `db/data/<ts>_backfill_source_slugs.rb`
- the two test files

Fix any offenses (autocorrect with `bin/rubocop -A` where safe).

- [ ] **Step 3: Commit any lint fixes**

```sh
git add -A
git commit -m "style: rubocop fixes for source feeds"
```

(Skip this step if there were no fixes.)

---

### Task 13: Manual smoke test (dev server)

- [ ] **Step 1: Start the dev server**

Run:
```sh
bin/dev
```

- [ ] **Step 2: Hit the source RSS feed**

In another terminal:
```sh
curl -s "http://localhost:3000/s/youtubeslug00000000000000/feed.xml" | head -20
```

Expected: an RSS 2.0 document with `<title>Test Channel</title>` and item entries.

- [ ] **Step 3: Hit the source manifest**

```sh
curl -s "http://localhost:3000/s/youtubeslug00000000000000/manifest.json" | python3 -m json.tool | head -30
```

Expected: JSON with `"format": "stray-source"`, a `source` block, an `items` array, and `pagination`.

- [ ] **Step 4: Hit the collection feed (regression)**

```sh
curl -s "http://localhost:3000/c/econblogssecrettoken1234/feed.xml" | head -20
```

Expected: still works, now includes `Hidden Video` if the bitchute source is an econ member.

- [ ] **Step 5: Stop the dev server**

`Ctrl-C` the `bin/dev` process.

---

## Self-Review

**1. Spec coverage** — cross-checking against `docs/superpowers/specs/2026-08-20-source-collection-feeds-design.md`:

| Spec section | Covered by |
|---|---|
| Routes `/s/:slug`, `/s/:slug/feed.xml`, `/s/:slug/manifest.json` | Task 8 |
| `has_secure_token :slug` on Source | Task 3 |
| Schema migration (add column + unique index) | Task 1 |
| Data migration (backfill) | Task 2 |
| `rotate_slug` authenticated member route + action | Tasks 8, 9 |
| `Source#feed` action, no state filter, 50 items, XML | Task 9 |
| `Source#manifest` action, delegates to `SourceManifest` | Task 9 |
| `sources/feed.xml.builder` mirroring collections builder | Task 9 |
| `public_show` view | Task 9 |
| `SourceManifest` service, format `stray-source`, no `sources:` array | Task 7 |
| Shared `FeedItemPayload` module | Task 5 |
| Shared `ManifestCursor` module | Task 4 |
| `CollectionManifest` uses both modules | Task 6 |
| Drop `where.not(state: :hidden)` from collection feed | Task 10 |
| Drop hidden filter from `CollectionManifest` | Task 6 |
| Tests: source feed/manifest/rotate, 404 for unknown slug | Task 9 |
| Tests: hidden items now included in collection feed + manifest | Task 10 |
| Tests: `SourceManifest` shape + pagination | Task 7 |
| Tests: shared modules | Tasks 4, 5 |
| Fixtures get explicit slugs (because `has_secure_token` doesn't fire on fixtures) | Task 11 |

No spec gaps found. All sections map to a task.

**2. Placeholder scan** — scanned the plan for "TBD", "TODO", "implement later", "add appropriate error handling", "similar to Task N", "write tests for the above" without code, etc. None found. Every code step contains the actual code; every test step contains the actual test code.

**3. Type consistency** — checked method/property names across tasks:
- `ManifestCursor.decode_offset`, `.encode_offset`, `.next_url(base_url:, path:, cursor:)` — used consistently in Tasks 4, 6, 7.
- `FeedItemPayload.payload(item)` — used consistently in Tasks 5, 6, 7.
- `SourceManifest.build(source, cursor:, page_size:, base_url:)` — signature matches between Task 7 (service) and Task 9 (controller).
- `CollectionManifest.build(collection, cursor:, page_size:, base_url:)` — unchanged signature from existing code (Task 6 only refactors internals).
- `source.regenerate_token(:slug)` — used in Task 9 (`rotate_slug` action) and mentioned in Task 2's notes. `has_secure_token` provides this method when declared with `has_secure_token :slug` (Task 3).
- `source.display_name` — exists on Source (confirmed in exploration: `app/models/source.rb:31-38`). Used in Tasks 7 and 9.
- `Setting.get(:instance_name)` / `Setting.get(:instance_domain)` — used in existing `CollectionManifest` (line 42-43) and reused in Task 7's `SourceManifest`.
- `Stray::VERSION` — required via `require "stray"` in both manifest services (Tasks 6, 7).
- Route helpers `source_feed_path(slug:, format:)`, `source_manifest_path(slug:, format:)`, `public_source_path(slug:)`, `rotate_source_slug_path(source)` — defined in Task 8, used in Task 9 tests.
- Fixture slugs are exactly 24 chars of `[A-Za-z0-9]` — Task 11. Verified by the `bin/rails test` run in Task 11 step 3.

No inconsistencies found.
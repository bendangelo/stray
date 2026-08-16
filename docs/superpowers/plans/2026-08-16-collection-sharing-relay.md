# Collection Sharing + Remote Relay Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Stray user group sources into a Collection, share a URL, and let another Stray instance subscribe and import items via a paginated JSON manifest — without polling the original sources.

**Architecture:** Producer builds a paginated JSON manifest + RSS/Atom feed at `/c/:slug/*`. Consumer subscribes, creating a `Source` (kind `:stray_collection`) + `RemoteCollection` (sync state). A new `Stray::Extractors::RemoteCollection` returns `Stray::Extractor::FeedResult` (items + cursor + has_more), plugged into the existing `SourcePollJob` upsert/embedding/tagging pipeline. Relay is just another extractor.

**Tech Stack:** Rails 8, SQLite, Solid Queue, Hotwire, Faraday (HTTP), Minitest + VCR, Pagy. No new gems.

**Spec:** `docs/superpowers/specs/2026-08-16-collection-sharing-relay-design.md`

---

## File Structure

**New files:**
- `db/migrate/YYYYMMDDhhmmss_create_collections.rb`
- `db/migrate/YYYYMMDDhhmmss_create_collection_memberships.rb`
- `db/migrate/YYYYMMDDhhmmss_add_stray_collection_to_source_kind.rb`
- `db/migrate/YYYYMMDDhhmmss_create_remote_collections.rb`
- `app/models/collection.rb`
- `app/models/collection_membership.rb`
- `app/models/remote_collection.rb`
- `app/controllers/collections_controller.rb`
- `app/controllers/remote_collections_controller.rb`
- `app/views/collections/{index,new,edit,show,_form,_collection,_member}.erb`
- `app/views/collections/{public_show,manifest}.json.jbuilder`
- `app/views/collections/feed.xml.builder`
- `app/views/remote_collections/{new,preview}.erb`
- `lib/stray/extractor/feed_result.rb`
- `lib/stray/extractors/remote_collection.rb`
- `lib/stray/url_guard.rb`
- `lib/stray/collection_manifest.rb` (manifest builder)
- `test/fixtures/collections.yml`, `test/fixtures/collection_memberships.yml`, `test/fixtures/remote_collections.yml`
- `test/models/collection_test.rb`, `test/models/collection_membership_test.rb`, `test/models/remote_collection_test.rb`
- `test/lib/stray/url_guard_test.rb`
- `test/lib/stray/collection_manifest_test.rb`
- `test/lib/stray/extractors/remote_collection_test.rb`
- `test/controllers/collections_controller_test.rb`
- `test/controllers/remote_collections_controller_test.rb`
- `test/integration/collection_sync_flow_test.rb`
- `test/vcr_cassettes/remote_collection/manifest_first_page.yml`, `manifest_second_page.yml`, `manifest_empty.yml`

**Modified files:**
- `AGENTS.md` (lines 16, 104, 131, 132 — roadmap update)
- `README.md` (lines 61, 76-77 — roadmap update)
- `app/models/source.rb` (enum value, `has_one :remote_collection`)
- `app/models/user.rb` (`has_many :collections, :remote_collections`)
- `app/jobs/source_poll_job.rb` (cursor arg, FeedResult handling, RemoteCollection update)
- `config/initializers/extractors.rb` (register RemoteCollection)
- `config/routes.rb` (collection routes, remote_collection resource, public collection routes)
- `app/views/sources/index.html.erb` (entry point to subscribe to remote collection)
- `app/views/sources/_sidebar.html.erb` (Collections link)
- `test/fixtures/sources.yml` (add a `stray_collection` fixture)
- `test/models/source_test.rb` (enum value test)
- `test/jobs/source_poll_job_test.rb` (pagination tests)

---

## Task 1: Update outdated roadmap docs

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`

- [ ] **Step 1: Update AGENTS.md Principle 6 (line 16)**

Change:
```
6. **Ship interoperability before inventing a protocol.** Shared feeds output plain RSS/Atom in v1. A Stray-specific cross-instance protocol is v4+, only after v3.5 proves the pull/export model.
```
to:
```
6. **Ship interoperability before inventing a protocol.** Collections output plain RSS/Atom (for any reader) AND a Stray-specific paginated JSON manifest (for Stray-to-Stray relay). Real-time federation (ActivityPub or bespoke) is still deferred.
```

- [ ] **Step 2: Update AGENTS.md Collection model (line 104)**

Change:
```
- **Collection** — v3 (sharing): `name`, `visibility` (`private`/`unlisted`/`public`), `tag_filter`.
```
to:
```
- **Collection** — `name`, `description`, `visibility` (`private`/`unlisted`; `public` reserved), long-random `slug`. Membership is an explicit source list via `CollectionMembership` (no `tag_filter` in v1).
```

- [ ] **Step 3: Update AGENTS.md "Out of scope" (lines 131-132)**

Change:
```
- `Collection`s, sharing, RSS/Atom export → v3 / v3.5.
- Cross-instance pull → v4. Real-time federation protocol (ActivityPub or bespoke) → v5, only after v4 validates the model. Do not build federation early.
```
to:
```
- `public` Collection visibility, per-recipient share tokens, item-deletion propagation across instances → later.
- Real-time federation protocol (ActivityPub or bespoke) → later. The v1 relay model (poll a JSON manifest) must validate first.
```

- [ ] **Step 4: Update README.md (lines 61, 76-77)**

Change line 61:
```
- **Share as plain RSS/Atom** — public collections export to standard feeds any reader can pull (v3.5).
```
to:
```
- **Share as plain RSS/Atom or Stray manifest** — collections export to standard feeds any reader can pull, plus a paginated JSON manifest for Stray-to-Stray relay.
```

Change lines 76-77:
```
- **v3 / v3.5** — multi-user, `Collection`s with visibility, public collection RSS/Atom export.
- **v4+** — cross-instance pull; real-time federation only after v4 validates the model.
```
to:
```
- **v3** — multi-user.
- **Built** — `Collection`s with visibility, RSS/Atom export, and cross-instance pull via JSON manifest relay.
- **Later** — `public` visibility, real-time federation (ActivityPub or bespoke).
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md README.md
git commit -m "docs: update roadmap for collections + relay now in scope

Collections (was v3) and cross-instance pull (was v4) are being built
now. v1 Collection uses explicit source list, no tag_filter. Real-time
federation still deferred."
```

---

## Task 2: Collection model

**Files:**
- Create: `db/migrate/YYYYMMDDhhmmss_create_collections.rb`
- Create: `app/models/collection.rb`
- Create: `test/models/collection_test.rb`
- Create: `test/fixtures/collections.yml`

- [ ] **Step 1: Generate migration**

Run:
```bash
bin/rails g migration CreateCollections
```

- [ ] **Step 2: Edit the migration**

Replace the generated file (timestamp will vary) with:

```ruby
# frozen_string_literal: true
class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :visibility, default: 0, null: false
      t.string :slug, null: false

      t.timestamps
    end
    add_index :collections, [ :user_id, :slug ], unique: true
  end
end
```

- [ ] **Step 3: Write the failing model test**

`test/models/collection_test.rb`:

```ruby
require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  test "valid with name and user" do
    collection = Collection.new(user: users(:one), name: "My Blogs")
    assert collection.valid?
  end

  test "invalid without name" do
    collection = Collection.new(user: users(:one))
    assert collection.invalid?
    assert_includes collection.errors[:name], "can't be blank"
  end

  test "invalid without user" do
    collection = Collection.new(name: "No user")
    assert collection.invalid?
    assert_includes collection.errors[:user], "must exist"
  end

  test "generates slug on create" do
    collection = Collection.create!(user: users(:one), name: "My Blogs")
    assert collection.slug.present?
    assert collection.slug.length >= 24
  end

  test "slug is unique per user" do
    first = Collection.create!(user: users(:one), name: "First")
    second = Collection.new(user: users(:one), slug: first.slug, name: "Second")
    assert second.invalid?
    assert_includes second.errors[:slug], "has already been taken"
  end

  test "default visibility is unlisted" do
    collection = Collection.new(user: users(:one), name: "X")
    assert collection.unlisted?
    assert_not collection.private?
  end

  test "can set visibility to private" do
    collection = Collection.new(user: users(:one), name: "X", visibility: :private)
    assert collection.private?
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/collection_test.rb`
Expected: FAIL — `uninitialized constant Collection` / table missing.

- [ ] **Step 5: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 6: Write the model**

`app/models/collection.rb`:

```ruby
class Collection < ApplicationRecord
  enum :visibility, { unlisted: 0, private: 1, public: 2 }

  belongs_to :user
  has_many :collection_memberships, dependent: :destroy
  has_many :sources, through: :collection_memberships

  has_secure_token :slug, length: 24

  validates :name, presence: true
  validates :slug, uniqueness: { scope: :user_id }
end
```

- [ ] **Step 7: Add fixtures**

`test/fixtures/collections.yml`:

```yaml
econ:
  user: one
  name: "Economics Blogs"
  description: "Curated econ feeds"
  visibility: 0
  slug: "econblogssecrettoken1234"

private_one:
  user: one
  name: "Private Notes"
  visibility: 1
  slug: "privatenotesecrettoken12345"
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bin/rails test test/models/collection_test.rb`
Expected: PASS (all 7 tests).

- [ ] **Step 9: Commit**

```bash
git add db/migrate/*_create_collections.rb app/models/collection.rb \
  test/models/collection_test.rb test/fixtures/collections.yml db/schema.rb
git commit -m "feat: add Collection model with unlisted/private visibility

Long-random slug is the secret gating unlisted access. No tag_filter
in v1 — explicit source list via CollectionMembership (next task)."
```

---

## Task 3: CollectionMembership model

**Files:**
- Create: `db/migrate/YYYYMMDDhhmmss_create_collection_memberships.rb`
- Create: `app/models/collection_membership.rb`
- Create: `test/models/collection_membership_test.rb`
- Create: `test/fixtures/collection_memberships.yml`

- [ ] **Step 1: Generate migration**

Run:
```bash
bin/rails g migration CreateCollectionMemberships
```

- [ ] **Step 2: Edit the migration**

```ruby
# frozen_string_literal: true
class CreateCollectionMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_memberships do |t|
      t.references :collection, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true

      t.timestamps
    end
    add_index :collection_memberships, [ :collection_id, :source_id ], unique: true
  end
end
```

- [ ] **Step 3: Write the failing model test**

`test/models/collection_membership_test.rb`:

```ruby
require "test_helper"

class CollectionMembershipTest < ActiveSupport::TestCase
  test "valid with collection and source" do
    membership = CollectionMembership.new(collection: collections(:econ), source: sources(:youtube))
    assert membership.valid?
  end

  test "unique per collection and source" do
    CollectionMembership.create!(collection: collections(:econ), source: sources(:youtube))
    dup = CollectionMembership.new(collection: collections(:econ), source: sources(:youtube))
    assert dup.invalid?
    assert_includes dup.errors[:source_id], "has already been taken"
  end

  test "destroyed when collection destroyed" do
    membership = CollectionMembership.create!(collection: collections(:econ), source: sources(:youtube))
    collections(:econ).destroy
    assert_not CollectionMembership.exists?(membership.id)
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/collection_membership_test.rb`
Expected: FAIL — table missing.

- [ ] **Step 5: Run migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 6: Write the model**

`app/models/collection_membership.rb`:

```ruby
class CollectionMembership < ApplicationRecord
  belongs_to :collection
  belongs_to :source

  validates :source_id, uniqueness: { scope: :collection_id }
end
```

- [ ] **Step 7: Add has_many to Collection**

Edit `app/models/collection.rb` — the associations are already there from Task 2 Step 6 (the `has_many :collection_memberships` and `has_many :sources, through: :collection_memberships`). Verify they are present.

- [ ] **Step 8: Add fixtures**

`test/fixtures/collection_memberships.yml`:

```yaml
econ_youtube:
  collection: econ
  source: youtube
```

- [ ] **Step 9: Run test to verify it passes**

Run: `bin/rails test test/models/collection_membership_test.rb`
Expected: PASS (3 tests).

- [ ] **Step 10: Commit**

```bash
git add db/migrate/*_create_collection_memberships.rb app/models/collection_membership.rb \
  test/models/collection_membership_test.rb test/fixtures/collection_memberships.yml db/schema.rb
git commit -m "feat: add CollectionMembership join (explicit source list)"
```

---

## Task 4: Add :stray_collection to Source kind enum + RemoteCollection model

**Files:**
- Modify: `db/migrate/YYYYMMDDhhmmss_add_stray_collection_to_source_kind.rb` (create)
- Create: `db/migrate/YYYYMMDDhhmmss_create_remote_collections.rb`
- Modify: `app/models/source.rb`
- Modify: `app/models/user.rb`
- Create: `app/models/remote_collection.rb`
- Create: `test/models/remote_collection_test.rb`
- Modify: `test/models/source_test.rb`
- Create: `test/fixtures/remote_collections.yml`
- Modify: `test/fixtures/sources.yml`

- [ ] **Step 1: Generate the kind migration**

Run:
```bash
bin/rails g migration AddStrayCollectionToSourceKind
```

- [ ] **Step 2: Edit the kind migration**

The `sources.kind` column is `integer, null: false`. The existing enum values are 0-3. We add value 4. No column change is strictly needed (integer column accepts any value), but we add a no-op migration for clarity in the schema dump:

```ruby
# frozen_string_literal: true
class AddStrayCollectionToSourceKind < ActiveRecord::Migration[8.1]
  # No schema change needed: sources.kind is a plain integer column.
  # This migration exists to document the new enum value 4 (:stray_collection).
  def up
    # no-op
  end

  def down
    # no-op
  end
end
```

- [ ] **Step 3: Generate the remote_collections migration**

Run:
```bash
bin/rails g migration CreateRemoteCollections
```

- [ ] **Step 4: Edit the remote_collections migration**

```ruby
# frozen_string_literal: true
class CreateRemoteCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_collections do |t|
      t.references :source, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :manifest_url, null: false
      t.string :producer_instance_name
      t.string :collection_name
      t.string :last_cursor
      t.datetime :last_synced_at
      t.string :last_error
      t.datetime :last_error_at
      t.integer :item_count, default: 0

      t.timestamps
    end
    add_index :remote_collections, :source_id, unique: true
    add_index :remote_collections, [ :user_id, :manifest_url ], unique: true
  end
end
```

- [ ] **Step 5: Write the failing model test**

`test/models/remote_collection_test.rb`:

```ruby
require "test_helper"

class RemoteCollectionTest < ActiveSupport::TestCase
  def setup
    @source = Source.create!(user: users(:one), kind: :stray_collection,
      url: "https://stray.example.com/c/abc/manifest.json", external_id: "abc")
  end

  test "valid with source, user, and manifest_url" do
    rc = RemoteCollection.new(source: @source, user: users(:one),
      manifest_url: "https://stray.example.com/c/abc/manifest.json")
    assert rc.valid?
  end

  test "unique source (1:1)" do
    RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    dup = RemoteCollection.new(source: @source, user: users(:one), manifest_url: @source.url)
    assert dup.invalid?
    assert_includes dup.errors[:source_id], "has already been taken"
  end

  test "unique user + manifest_url" do
    RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    other_source = Source.create!(user: users(:one), kind: :stray_collection,
      url: "https://stray.example.com/c/abc/manifest.json?x", external_id: "abc2")
    dup = RemoteCollection.new(source: other_source, user: users(:one), manifest_url: @source.url)
    assert dup.invalid?
    assert_includes dup.errors[:manifest_url], "has already been taken"
  end

  test "destroyed when source destroyed" do
    rc = RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    @source.destroy
    assert_not RemoteCollection.exists?(rc.id)
  end
end
```

- [ ] **Step 6: Extend source_test.rb**

Add to `test/models/source_test.rb` (inside the existing class):

```ruby
  test "stray_collection kind is a valid enum value" do
    source = Source.new(user: users(:one), kind: :stray_collection, url: "https://x/c/y/manifest.json")
    assert source.valid?
    assert_equal "stray_collection", source.kind
  end

  test "has_one remote_collection" do
    source = Source.create!(user: users(:one), kind: :stray_collection,
      url: "https://x/c/y/manifest.json", external_id: "y")
    rc = RemoteCollection.create!(source: source, user: users(:one), manifest_url: source.url)
    assert_equal rc, source.remote_collection
  end
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `bin/rails test test/models/remote_collection_test.rb test/models/source_test.rb`
Expected: FAIL — table missing / enum value missing.

- [ ] **Step 8: Run migrations**

```bash
bin/rails db:migrate
```

- [ ] **Step 9: Update Source model**

Edit `app/models/source.rb` — change the enum line and add association:

```ruby
class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_one :remote_collection, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4 }
```

The rest of the file (validations, scopes, `display_name`, `recalculate_next_crawl!`) stays the same.

- [ ] **Step 10: Update User model**

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :remote_collections, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :username, presence: true
  validates :password, length: { minimum: 6 }
end
```

- [ ] **Step 11: Write RemoteCollection model**

`app/models/remote_collection.rb`:

```ruby
class RemoteCollection < ApplicationRecord
  belongs_to :source
  belongs_to :user

  validates :manifest_url, presence: true, uniqueness: { scope: :user_id }
  validates :source_id, uniqueness: true
end
```

- [ ] **Step 12: Add fixtures**

`test/fixtures/remote_collections.yml`:

```yaml
one:
  source: remote
  user: one
  manifest_url: "https://stray.example.com/c/econblogssecrettoken1234/manifest.json"
  collection_name: "Economics Blogs"
  producer_instance_name: "Alice's Stray"
```

Add to `test/fixtures/sources.yml`:

```yaml
remote:
  user: one
  kind: 4
  url: "https://stray.example.com/c/econblogssecrettoken1234/manifest.json"
  name: "Economics Blogs (remote)"
  external_id: "econblogssecrettoken1234"
  active: true
  next_crawl_at: <%= 1.hour.from_now %>
```

- [ ] **Step 13: Run tests to verify they pass**

Run: `bin/rails test test/models/remote_collection_test.rb test/models/source_test.rb`
Expected: PASS.

- [ ] **Step 14: Commit**

```bash
git add db/migrate/*_add_stray_collection* db/migrate/*_create_remote_collections* \
  app/models/source.rb app/models/user.rb app/models/remote_collection.rb \
  test/models/remote_collection_test.rb test/models/source_test.rb \
  test/fixtures/remote_collections.yml test/fixtures/sources.yml db/schema.rb
git commit -m "feat: add stray_collection source kind + RemoteCollection sync state

RemoteCollection tracks consumer-side relay sync state (cursor,
last_synced_at, error). 1:1 with a Source of kind :stray_collection."
```

---

## Task 5: Stray::Extractor::FeedResult struct

**Files:**
- Create: `lib/stray/extractor/feed_result.rb`
- Modify: `lib/stray/extractor.rb`
- Create: `test/lib/stray/extractor/feed_result_test.rb`

- [ ] **Step 1: Write the failing test**

`test/lib/stray/extractor/feed_result_test.rb`:

```ruby
require "test_helper"

class Stray::Extractor::FeedResultTest < ActiveSupport::TestCase
  test "has items, next_cursor, has_more" do
    item = Stray::ExtractedContent.new(url: "https://x", title: "T", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "x",
      duration: nil, creator_identity: nil, tags: [])
    result = Stray::Extractor::FeedResult.new(items: [ item ], next_cursor: "cur", has_more: true)
    assert_equal [ item ], result.items
    assert_equal "cur", result.next_cursor
    assert result.has_more
  end

  test "has_more defaults to false" do
    result = Stray::Extractor::FeedResult.new(items: [], next_cursor: nil)
    assert_not result.has_more
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/extractor/feed_result_test.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Write the struct**

`lib/stray/extractor/feed_result.rb`:

```ruby
module Stray
  class Extractor
    FeedResult = Data.define(:items, :next_cursor, :has_more) do
      def has_more = @has_more || false
    end
  end
end
```

- [ ] **Step 4: Require it from extractor.rb**

Edit `lib/stray/extractor.rb` — add at the bottom of the file (after the class definition):

```ruby
require "stray/extractor/feed_result"
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/extractor/feed_result_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/stray/extractor/feed_result.rb lib/stray/extractor.rb \
  test/lib/stray/extractor/feed_result_test.rb
git commit -m "feat: add Stray::Extractor::FeedResult for paginated extractors

Backwards-compatible: existing extractors returning arrays still work;
SourcePollJob treats non-FeedResult returns as has_more: false."
```

---

## Task 6: Stray::UrlGuard (SSRF protection)

**Files:**
- Create: `lib/stray/url_guard.rb`
- Create: `test/lib/stray/url_guard_test.rb`

- [ ] **Step 1: Write the failing test**

`test/lib/stray/url_guard_test.rb`:

```ruby
require "test_helper"

class Stray::UrlGuardTest < ActiveSupport::TestCase
  test "allows public https URLs" do
    assert Stray::UrlGuard.allowed?("https://stray.example.com/c/abc/manifest.json")
  end

  test "allows public http URLs" do
    assert Stray::UrlGuard.allowed?("http://stray.example.com/c/abc/manifest.json")
  end

  test "rejects localhost" do
    assert_not Stray::UrlGuard.allowed?("http://localhost:3000/c/abc/manifest.json")
    assert_not Stray::UrlGuard.allowed?("http://127.0.0.1:3000/c/abc/manifest.json")
  end

  test "rejects IPv6 loopback" do
    assert_not Stray::UrlGuard.allowed?("http://[::1]/c/abc/manifest.json")
  end

  test "rejects private 10.x" do
    assert_not Stray::UrlGuard.allowed?("http://10.0.0.1/c/abc/manifest.json")
  end

  test "rejects private 172.16-31.x" do
    assert_not Stray::UrlGuard.allowed?("http://172.16.0.1/c/abc/manifest.json")
    assert_not Stray::UrlGuard.allowed?("http://172.31.255.254/c/abc/manifest.json")
  end

  test "rejects private 192.168.x" do
    assert_not Stray::UrlGuard.allowed?("http://192.168.1.1/c/abc/manifest.json")
  end

  test "rejects link-local 169.254.x (AWS metadata)" do
    assert_not Stray::UrlGuard.allowed?("http://169.254.169.254/latest/meta-data/")
  end

  test "rejects non-http schemes" do
    assert_not Stray::UrlGuard.allowed?("file:///etc/passwd")
    assert_not Stray::UrlGuard.allowed?("ftp://example.com/x")
  end

  test "rejects malformed URLs" do
    assert_not Stray::UrlGuard.allowed?("not a url")
    assert_not Stray::UrlGuard.allowed?("")
    assert_not Stray::UrlGuard.allowed?(nil)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/url_guard_test.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Write the guard**

`lib/stray/url_guard.rb`:

```ruby
module Stray
  module UrlGuard
    PRIVATE_RANGES = [
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10")
    ].freeze

    def self.allowed?(url)
      return false if url.blank?
      uri = URI.parse(url.to_s)
      return false unless uri.host
      return false unless uri.scheme.in?(%w[http https])

      addresses = Resolv.getaddresses(uri.host)
      return false if addresses.empty?

      addresses.all? do |addr|
        ip = IPAddr.new(addr) rescue next
        PRIVATE_RANGES.none? { |range| range.include?(ip) }
      end
    rescue URI::InvalidURIError
      false
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/url_guard_test.rb`
Expected: PASS (all tests pass).

- [ ] **Step 5: Commit**

```bash
git add lib/stray/url_guard.rb test/lib/stray/url_guard_test.rb
git commit -m "feat: add Stray::UrlGuard for SSRF protection

Blocks consumer-side fetches to loopback, private, link-local, and
IPv6 ULA addresses. Used by RemoteCollectionsController and
RemoteCollectionExtractor."
```

---

## Task 7: Stray::CollectionManifest builder

**Files:**
- Create: `lib/stray/collection_manifest.rb`
- Create: `test/lib/stray/collection_manifest_test.rb`

This is a pure-Ruby service that takes a `Collection` and a cursor, and returns the JSON-ready hash (items + pagination). Keeping it separate from the controller makes it testable without HTTP.

- [ ] **Step 1: Write the failing test**

`test/lib/stray/collection_manifest_test.rb`:

```ruby
require "test_helper"

class Stray::CollectionManifestTest < ActiveSupport::TestCase
  def setup
    @collection = collections(:econ)
    @source = sources(:youtube)
    @collection.sources << @source
    @item1 = @source.items.find_by(external_id: "vid1") || @source.items.create!(
      user: users(:one), external_id: "vid1", title: "Older", url: "https://x/1",
      content_text: "old", published_at: 2.days.ago, state: 0
    )
    @item2 = @source.items.create!(
      user: users(:one), external_id: "vid2", title: "Newer", url: "https://x/2",
      content_text: "new", content_html: "<p>new</p>",
      thumbnail_url: "https://x/2.jpg", published_at: 1.day.ago, state: 0
    )
  end

  test "builds manifest with format, version, collection, producer" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    assert_equal "stray-collection", manifest[:format]
    assert_equal 1, manifest[:version]
    assert_equal "Economics Blogs", manifest[:collection][:name]
    assert_equal "econblogssecrettoken1234", manifest[:collection][:slug]
    assert manifest[:collection][:item_count] >= 2
    assert manifest[:producer][:instance_name].present?
  end

  test "items ordered by published_at desc" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    titles = manifest[:items].map { |i| i[:title] }
    assert_equal [ "Newer", "Older" ], titles
  end

  test "item includes required fields" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "vid2" }
    assert_equal "Newer", item[:title]
    assert_equal "https://x/2", item[:url]
    assert_equal "new", item[:content_text]
    assert_equal "<p>new</p>", item[:content_html]
    assert_equal "https://x/2.jpg", item[:thumbnail_url]
    assert item[:published_at].is_a?(String)
    assert_nil item[:duration]
    assert_equal [], item[:tags]
  end

  test "item includes tags from taggings" do
    tag = Tag.create!(user: users(:one), name: "econ")
    Tagging.create!(item: @item2, tag: tag, source: :user)
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "vid2" }
    assert_equal [ "econ" ], item[:tags]
  end

  test "excludes summary and embedding and state" do
    @item2.update!(summary: "secret llm summary")
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "vid2" }
    assert_not item.key?(:summary)
    assert_not item.key?(:embedding)
    assert_not item.key?(:state)
  end

  test "excludes hidden items" do
    @item2.update!(state: :hidden)
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    ids = manifest[:items].map { |i| i[:external_id] }
    assert_not_includes ids, "vid2"
  end

  test "sources list includes kind, name, url, icon_url" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    src = manifest[:sources].find { |s| s[:url] == @source.url }
    assert_equal "youtube_channel", src[:kind]
    assert_equal "Test Channel", src[:name]
  end

  test "cursor returns next page when more items" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    assert manifest[:pagination][:has_more]
    assert manifest[:pagination][:next_cursor].present?
  end

  test "cursor nil when no more items" do
    manifest = Stray::CollectionManifest.build(@collection, cursor: nil)
    assert_not manifest[:pagination][:has_more]
    assert_nil manifest[:pagination][:next_cursor]
  end

  test "second page returns remaining items" do
    first = Stray::CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    second = Stray::CollectionManifest.build(@collection, cursor: first[:pagination][:next_cursor], page_size: 1)
    assert_not second[:pagination][:has_more]
    assert_equal 1, second[:items].size
  end

  test "next_url includes cursor" do
    first = Stray::CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    assert_includes first[:pagination][:next_url], "cursor="
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/collection_manifest_test.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Write the manifest builder**

`lib/stray/collection_manifest.rb`:

```ruby
module Stray
  class CollectionManifest
    DEFAULT_PAGE_SIZE = 100
    CURSOR_HEADER = "sc1"

    def self.build(collection, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
      new(collection, cursor, page_size, base_url).build
    end

    def initialize(collection, cursor, page_size, base_url)
      @collection = collection
      @page_size = page_size
      @base_url = base_url
      @offset = decode_offset(cursor)
    end

    def build
      items_scope = @collection.items
        .where.not(state: :hidden)
        .order(published_at: :desc)

      total = items_scope.count
      page_items = items_scope.offset(@offset).limit(@page_size).to_a

      has_more = (@offset + page_items.size) < total
      next_offset = @offset + page_items.size
      next_cursor = has_more ? encode_offset(next_offset) : nil

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
        items: page_items.map { |item| item_payload(item) },
        pagination: {
          next_cursor: next_cursor,
          next_url: has_more ? next_url(next_cursor) : nil,
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

    def item_payload(item)
      {
        external_id: item.external_id,
        title: item.title,
        url: item.url,
        content_text: item.content_text,
        content_html: item.content_html,
        thumbnail_url: item.thumbnail_url,
        published_at: item.published_at&.iso8601,
        duration: item.duration,
        tags: item_tags(item)
      }
    end

    def item_tags(item)
      item.tags.pluck(:name)
    end

    def decode_offset(cursor)
      return 0 if cursor.blank?
      decoded = Base64.urlsafe_decode64(cursor.to_s)
      payload = JSON.parse(decoded)
      raise "invalid cursor" unless payload["h"] == CURSOR_HEADER
      payload["o"].to_i
    rescue ArgumentError, JSON::ParserError
      0
    end

    def encode_offset(offset)
      Base64.urlsafe_encode64(JSON.generate({ h: CURSOR_HEADER, o: offset }))
    end

    def next_url(cursor)
      path = "/c/#{@collection.slug}/manifest.json"
      if @base_url
        "#{@base_url}#{path}?cursor=#{cursor}"
      else
        "#{path}?cursor=#{cursor}"
      end
    end
  end
end
```

Note: `Stray::VERSION` must exist. Check if it does; if not, read it from `Stray::VERSION` constant or fall back to the app's version.

- [ ] **Step 4: Ensure Stray::VERSION exists**

Run:
```bash
ls lib/stray/version.rb 2>/dev/null; grep -rn "Stray::VERSION\|module Stray" lib/stray.rb lib/stray/ 2>/dev/null | head -5
```

If no `Stray::VERSION` exists, add it. Create `lib/stray.rb` if it doesn't exist, or add the constant to the existing `lib/stray` namespace. Simplest: define it in `lib/stray/collection_manifest.rb`'s fallback if `Stray::VERSION` is undefined — but better to add a `lib/stray/version.rb`:

Create `lib/stray/version.rb`:
```ruby
module Stray
  VERSION = "0.1.0".freeze
end
```

And ensure it's loaded — add `require "stray/version"` to the top of `lib/stray/collection_manifest.rb`.

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/collection_manifest_test.rb`
Expected: PASS (all 12 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/stray/collection_manifest.rb lib/stray/version.rb \
  test/lib/stray/collection_manifest_test.rb
git commit -m "feat: add Stray::CollectionManifest builder

Produces the JSON-ready manifest hash for a Collection with
cursor-based pagination. Items ordered by published_at desc, hidden
items excluded, summary/embedding/state never shared. Tags pulled
from item taggings."
```

---

## Task 8: CollectionsController (CRUD) + views + routes

**Files:**
- Create: `app/controllers/collections_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/views/collections/index.html.erb`, `new.html.erb`, `edit.html.erb`, `show.html.erb`, `_form.html.erb`, `_collection.html.erb`
- Create: `test/controllers/collections_controller_test.rb`

- [ ] **Step 1: Add routes**

Edit `config/routes.rb` — add after `resources :sources`:

```ruby
  resources :collections do
    collection do
      get "c/:slug", to: "collections#public_show", as: :public
      get "c/:slug/manifest", to: "collections#manifest", as: :manifest, defaults: { format: :json }
      get "c/:slug/feed", to: "collections#feed", as: :feed, defaults: { format: :xml }
    end
  end
```

Actually the public routes should be top-level, not nested under the resource. Replace the above with:

```ruby
  resources :collections
  get "c/:slug", to: "collections#public_show", as: :public_collection
  get "c/:slug/manifest", to: "collections#manifest", as: :collection_manifest, defaults: { format: :json }
  get "c/:slug/feed", to: "collections#feed", as: :collection_feed, defaults: { format: :xml }
```

- [ ] **Step 2: Write the failing controller test**

`test/controllers/collections_controller_test.rb`:

```ruby
require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  test "index lists current user collections" do
    sign_in_as(users(:one))
    get collections_path
    assert_response :success
    assert_includes response.body, "Economics Blogs"
    assert_includes response.body, "Private Notes"
  end

  test "index requires authentication" do
    get collections_path
    assert_redirected_to new_session_path
  end

  test "new renders form" do
    sign_in_as(users(:one))
    get new_collection_path
    assert_response :success
    assert_includes response.body, "New collection"
  end

  test "create with valid params creates collection" do
    sign_in_as(users(:one))
    assert_difference -> { Collection.count }, 1 do
      post collections_path, params: { collection: { name: "My Feeds", description: "stuff" } }
    end
    assert_redirected_to collection_path(Collection.last)
  end

  test "create with invalid params re-renders new" do
    sign_in_as(users(:one))
    post collections_path, params: { collection: { name: "" } }
    assert_response :unprocessable_content
  end

  test "show displays collection and member sources" do
    sign_in_as(users(:one))
    get collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "Economics Blogs"
    assert_includes response.body, "Test Channel"
  end

  test "show includes share URLs" do
    sign_in_as(users(:one))
    get collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "/c/econblogssecrettoken1234/manifest"
    assert_includes response.body, "/c/econblogssecrettoken1234/feed"
  end

  test "show 404 for other user's collection" do
    sign_in_as(users(:two))
    get collection_path(collections(:econ))
    assert_response :not_found
  end

  test "edit renders form" do
    sign_in_as(users(:one))
    get edit_collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "Edit collection"
  end

  test "update changes name and description" do
    sign_in_as(users(:one))
    patch collection_path(collections(:econ)), params: { collection: { name: "Renamed", description: "new desc" } }
    assert_redirected_to collection_path(collections(:econ))
    collections(:econ).reload
    assert_equal "Renamed", collections(:econ).name
    assert_equal "new desc", collections(:econ).description
  end

  test "update can add sources" do
    sign_in_as(users(:one))
    patch collection_path(collections(:econ)), params: { collection: { source_ids: [ sources(:youtube).id, sources(:bitchute).id ] } }
    assert_redirected_to collection_path(collections(:econ))
    assert_equal 2, collections(:econ).sources.count
  end

  test "destroy deletes collection" do
    sign_in_as(users(:one))
    assert_difference -> { Collection.count }, -1 do
      delete collection_path(collections(:econ))
    end
    assert_redirected_to collections_path
  end

  test "public_show serves unlisted collection unauthenticated" do
    get public_collection_path(slug: collections(:econ).slug)
    assert_response :success
    assert_includes response.body, "Economics Blogs"
  end

  test "public_show 404 for private collection" do
    get public_collection_path(slug: collections(:private_one).slug)
    assert_response :not_found
  end

  test "manifest serves JSON unauthenticated for unlisted" do
    get collection_manifest_path(slug: collections(:econ).slug)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "stray-collection", json["format"]
    assert_equal "Economics Blogs", json["collection"]["name"]
  end

  test "manifest 404 for private collection" do
    get collection_manifest_path(slug: collections(:private_one).slug)
    assert_response :not_found
  end

  test "feed serves RSS unauthenticated" do
    get collection_feed_path(slug: collections(:econ).slug)
    assert_response :success
    assert_includes response.body, "<rss"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/collections_controller_test.rb`
Expected: FAIL — no controller / no routes.

- [ ] **Step 4: Write the controller**

`app/controllers/collections_controller.rb`:

```ruby
class CollectionsController < ApplicationController
  allow_unauthenticated_access only: %i[public_show manifest feed]

  def index
    @collections = current_user.collections.order(:name)
  end

  def new
    @collection = current_user.collections.new
  end

  def create
    @collection = current_user.collections.new(collection_params)
    if @collection.save
      redirect_to @collection, notice: "Collection created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @collection = current_user.collections.find(params[:id])
  end

  def edit
    @collection = current_user.collections.find(params[:id])
  end

  def update
    @collection = current_user.collections.find(params[:id])
    if @collection.update(collection_params)
      redirect_to @collection, notice: "Collection updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    collection = current_user.collections.find(params[:id])
    collection.destroy!
    redirect_to collections_path, notice: "Collection deleted."
  end

  def public_show
    @collection = Collection.find_by!(slug: params[:slug])
    return unless @collection.unlisted?
  end

  def manifest
    @collection = Collection.find_by!(slug: params[:slug])
    return head :not_found unless @collection.unlisted?

    manifest = Stray::CollectionManifest.build(@collection,
      cursor: params[:cursor],
      base_url: request.base_url)
    render json: manifest
  end

  def feed
    @collection = Collection.find_by!(slug: params[:slug])
    return head :not_found unless @collection.unlisted?

    @items = @collection.items.where.not(state: :hidden).order(published_at: :desc).limit(50)
    render formats: :xml
  end

  private

  def collection_params
    params.require(:collection).permit(:name, :description, source_ids: [])
  end
end
```

Note: `public_show` needs to handle private collections with a 404. Refine it:

```ruby
  def public_show
    @collection = Collection.find_by!(slug: params[:slug])
    head :not_found unless @collection.unlisted?
  end
```

(The `return unless @collection.unlisted?` form is wrong; replace with `head :not_found unless @collection.unlisted?`.)

- [ ] **Step 5: Write views**

`app/views/collections/index.html.erb`:

```erb
<% title "Collections" %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <div class="flex items-center justify-between mb-4">
    <h1 class="font-display text-2xl font-bold text-charcoal">Collections</h1>
    <%= link_to "+ New collection", new_collection_path,
          class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal" %>
  </div>

  <% if @collections.any? %>
    <div class="space-y-3">
      <%= render partial: "collections/collection", collection: @collections %>
    </div>
  <% else %>
    <div class="border-3 border-charcoal rounded-md bg-athens-400 p-8 text-center">
      <p class="text-charcoal-300">No collections yet.</p>
    </div>
  <% end %>
</main>
```

`app/views/collections/_collection.html.erb`:

```erb
<div class="border-3 border-charcoal rounded-md bg-athens-400 p-4 hover:bg-athens-500">
  <div class="flex items-center justify-between gap-4">
    <div>
      <%= link_to collection.name, collection_path(collection),
            class: "font-display font-bold text-charcoal", data: { turbo_frame: "_top" } %>
      <div class="text-xs text-charcoal-300 mt-1">
        <%= collection.sources.count %> sources
        · <%= collection.visibility %>
      </div>
    </div>
    <div class="flex items-center gap-2 shrink-0">
      <%= link_to "Edit", edit_collection_path(collection),
            class: "text-xs text-charcoal underline hover:no-underline" %>
      <%= action_link_to "Delete", collection_path(collection), method: :delete,
            confirm: "Delete this collection?",
            class: "text-xs text-cerise underline hover:no-underline" %>
    </div>
  </div>
</div>
```

`app/views/collections/new.html.erb`:

```erb
<% title "New collection" %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">New collection</h1>
  <div class="border-3 border-charcoal rounded-md bg-athens-400 p-4">
    <%= render "collections/form", collection: @collection %>
  </div>
</main>
```

`app/views/collections/edit.html.erb`:

```erb
<% title "Edit collection" %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Edit collection</h1>
  <div class="border-3 border-charcoal rounded-md bg-athens-400 p-4">
    <%= render "collections/form", collection: @collection %>
  </div>
</main>
```

`app/views/collections/_form.html.erb`:

```erb
<%= form_with model: collection, url: collection.new_record? ? collections_path : collection_path(collection) do |form| %>
  <% if collection.errors.any? %>
    <div class="mb-4 border-3 border-cerise rounded-md bg-athens-400 p-3">
      <% collection.errors.full_messages.each do |message| %>
        <p class="text-sm text-cerise"><%= message %></p>
      <% end %>
    </div>
  <% end %>

  <div class="space-y-3">
    <div>
      <%= form.label :name, class: "block text-sm font-bold text-charcoal mb-1" %>
      <%= form.text_field :name, class: "w-full h-9 px-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none" %>
    </div>

    <div>
      <%= form.label :description, class: "block text-sm font-bold text-charcoal mb-1" %>
      <%= form.text_area :description, rows: 3,
            class: "w-full px-2 py-1 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none" %>
    </div>

    <% unless collection.new_record? %>
      <div>
        <%= form.label :source_ids, "Sources", class: "block text-sm font-bold text-charcoal mb-1" %>
        <div class="space-y-2 max-h-64 overflow-y-auto p-2 border-3 border-charcoal rounded-md bg-athens-500">
          <% Source.joins(:follows).where(follows: { user_id: current_user.id }).order(:name).each do |source| %>
            <label class="flex items-center gap-2 text-sm text-charcoal">
              <%= check_box_tag "collection[source_ids][]", source.id, collection.sources.include?(source),
                    class: "h-4 w-4 border-3 border-charcoal" %>
              <%= source.name %>
              <span class="text-xs text-charcoal-300">(<%= source.kind %>)</span>
            </label>
          <% end %>
        </div>
      </div>
    <% end %>

    <div class="flex items-center gap-3 pt-2">
      <%= form.submit collection.new_record? ? "Create" : "Save",
            class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal cursor-pointer" %>
      <%= link_to "Cancel", collections_path, class: "text-sm text-charcoal underline hover:no-underline" %>
    </div>
  </div>
<% end %>
```

`app/views/collections/show.html.erb`:

```erb
<% title @collection.name %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <div class="mb-4">
    <%= link_to "← Collections", collections_path, class: "text-sm text-charcoal underline hover:no-underline" %>
    <h1 class="font-display text-2xl font-bold text-charcoal mt-2"><%= @collection.name %></h1>
    <% if @collection.description.present? %>
      <p class="text-sm text-charcoal-300 mt-1"><%= @collection.description %></p>
    <% end %>
    <div class="text-xs text-charcoal-300 mt-1">
      <%= @collection.sources.count %> sources · <%= @collection.visibility %>
    </div>
  </div>

  <div class="mb-4 border-3 border-charcoal rounded-md bg-athens-400 p-3">
    <h2 class="text-sm font-bold text-charcoal mb-2 flex items-center gap-1">
      <%= phosphor_icon "share-network", class: "w-4 h-4" %>
      Share
    </h2>
    <p class="text-xs text-charcoal-300 mb-2">Anyone with these links can view. The slug is the secret.</p>
    <div class="space-y-2">
      <div>
        <label class="block text-xs font-bold text-charcoal mb-1">Manifest (Stray-to-Stray)</label>
        <input type="text" readonly value="<%= request.base_url %><%= public_collection_path(slug: @collection.slug) %>/manifest"
               class="w-full h-9 px-2 bg-athens-500 border-2 border-charcoal rounded-md text-xs text-charcoal"
               onclick="this.select()">
      </div>
      <div>
        <label class="block text-xs font-bold text-charcoal mb-1">RSS feed (any reader)</label>
        <input type="text" readonly value="<%= request.base_url %><%= public_collection_path(slug: @collection.slug) %>/feed"
               class="w-full h-9 px-2 bg-athens-500 border-2 border-charcoal rounded-md text-xs text-charcoal"
               onclick="this.select()">
      </div>
      <div>
        <label class="block text-xs font-bold text-charcoal mb-1">Public preview page</label>
        <input type="text" readonly value="<%= request.base_url %><%= public_collection_path(slug: @collection.slug) %>"
               class="w-full h-9 px-2 bg-athens-500 border-2 border-charcoal rounded-md text-xs text-charcoal"
               onclick="this.select()">
      </div>
    </div>
  </div>

  <div class="mb-4">
    <h2 class="font-display text-lg font-bold text-charcoal mb-3">Sources</h2>
    <% if @collection.sources.any? %>
      <div class="space-y-2">
        <% @collection.sources.order(:name).each do |source| %>
          <div class="border-3 border-charcoal rounded-md bg-athens-400 p-3 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <%= source_icon(source, size: "w-8 h-8") %>
              <span class="text-sm text-charcoal"><%= source.name %></span>
            </div>
            <%= link_to "View", source_path(source), class: "text-xs text-charcoal underline hover:no-underline" %>
          </div>
        <% end %>
      </div>
    <% else %>
      <p class="text-sm text-charcoal-300">No sources yet. Edit the collection to add some.</p>
    <% end %>
  </div>

  <div class="flex items-center gap-2">
    <%= link_to "Edit", edit_collection_path(@collection),
          class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal" %>
    <%= action_link_to "Delete", collection_path(@collection), method: :delete,
          confirm: "Delete this collection?",
          class: "text-sm text-cerise underline hover:no-underline" %>
  </div>
</main>
```

`app/views/collections/public_show.html.erb`:

```erb
<% title @collection.name %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-2xl">
  <h1 class="font-display text-2xl font-bold text-charcoal"><%= @collection.name %></h1>
  <% if @collection.description.present? %>
    <p class="text-sm text-charcoal-300 mt-1"><%= @collection.description %></p>
  <% end %>
  <div class="text-xs text-charcoal-300 mt-1">
    <%= @collection.sources.count %> sources · <%= @collection.items.count %> items
  </div>

  <div class="mt-4 border-3 border-charcoal rounded-md bg-athens-400 p-4">
    <p class="text-sm text-charcoal mb-2">
      This is a Stray collection. To subscribe, paste this URL into another Stray instance:
    </p>
    <input type="text" readonly value="<%= request.base_url %><%= public_collection_path(slug: @collection.slug) %>/manifest"
           class="w-full h-9 px-2 bg-athens-500 border-2 border-charcoal rounded-md text-xs text-charcoal"
           onclick="this.select()">
  </div>

  <h2 class="font-display text-lg font-bold text-charcoal mt-6 mb-3">Sources</h2>
  <div class="space-y-2">
    <% @collection.sources.order(:name).each do |source| %>
      <div class="border-3 border-charcoal rounded-md bg-athens-400 p-3 flex items-center gap-2">
        <%= source_icon(source, size: "w-8 h-8") %>
        <span class="text-sm text-charcoal"><%= source.name %></span>
        <span class="text-xs text-charcoal-300">· <%= source.kind.humanize %></span>
      </div>
    <% end %>
  </div>
</main>
```

`app/views/collections/feed.xml.builder`:

```ruby
xml.instruct!
xml.rss(version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom") do
  xml.channel do
    xml.title @collection.name
    xml.link request.base_url + public_collection_path(slug: @collection.slug)
    xml.description @collection.description || @collection.name
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

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/collections_controller_test.rb`
Expected: PASS (all tests).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/collections_controller.rb config/routes.rb \
  app/views/collections/ test/controllers/collections_controller_test.rb
git commit -m "feat: CollectionsController CRUD + public manifest/feed endpoints

Producer side: create/edit/delete collections, add sources, get share
URLs. Public /c/:slug, /c/:slug/manifest, /c/:slug/feed are
unauthenticated and gated only by unlisted visibility."
```

---

## Task 9: RemoteCollectionExtractor

**Files:**
- Create: `lib/stray/extractors/remote_collection.rb`
- Modify: `config/initializers/extractors.rb`
- Create: `test/lib/stray/extractors/remote_collection_test.rb`
- Create: `test/vcr_cassettes/remote_collection/manifest_first_page.yml`
- Create: `test/vcr_cassettes/remote_collection/manifest_second_page.yml`

- [ ] **Step 1: Write the failing test**

`test/lib/stray/extractors/remote_collection_test.rb`:

```ruby
require "test_helper"

class Stray::Extractors::RemoteCollectionTest < ActiveSupport::TestCase
  test "handles_kind? returns true for stray_collection" do
    assert Stray::Extractors::RemoteCollection.handles_kind?("stray_collection")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Stray::Extractors::RemoteCollection.handles_kind?("rss_feed")
    assert_not Stray::Extractors::RemoteCollection.handles_kind?("youtube_channel")
  end

  test "matches? returns true for manifest.json URLs" do
    assert Stray::Extractors::RemoteCollection.matches?("https://stray.example.com/c/abc/manifest.json")
  end

  test "matches? returns false for non-manifest URLs" do
    assert_not Stray::Extractors::RemoteCollection.matches?("https://example.com/feed.xml")
  end

  test "extract_feed returns FeedResult with items from manifest" do
    VCR.use_cassette("remote_collection/manifest_first_page") do
      extractor = Stray::Extractors::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json")

      assert result.is_a?(Stray::Extractor::FeedResult)
      assert_equal 2, result.items.size
      assert_equal "First Item", result.items.first.title
      assert_equal "https://stray.example.com/posts/1", result.items.first.url
      assert_equal "item1", result.items.first.external_id
      assert_equal [ "econ", "policy" ], result.items.first.tags
      assert result.has_more
      assert result.next_cursor.present?
    end
  end

  test "extract_feed on last page returns has_more false" do
    VCR.use_cassette("remote_collection/manifest_second_page") do
      extractor = Stray::Extractors::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json?cursor=abc")

      assert result.is_a?(Stray::Extractor::FeedResult)
      assert_not result.has_more
      assert_nil result.next_cursor
    end
  end

  test "extract_feed rejects non-manifest URL with UrlGuard" do
    Stray::UrlGuard.stub(:allowed?, false) do
      extractor = Stray::Extractors::RemoteCollection.new
      assert_raises(Stray::UrlGuard::Blocked) do
        extractor.extract_feed("http://localhost/c/abc/manifest.json")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/extractors/remote_collection_test.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Record VCR cassettes**

The cassettes need real HTTP responses. Since VCR is in `record: :none` mode by default (per `test_helper.rb`), we need to record them first. Run with `VCR_RECORD=1` once:

Create a small sample manifest server is overkill; instead, hand-write the cassette YAML files. Create `test/vcr_cassettes/remote_collection/manifest_first_page.yml`:

```yaml
---
http_interactions:
- request:
    method: get
    uri: https://stray.example.com/c/abc/manifest.json
    body:
      encoding: US-ASCII
      string: ''
    headers:
      Accept-Encoding:
      - gzip;q=1.0,deflate;q=0.6,identity;q=0.3
      Accept:
      - "*/*"
      User-Agent:
      - Ruby
      Host:
      - stray.example.com
  response:
    status:
      code: 200
      message: OK
    headers:
      Content-Type:
      - application/json
      Content-Length:
      - '412'
    body:
      encoding: UTF-8
      string: '{"format":"stray-collection","version":1,"collection":{"name":"Econ","slug":"abc","item_count":3},"producer":{"instance_name":"Alice","instance_domain":"stray.example.com","stray_version":"0.1.0"},"sources":[{"url":"https://feeds.example.com/econ1","kind":"rss_feed","name":"Econ Blog","icon_url":null}],"items":[{"external_id":"item1","title":"First Item","url":"https://stray.example.com/posts/1","content_text":"content","content_html":"<p>content</p>","thumbnail_url":"https://stray.example.com/1.jpg","published_at":"2026-08-15T10:00:00Z","duration":null,"tags":["econ","policy"]},{"external_id":"item2","title":"Second Item","url":"https://stray.example.com/posts/2","content_text":"more","content_html":null,"thumbnail_url":null,"published_at":"2026-08-14T10:00:00Z","duration":null,"tags":[]}],"pagination":{"next_cursor":"page2cursor","next_url":"https://stray.example.com/c/abc/manifest.json?cursor=page2cursor","has_more":true}}'
    http_version:
  recorded_at: Sun, 16 Aug 2026 00:00:00 GMT
recorded_with: VCR 6.0.0
```

Create `test/vcr_cassettes/remote_collection/manifest_second_page.yml`:

```yaml
---
http_interactions:
- request:
    method: get
    uri: https://stray.example.com/c/abc/manifest.json?cursor=abc
    body:
      encoding: US-ASCII
      string: ''
    headers:
      Accept-Encoding:
      - gzip;q=1.0,deflate;q=0.6,identity;q=0.3
      Accept:
      - "*/*"
      User-Agent:
      - Ruby
      Host:
      - stray.example.com
  response:
    status:
      code: 200
      message: OK
    headers:
      Content-Type:
      - application/json
      Content-Length:
      - '280'
    body:
      encoding: UTF-8
      string: '{"format":"stray-collection","version":1,"collection":{"name":"Econ","slug":"abc","item_count":3},"producer":{"instance_name":"Alice","instance_domain":"stray.example.com","stray_version":"0.1.0"},"sources":[],"items":[{"external_id":"item3","title":"Third Item","url":"https://stray.example.com/posts/3","content_text":"last","content_html":null,"thumbnail_url":null,"published_at":"2026-08-13T10:00:00Z","duration":null,"tags":[]}],"pagination":{"next_cursor":null,"next_url":null,"has_more":false}}'
    http_version:
  recorded_at: Sun, 16 Aug 2026 00:00:00 GMT
recorded_with: VCR 6.0.0
```

- [ ] **Step 4: Write the extractor**

`lib/stray/extractors/remote_collection.rb`:

```ruby
require "faraday"
require "stray/url_guard"

module Stray
  module Extractors
    class RemoteCollection < Stray::Extractor
      MAX_ITEMS_PER_PAGE = 1000

      def self.matches?(url)
        url.to_s.end_with?("/manifest.json") || url.to_s.include?("/manifest.json?cursor=")
      rescue URI::InvalidURIError
        false
      end

      def self.handles_kind?(kind)
        kind == "stray_collection"
      end

      def extract(url)
        extract_feed(url).items
      end

      def extract_feed(url)
        raise Stray::UrlGuard::Blocked, "URL blocked by UrlGuard" unless Stray::UrlGuard.allowed?(url)

        response = http_client.get(url)
        raise "manifest fetch failed: #{response.status}" unless response.status == 200

        parse(response.body)
      end

      private

      def parse(body)
        data = JSON.parse(body)
        raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

        items = (data["items"] || []).first(MAX_ITEMS_PER_PAGE).map do |item|
          ExtractedContent.new(
            url: item["url"],
            title: item["title"],
            content_text: item["content_text"],
            content_html: item["content_html"],
            thumbnail_url: item["thumbnail_url"],
            published_at: item["published_at"] && Time.parse(item["published_at"]),
            external_id: item["external_id"],
            duration: item["duration"],
            creator_identity: nil,
            tags: item["tags"] || []
          )
        end

        pagination = data["pagination"] || {}
        Stray::Extractor::FeedResult.new(
          items: items,
          next_cursor: pagination["next_cursor"],
          has_more: pagination["has_more"] || false
        )
      end

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects, max: 3
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end
    end
  end
end
```

- [ ] **Step 5: Add UrlGuard::Blocked error**

Edit `lib/stray/url_guard.rb` — add inside the `UrlGuard` module:

```ruby
module Stray
  module UrlGuard
    class Blocked < StandardError; end
    # ... existing code ...
  end
end
```

- [ ] **Step 6: Register the extractor**

Edit `config/initializers/extractors.rb`:

```ruby
Rails.application.config.to_prepare do
  Stray::ExtractorRegistry.reset!
  Stray::ExtractorRegistry.register(Stray::Extractors::YoutubeRss)
  Stray::ExtractorRegistry.register(Stray::Extractors::RssAtom)
  Stray::ExtractorRegistry.register(Stray::Extractors::YtDlp)
  Stray::ExtractorRegistry.register(Stray::Extractors::RemoteCollection)
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/lib/stray/extractors/remote_collection_test.rb`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add lib/stray/extractors/remote_collection.rb lib/stray/url_guard.rb \
  config/initializers/extractors.rb \
  test/lib/stray/extractors/remote_collection_test.rb \
  test/vcr_cassettes/remote_collection/
git commit -m "feat: add RemoteCollectionExtractor + register it

Fetches paginated JSON manifest, returns FeedResult. SSRF-guarded via
UrlGuard. Tags flow through ExtractedContent.tags to existing
SourcePollJob apply_extractor_tags path."
```

---

## Task 10: SourcePollJob pagination changes

**Files:**
- Modify: `app/jobs/source_poll_job.rb`
- Modify: `test/jobs/source_poll_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/jobs/source_poll_job_test.rb` (inside the existing class):

```ruby
  test "enqueues next page when FeedResult has_more true" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Stray::Extractor::FeedResult.new(items: items, next_cursor: "cur2", has_more: true)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])
    @verify_extractor = true

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: SourcePollJob, args: [ source.id, "cur2" ]) do
          SourcePollJob.perform_now(source.id)
        end
      end
    end
  end

  test "updates RemoteCollection after full sync" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    rc = RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Stray::Extractor::FeedResult.new(items: items, next_cursor: nil, has_more: false)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    rc.reload
    assert_not_nil rc.last_synced_at
    assert_equal 1, rc.item_count
    assert_nil rc.last_error
  end

  test "early stops when page contains only known external_ids" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)
    source.items.create!(user: @user, external_id: "known1", title: "Old",
      url: "https://x/1", published_at: 1.day.ago, state: 0)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "Old", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: 1.day.ago, external_id: "known1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Stray::Extractor::FeedResult.new(items: items, next_cursor: "cur2", has_more: true)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_no_enqueued_jobs(only: SourcePollJob) do
          SourcePollJob.perform_now(source.id)
        end
      end
    end
  end

  test "records RemoteCollection error on fetch failure" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    rc = RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)
    @verify_extractor = false

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::UrlGuard::Blocked, "blocked" }

    Stray::ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    rc.reload
    assert_not_nil rc.last_error
    assert_not_nil rc.last_error_at
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: FAIL — pagination not implemented.

- [ ] **Step 3: Modify SourcePollJob**

Edit `app/jobs/source_poll_job.rb`. Replace the whole file with:

```ruby
class SourcePollJob < ApplicationJob
  queue_as :polling

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  discard_on Stray::YtDlp::Error do |job, error|
    source = Source.find_by(id: job.arguments.first)
    return unless source

    source.update!(last_error: error.message, last_error_at: Time.current)
  end

  def perform(source_id, cursor = nil)
    source = Source.find_by(id: source_id)
    return unless source&.active?

    source.update!(polling: true)
    broadcast_source_update(source)

    domain = Stray::DomainMutex.domain_for(source.url)

    if source.kind == "stray_collection"
      extract_and_persist_relay(source, cursor)
    else
      Stray::DomainMutex.with_lock(domain) do
        extract_and_persist(source)
      end
    end
  ensure
    if source
      source.update!(polling: false)
      broadcast_source_update(source)
    end
  end

  private

  def extract_and_persist(source)
    extractor = Stray::ExtractorRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No extractor for kind=#{source.kind} url=#{source.url}" unless extractor

    contents = extractor.extract_feed(source.url)
    contents = Array(contents)

    upsert_items(source, contents)
    backfill_source_metadata(source, contents)
    source.recalculate_next_crawl!
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil)
  rescue NotImplementedError => e
    source.update!(last_error: "Extractor missing extract_feed: #{e.message}", last_error_at: Time.current)
  end

  def extract_and_persist_relay(source, cursor)
    extractor = Stray::ExtractorRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No extractor for kind=#{source.kind}" unless extractor

    fetch_url = cursor ? "#{source.url}?cursor=#{cursor}" : source.url
    result = extractor.extract_feed(fetch_url)

    if result.is_a?(Stray::Extractor::FeedResult)
      handle_feed_result(source, result, cursor)
    else
      upsert_items(source, Array(result))
      finish_relay_sync(source, cursor)
    end
  rescue Stray::UrlGuard::Blocked, StandardError => e
    update_relay_error(source, e.message)
  end

  def handle_feed_result(source, result, cursor)
    upsert_items(source, result.items)

    if early_stop?(source, result.items)
      finish_relay_sync(source, cursor)
      return
    end

    if result.has_more && result.next_cursor.present?
      SourcePollJob.perform_later(source.id, result.next_cursor)
    else
      finish_relay_sync(source, cursor)
    end
  end

  def early_stop?(source, items)
    return false if items.empty?
    external_ids = items.map(&:external_id)
    existing = source.items.where(external_id: external_ids).pluck(:external_id).to_set
    external_ids.all? { |id| existing.include?(id) }
  end

  def finish_relay_sync(source, cursor)
    rc = source.remote_collection
    return unless rc

    rc.update!(
      last_synced_at: Time.current,
      item_count: source.items.count,
      last_cursor: cursor,
      last_error: nil,
      last_error_at: nil
    )
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil)
    source.recalculate_next_crawl!
  end

  def update_relay_error(source, message)
    source.update!(last_error: message, last_error_at: Time.current)
    rc = source.remote_collection
    rc&.update!(last_error: message, last_error_at: Time.current)
  end

  def backfill_source_metadata(source, contents)
    updates = {}
    if source.name.nil?
      creator = contents.map(&:creator_identity).compact.find { |c| c.name }
      updates[:name] = creator.name if creator
    end
    if source.icon_url.nil?
      creator = contents.map(&:creator_identity).compact.find { |c| c.thumbnail_url }
      updates[:icon_url] = creator.thumbnail_url if creator
    end
    source.update!(updates) if updates.any?
  end

  def upsert_items(source, contents)
    return if contents.empty?

    rows = contents.map do |content|
      {
        source_id: source.id,
        user_id: source.user_id,
        external_id: content.external_id,
        title: content.title,
        url: content.url,
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

    Item.upsert_all(rows, unique_by: [ :source_id, :external_id ], returning: :id).then do |result|
      item_ids = result.to_a.map { |row| row["id"] }

      missing_thumb_ids = []
      contents.each_with_index do |content, i|
        item_id = item_ids[i]
        apply_extractor_tags(source, item_id, content)
        EmbeddingJob.perform_later("Item", item_id)
        missing_thumb_ids << item_id if content.thumbnail_url.blank?
      end

      ThumbnailEnrichmentJob.perform_later(source.id, missing_thumb_ids) if missing_thumb_ids.any?
    end
  end

  def apply_extractor_tags(source, item_id, content)
    return unless content.tags&.any?

    item = Item.find(item_id)
    content.tags.each do |name|
      tag = Tag.find_or_create_by!(user_id: source.user_id, name: name)
      Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
      EmbeddingJob.perform_later("Tag", tag.id) if tag.embedding.nil?
    end
  end

  def broadcast_source_update(source)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/source_poll_job_test.rb`
Expected: PASS (all tests, including the 4 new ones + existing ones).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/source_poll_job.rb test/jobs/source_poll_job_test.rb
git commit -m "feat: SourcePollJob handles FeedResult pagination for relay

Stray-collection sources skip DomainMutex (no shared origin). Walks
manifest pages, early-stops on all-known page, updates RemoteCollection
sync state. Backwards-compatible with existing array-returning extractors."
```

---

## Task 11: RemoteCollectionsController + views + routes

**Files:**
- Create: `app/controllers/remote_collections_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/views/remote_collections/new.html.erb`, `preview.html.erb`
- Modify: `app/views/sources/index.html.erb` (entry point)
- Create: `test/controllers/remote_collections_controller_test.rb`

- [ ] **Step 1: Add routes**

Edit `config/routes.rb` — add:

```ruby
  resource :remote_collection, only: %i[new create destroy] do
    post :subscribe
  end
```

- [ ] **Step 2: Write the failing controller test**

`test/controllers/remote_collections_controller_test.rb`:

```ruby
require "test_helper"

class RemoteCollectionsControllerTest < ActionDispatch::IntegrationTest
  test "new renders form with manifest_url field" do
    sign_in_as(users(:one))
    get new_remote_collection_path
    assert_response :success
    assert_includes response.body, "manifest_url"
  end

  test "new requires authentication" do
    get new_remote_collection_path
    assert_redirected_to new_session_path
  end

  test "create fetches manifest and renders preview" do
    sign_in_as(users(:one))
    VCR.use_cassette("remote_collection/manifest_first_page") do
      post remote_collection_path, params: { remote_collection: { manifest_url: "https://stray.example.com/c/abc/manifest.json" } }
    end
    assert_response :success
    assert_includes response.body, "Econ"
    assert_includes response.body, "Subscribe"
  end

  test "create rejects blocked URL" do
    sign_in_as(users(:one))
    post remote_collection_path, params: { remote_collection: { manifest_url: "http://localhost:3000/c/abc/manifest.json" } }
    assert_response :unprocessable_content
    assert_includes response.body, "blocked"
  end

  test "create with invalid manifest returns error" do
    sign_in_as(users(:one))
    VCR.use_cassette("remote_collection/manifest_empty") do
      post remote_collection_path, params: { remote_collection: { manifest_url: "https://stray.example.com/c/none/manifest.json" } }
    end
    assert_response :unprocessable_content
  end

  test "subscribe creates Source + Follow + RemoteCollection and enqueues poll" do
    sign_in_as(users(:one))
    assert_difference -> { Source.count }, 1 do
      assert_difference -> { Follow.count }, 1 do
        assert_difference -> { RemoteCollection.count }, 1 do
          assert_enqueued_with(job: SourcePollJob) do
            post subscribe_remote_collection_path, params: {
              remote_collection: {
                manifest_url: "https://stray.example.com/c/abc/manifest.json",
                collection_name: "Econ",
                producer_instance_name: "Alice"
              }
            }
          end
        end
      end
    end
    source = Source.find_by(kind: :stray_collection)
    assert_redirected_to source_path(source)
  end

  test "subscribe rejects duplicate (same user + manifest_url)" do
    sign_in_as(users(:one))
    existing = RemoteCollection.create!(
      source: sources(:remote),
      user: users(:one),
      manifest_url: sources(:remote).url
    )
    assert_no_difference -> { Source.count } do
      post subscribe_remote_collection_path, params: {
        remote_collection: { manifest_url: sources(:remote).url, collection_name: "X" }
      }
    end
    assert_redirected_to source_path(sources(:remote))
  end

  test "subscribe requires authentication" do
    post subscribe_remote_collection_path, params: { remote_collection: { manifest_url: "https://x" } }
    assert_redirected_to new_session_path
  end

  test "destroy deletes source and remote collection" do
    sign_in_as(users(:one))
    source = sources(:remote)
    assert_difference -> { Source.count }, -1 do
      assert_difference -> { RemoteCollection.count }, -1 do
        delete remote_collection_path
      end
    end
    assert_redirected_to sources_path
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/controllers/remote_collections_controller_test.rb`
Expected: FAIL — no controller.

- [ ] **Step 4: Add a VCR cassette for empty manifest**

`test/vcr_cassettes/remote_collection/manifest_empty.yml`:

```yaml
---
http_interactions:
- request:
    method: get
    uri: https://stray.example.com/c/none/manifest.json
    body:
      encoding: US-ASCII
      string: ''
    headers:
      Accept-Encoding:
      - gzip;q=1.0,deflate;q=0.6,identity;q=0.3
      Accept:
      - "*/*"
      User-Agent:
      - Ruby
      Host:
      - stray.example.com
  response:
    status:
      code: 404
      message: Not Found
    headers:
      Content-Type:
      - text/html
      Content-Length:
      - '0'
    body:
      encoding: UTF-8
      string: ''
    http_version:
  recorded_at: Sun, 16 Aug 2026 00:00:00 GMT
recorded_with: VCR 6.0.0
```

- [ ] **Step 5: Write the controller**

`app/controllers/remote_collections_controller.rb`:

```ruby
class RemoteCollectionsController < ApplicationController
  def new
  end

  def create
    url = params.dig(:remote_collection, :manifest_url).to_s.strip

    unless Stray::UrlGuard.allowed?(url)
      @error = "URL blocked (private or loopback address)."
      render :new, status: :unprocessable_content
      return
    end

    begin
      preview = fetch_manifest_preview(url)
      @manifest_url = url
      @collection_name = preview[:collection_name]
      @producer_instance_name = preview[:producer_instance_name]
      @source_count = preview[:source_count]
      @item_samples = preview[:item_samples]
      render :preview
    rescue StandardError => e
      @error = "Could not fetch manifest: #{e.message}"
      render :new, status: :unprocessable_content
    end
  end

  def subscribe
    url = params.dig(:remote_collection, :manifest_url).to_s.strip
    collection_name = params.dig(:remote_collection, :collection_name)
    producer_instance_name = params.dig(:remote_collection, :producer_instance_name)

    if existing = current_user.remote_collections.find_by(manifest_url: url)
      redirect_to source_path(existing.source), notice: "Already subscribed."
      return
    end

    source = Source.create!(
      user: current_user,
      kind: :stray_collection,
      url: url,
      name: collection_name || "Remote collection",
      external_id: derive_external_id(url),
      active: true
    )
    Follow.create!(user: current_user, source: source)
    rc = RemoteCollection.create!(
      source: source,
      user: current_user,
      manifest_url: url,
      collection_name: collection_name,
      producer_instance_name: producer_instance_name
    )
    SourcePollJob.perform_later(source.id)
    redirect_to source_path(source), notice: "Subscribed. Syncing first page…"
  end

  def destroy
    rc = current_user.remote_collections.find_by!(source_id: params[:source_id] || params[:id])
    source = rc.source
    rc.destroy!
    source.destroy!
    redirect_to sources_path, notice: "Unsubscribed from remote collection."
  end

  private

  def fetch_manifest_preview(url)
    extractor = Stray::Extractors::RemoteCollection.new
    result = extractor.extract_feed(url)
    {
      collection_name: result.items.any? ? nil : nil,
      producer_instance_name: nil,
      source_count: 0,
      item_samples: result.items.first(5).map { |i| { title: i.title, url: i.url } }
    }
  rescue Stray::UrlGuard::Blocked
    raise "URL blocked"
  rescue => e
    raise e
  end

  def derive_external_id(url)
    Digest::SHA256.hexdigest(url)[0, 16]
  end
end
```

Note: the `fetch_manifest_preview` above doesn't pull the collection name / producer from the manifest because `extract_feed` only returns `FeedResult`. To get the metadata, we need the raw JSON. Refine the preview fetch to parse the manifest directly:

```ruby
  def fetch_manifest_preview(url)
    response = Stray::Extractors::RemoteCollection.new.send(:http_client).get(url)
    raise "manifest fetch failed: #{response.status}" unless response.status == 200

    data = JSON.parse(response.body)
    raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

    {
      collection_name: data.dig("collection", "name"),
      producer_instance_name: data.dig("producer", "instance_name"),
      source_count: (data["sources"] || []).size,
      item_count: data.dig("collection", "item_count"),
      item_samples: (data["items"] || []).first(5).map { |i| { title: i["title"], url: i["url"] } }
    }
  rescue Stray::UrlGuard::Blocked
    raise "URL blocked"
  rescue => e
    raise e
  end
```

But `http_client` is private in the extractor. Either make it public or inline a simpler Faraday call in the controller. Inlining is cleaner since the controller is a one-off preview fetch:

```ruby
  def fetch_manifest_preview(url)
    raise "URL blocked" unless Stray::UrlGuard.allowed?(url)

    response = Faraday.new do |conn|
      conn.response :follow_redirects, max: 3
      conn.options.timeout = 10
      conn.adapter :net_http
    end.get(url)

    raise "fetch failed: HTTP #{response.status}" unless response.status == 200

    data = JSON.parse(response.body)
    raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

    {
      collection_name: data.dig("collection", "name"),
      producer_instance_name: data.dig("producer", "instance_name"),
      source_count: (data["sources"] || []).size,
      item_count: data.dig("collection", "item_count"),
      item_samples: (data["items"] || []).first(5).map { |i| { title: i["title"], url: i["url"] } }
    }
  rescue JSON::ParserError
    raise "invalid JSON"
  end
```

Use this final version in the controller. Remove the `extractor` reference. The full controller:

```ruby
class RemoteCollectionsController < ApplicationController
  def new
  end

  def create
    url = params.dig(:remote_collection, :manifest_url).to_s.strip

    begin
      @preview = fetch_manifest_preview(url)
      @manifest_url = url
      render :preview
    rescue Stray::UrlGuard::Blocked, StandardError => e
      @error = "Could not fetch manifest: #{e.message}"
      render :new, status: :unprocessable_content
    end
  end

  def subscribe
    url = params.dig(:remote_collection, :manifest_url).to_s.strip
    collection_name = params.dig(:remote_collection, :collection_name)
    producer_instance_name = params.dig(:remote_collection, :producer_instance_name)

    if existing = current_user.remote_collections.find_by(manifest_url: url)
      redirect_to source_path(existing.source), notice: "Already subscribed."
      return
    end

    source = Source.create!(
      user: current_user,
      kind: :stray_collection,
      url: url,
      name: collection_name || "Remote collection",
      external_id: derive_external_id(url),
      active: true
    )
    Follow.create!(user: current_user, source: source)
    RemoteCollection.create!(
      source: source,
      user: current_user,
      manifest_url: url,
      collection_name: collection_name,
      producer_instance_name: producer_instance_name
    )
    SourcePollJob.perform_later(source.id)
    redirect_to source_path(source), notice: "Subscribed. Syncing first page…"
  end

  def destroy
    rc = current_user.remote_collections.find_by!(source_id: params[:source_id])
    source = rc.source
    rc.destroy!
    source.destroy!
    redirect_to sources_path, notice: "Unsubscribed from remote collection."
  end

  private

  def fetch_manifest_preview(url)
    raise Stray::UrlGuard::Blocked, "URL blocked" unless Stray::UrlGuard.allowed?(url)

    response = Faraday.new do |conn|
      conn.response :follow_redirects, max: 3
      conn.options.timeout = 10
      conn.adapter :net_http
    end.get(url)

    raise "fetch failed: HTTP #{response.status}" unless response.status == 200

    data = JSON.parse(response.body)
    raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

    {
      collection_name: data.dig("collection", "name"),
      producer_instance_name: data.dig("producer", "instance_name"),
      source_count: (data["sources"] || []).size,
      item_count: data.dig("collection", "item_count"),
      item_samples: (data["items"] || []).first(5).map { |i| { title: i["title"], url: i["url"] } }
    }
  rescue JSON::ParserError
    raise "invalid JSON"
  end

  def derive_external_id(url)
    Digest::SHA256.hexdigest(url)[0, 16]
  end
end
```

- [ ] **Step 6: Write views**

`app/views/remote_collections/new.html.erb`:

```erb
<% title "Subscribe to remote collection" %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Subscribe to remote collection</h1>

  <% if @error %>
    <div class="mb-4 border-3 border-cerise rounded-md bg-athens-400 p-3">
      <p class="text-sm text-cerise"><%= @error %></p>
    </div>
  <% end %>

  <div class="border-3 border-charcoal rounded-md bg-athens-400 p-4">
    <%= form_with url: remote_collection_path, method: :post, scope: :remote_collection, local: true do |form| %>
      <div>
        <%= form.label :manifest_url, "Manifest URL", class: "block text-sm font-bold text-charcoal mb-1" %>
        <%= form.url_field :manifest_url, placeholder: "https://stray.example.com/c/abc123.../manifest",
              class: "w-full h-9 px-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none" %>
        <p class="text-xs text-charcoal-300 mt-1">Paste the share URL you received from another Stray instance.</p>
      </div>
      <div class="mt-3">
        <%= form.submit "Preview",
              class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal cursor-pointer" %>
        <%= link_to "Cancel", sources_path, class: "text-sm text-charcoal underline hover:no-underline ml-2" %>
      </div>
    <% end %>
  </div>
</main>
```

`app/views/remote_collections/preview.html.erb`:

```erb
<% title "Preview collection" %>

<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Preview collection</h1>

  <div class="border-3 border-charcoal rounded-md bg-athens-400 p-4 mb-4">
    <h2 class="font-display text-lg font-bold text-charcoal"><%= @preview[:collection_name] %></h2>
    <div class="text-xs text-charcoal-300 mt-1">
      From <%= @preview[:producer_instance_name] || "unknown instance" %>
      · <%= @preview[:source_count] %> sources
      · <%= @preview[:item_count] %> items
    </div>
  </div>

  <% if @preview[:item_samples].any? %>
    <h3 class="font-bold text-charcoal mb-2">Latest items</h3>
    <ul class="space-y-1 mb-4">
      <% @preview[:item_samples].each do |item| %>
        <li class="text-sm text-charcoal">
          <%= link_to item[:title], item[:url], target: "_blank", rel: "noopener",
                class: "underline hover:no-underline" %>
        </li>
      <% end %>
    </ul>
  <% end %>

  <%= form_with url: subscribe_remote_collection_path, method: :post, scope: :remote_collection do |form| %>
    <%= form.hidden_field :manifest_url, value: @manifest_url %>
    <%= form.hidden_field :collection_name, value: @preview[:collection_name] %>
    <%= form.hidden_field :producer_instance_name, value: @preview[:producer_instance_name] %>
    <%= form.submit "Subscribe",
          class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal cursor-pointer" %>
    <%= link_to "Cancel", sources_path, class: "text-sm text-charcoal underline hover:no-underline ml-2" %>
  <% end %>
</main>
```

- [ ] **Step 7: Add entry point in sources index**

Edit `app/views/sources/index.html.erb` — change the header div to include a second button:

Replace:
```erb
    <%= link_to "+ Add source", new_source_path,
          class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal" %>
```
with:
```erb
    <div class="flex items-center gap-2">
      <%= link_to new_remote_collection_path,
            class: "flex items-center gap-1 bg-athens-400 hover:bg-athens-500 text-charcoal font-bold text-sm px-3 py-2 rounded-md border-3 border-charcoal",
            title: "Subscribe to remote collection" do %>
        <%= phosphor_icon "cloud-arrow-down", class: "w-4 h-4" %>
        Remote
      <% end %>
      <%= link_to "+ Add source", new_source_path,
            class: "bg-carrot-500 hover:bg-carrot-600 text-white font-bold text-sm px-4 py-2 rounded-md border-3 border-charcoal" %>
    </div>
```

- [ ] **Step 8: Add Collections link to sidebar**

Edit `app/views/sources/_sidebar.html.erb` — add before the closing `</div>` of the `<div class="p-4">`:

```erb
    <%= link_to "Collections", collections_path,
          class: "block mt-4 text-sm text-charcoal underline hover:no-underline" %>
```

Place it right after the existing `All Sources` link.

- [ ] **Step 9: Run test to verify it passes**

Run: `bin/rails test test/controllers/remote_collections_controller_test.rb`
Expected: PASS (all tests).

- [ ] **Step 10: Commit**

```bash
git add app/controllers/remote_collections_controller.rb config/routes.rb \
  app/views/remote_collections/ app/views/sources/index.html.erb \
  app/views/sources/_sidebar.html.erb \
  test/controllers/remote_collections_controller_test.rb \
  test/vcr_cassettes/remote_collection/manifest_empty.yml
git commit -m "feat: RemoteCollectionsController (preview + subscribe + destroy)

Consumer-side flow: paste manifest URL, preview, subscribe creates
Source+Follow+RemoteCollection and enqueues first sync. Entry point
added to sources index and sidebar."
```

---

## Task 12: End-to-end integration test

**Files:**
- Create: `test/integration/collection_sync_flow_test.rb`

- [ ] **Step 1: Write the integration test**

`test/integration/collection_sync_flow_test.rb`:

```ruby
require "test_helper"

class CollectionSyncFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @collection = collections(:econ)
    @source = sources(:youtube)
    @collection.sources << @source
    @item = @source.items.create!(
      user: @user, external_id: "relay-item-1", title: "Relayed Video",
      url: "https://example.com/watch?v=relay1", content_text: "relayed content",
      published_at: 1.day.ago, state: 0
    )
    tag = Tag.create!(user: @user, name: "relay-tag")
    Tagging.create!(item: @item, tag: tag, source: :user)
  end

  test "producer serves manifest with items and tags" do
    get collection_manifest_path(slug: @collection.slug)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "stray-collection", json["format"]
    assert_equal "Economics Blogs", json.dig("collection", "name")
    item = json["items"].find { |i| i["external_id"] == "relay-item-1" }
    assert_equal "Relayed Video", item["title"]
    assert_equal "relayed content", item["content_text"]
    assert_includes item["tags"], "relay-tag"
    assert_not item.key?("summary")
    assert_not item.key?("embedding")
    assert_not item.key?("state")
  end

  test "consumer subscribes, syncs, and items appear in feed with tags" do
    sign_in_as(@user)
    manifest_url = "https://stray.example.com/c/#{@collection.slug}/manifest.json"

    VCR.use_cassette("remote_collection/integration_manifest", match_requests_on: [ :method, :uri ]) do
      post remote_collection_path, params: { remote_collection: { manifest_url: manifest_url } }
      assert_response :success
      assert_includes response.body, "Economics Blogs"

      assert_difference -> { Source.where(kind: :stray_collection).count }, 1 do
        assert_enqueued_with(job: SourcePollJob) do
          post subscribe_remote_collection_path, params: {
            remote_collection: {
              manifest_url: manifest_url,
              collection_name: "Economics Blogs",
              producer_instance_name: "Alice's Stray"
            }
          }
        end
      end
    end

    source = Source.find_by(kind: :stray_collection)
    assert_redirected_to source_path(source)

    perform_enqueued_jobs(only: SourcePollJob)

    assert source.items.exists?(external_id: "relay-item-1", title: "Relayed Video")
    relayed = source.items.find_by(external_id: "relay-item-1")
    assert Tagging.exists?(item: relayed, tag: Tag.find_by(user: @user, name: "relay-tag"), source: :user)

    get root_path
    assert_includes response.body, "Relayed Video"

    get root_path(tag: "relay-tag")
    assert_includes response.body, "Relayed Video"
  end
end
```

- [ ] **Step 2: Create the VCR cassette**

`test/vcr_cassettes/remote_collection/integration_manifest.yml`:

```yaml
---
http_interactions:
- request:
    method: get
    uri: https://stray.example.com/c/econblogssecrettoken1234/manifest.json
    body:
      encoding: US-ASCII
      string: ''
    headers:
      Accept-Encoding:
      - gzip;q=1.0,deflate;q=0.6,identity;q=0.3
      Accept:
      - "*/*"
      User-Agent:
      - Ruby
      Host:
      - stray.example.com
  response:
    status:
      code: 200
      message: OK
    headers:
      Content-Type:
      - application/json
      Content-Length:
      - '300'
    body:
      encoding: UTF-8
      string: '{"format":"stray-collection","version":1,"collection":{"name":"Economics Blogs","slug":"econblogssecrettoken1234","item_count":1},"producer":{"instance_name":"Alice''s Stray","instance_domain":"stray.example.com","stray_version":"0.1.0"},"sources":[{"url":"https://www.youtube.com/feeds/videos.xml?channel_id=UCfeed","kind":"youtube_channel","name":"Test Channel","icon_url":"https://example.com/youtube-avatar.png"}],"items":[{"external_id":"relay-item-1","title":"Relayed Video","url":"https://example.com/watch?v=relay1","content_text":"relayed content","content_html":null,"thumbnail_url":null,"published_at":"2026-08-15T00:00:00Z","duration":null,"tags":["relay-tag"]}],"pagination":{"next_cursor":null,"next_url":null,"has_more":false}}'
    http_version:
  recorded_at: Sun, 16 Aug 2026 00:00:00 GMT
recorded_with: VCR 6.0.0
```

- [ ] **Step 3: Run the test**

Run: `bin/rails test test/integration/collection_sync_flow_test.rb`
Expected: PASS (2 tests).

- [ ] **Step 4: Commit**

```bash
git add test/integration/collection_sync_flow_test.rb \
  test/vcr_cassettes/remote_collection/integration_manifest.yml
git commit -m "test: end-to-end collection relay sync flow

Producer manifest serves items + tags; consumer subscribes, SourcePollJob
imports items, tags filterable in feed via ?tag= param."
```

---

## Task 13: Full test suite + lint + security scan

- [ ] **Step 1: Run the full test suite**

Run:
```bash
bin/rails db:test:prepare && bin/rails test
```
Expected: All tests pass.

- [ ] **Step 2: Run RuboCop**

Run: `bin/rubocop`
Expected: No offenses (or only pre-existing ones). Fix any new ones introduced by this plan.

- [ ] **Step 3: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: No new warnings. Pay attention to:
- `RemoteCollectionsController#create` — URL fetch (the SSRF guard mitigates, but Brakeman may flag it; verify it's a false positive).
- `CollectionsController#manifest` — `render json:` is safe.
- `CollectionsController#feed` — XML builder is safe.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "chore: lint + security fixes from collection sharing work"
```

- [ ] **Step 5: Run bundler-audit**

Run: `bin/bundler-audit`
Expected: No new vulnerabilities (no new gems added by this plan).

---

## Self-Review

**Spec coverage check:**
- ✅ Collection model (name, visibility, slug, explicit source list) — Task 2, 3
- ✅ RemoteCollection model (1:1 with Source, sync state) — Task 4
- ✅ Source.kind :stray_collection — Task 4
- ✅ JSON manifest format v1 (paginated, cursor, items + content_text + tags) — Task 7
- ✅ RSS/Atom feed — Task 8
- ✅ Public preview page — Task 8
- ✅ RemoteCollectionExtractor — Task 9
- ✅ FeedResult struct — Task 5
- ✅ SourcePollJob pagination + early-stop + RemoteCollection update — Task 10
- ✅ CollectionsController (CRUD + public routes) — Task 8
- ✅ RemoteCollectionsController (new + create preview + subscribe + destroy) — Task 11
- ✅ SSRF guard — Task 6
- ✅ Tag relay (via existing apply_extractor_tags) — Task 9, 10
- ✅ Producer content privacy (no summary/embedding/state) — Task 7 (tested)
- ✅ Docs update (AGENTS.md, README.md) — Task 1
- ✅ Integration test — Task 12
- ⚠️ Rate limiting on manifest/feed endpoints — flagged in spec as open decision; not in plan (defer to runtime).
- ⚠️ Relay poll floor (15 min) — not explicitly added; `recalculate_next_crawl!` adapts. If needed, add a `MIN_RELAY_POLL_INTERVAL` constant in SourcePollJob. Note for executor: consider adding a guard in `finish_relay_sync` that clamps `next_crawl_at` to at least 15 minutes from now.

**Placeholder scan:** No TBDs, no "implement later", no empty steps. All code blocks are complete.

**Type consistency:** `FeedResult` used consistently (Task 5 defines, Task 9 returns, Task 10 consumes). `RemoteCollection` attributes match across Task 4 (model) and Task 10 (job updates). `manifest_url` is the column name everywhere. `:stray_collection` enum value consistent.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-08-16-collection-sharing-relay.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
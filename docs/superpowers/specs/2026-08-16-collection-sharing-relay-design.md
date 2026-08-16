# Stray Collection Sharing + Remote Relay Sync — Design

**Date:** 2026-08-16
**Status:** Approved (brainstormed 2026-08-16)
**Author:** Pair session (user + assistant)

## Goal

A user on instance A creates a Collection of sources and shares a URL. A user on instance B pastes the URL, previews the collection, and subscribes. B polls A's paginated JSON manifest and imports items (with `content_text` + tags) without ever touching the original sources. A acts as a relay; B's followers save bandwidth and get content from sources they couldn't poll themselves.

This pulls two features forward from the AGENTS.md roadmap:
- **Collections** (was v3) — built now, with explicit source list membership (no `tag_filter` in v1).
- **Cross-instance pull** (was v4) — built now, as a relay via paginated JSON manifest.

RSS/Atom export (was v3.5) is built alongside the manifest at a sibling URL, so non-Stray RSS readers can subscribe to a Collection's item stream too.

## Non-goals (deferred)

- `public` Collection visibility (only `unlisted` + `private` implemented).
- Token revocation / per-recipient share tokens.
- Item deletions propagating from A to B (B keeps items A removed).
- OPML export (JSON manifest is a strict superset; RSS/Atom covers non-Stray interop).
- Cross-instance authentication handshake (unlisted URL is the secret).
- `tag_filter` on Collection (explicit source list only for v1; can add later without breaking the manifest format).
- `creator_identity` in the manifest (deferred to manifest v2).

## Architecture

Two roles, one `Collection` model:

- **Producer (instance A):** Creates a `Collection`, adds sources to it via `CollectionMembership`, gets a shareable URL. The URL serves a paginated JSON manifest AND an RSS/Atom feed at sibling paths.
- **Consumer (instance B):** Pastes the manifest URL into an "Add remote collection" form. B creates a single `Source` (kind `:stray_collection`) pointing at the manifest, a `Follow`, and a `RemoteCollection` record tracking sync state. The existing `SourcePollJob` polls the manifest via a new `RemoteCollectionExtractor` and upserts items — exactly the path used for RSS/YouTube today.

**Key reuse:** The relay is *just another extractor.* `SourcePollJob#extract_and_persist` already calls `ExtractorRegistry.find_for_source(source)` and upserts the returned `ExtractedContent` structs. The new `RemoteCollectionExtractor` returns those same structs; the existing upsert path handles dedup (`external_id` + `source_id`), tag application, embeddings, and thumbnails. No changes to `SourcePollJob` for the common path — only pagination handling added.

## Data model

### Producer side (instance A)

**`collections` table**
- `id`, `user_id` (FK → users), `name` (presence), `description` (nullable), `visibility` (enum: `unlisted`=0 default; `private`=1; `public`=2 reserved, not built), `slug` (long random token, for URL), `created_at`, `updated_at`.
- Only `unlisted` is implemented now. `private` = owner-only (collection exists but no share URL served). `public` reserved, not built.
- Unique index on `[user_id, slug]`.
- Slug is a long random token (`has_secure_token :slug, length: 24`), not a human-readable string — the slug is the secret that gates unlisted access.

**`collection_memberships` table**
- `id`, `collection_id` (FK → collections), `source_id` (FK → sources), `created_at`, `updated_at`.
- Unique on `[collection_id, source_id]`. Explicit source list (as decided). No `tag_filter` column — kept out for v1 simplicity; can add later without breaking the manifest format (consumers ignore unknown fields).

### Consumer side (instance B)

**`sources` table — add enum value**
- `Source.kind` gains `:stray_collection` (=4). No other column changes; `url` holds the manifest URL.

**`remote_collections` table** (consumer-side sync state, 1:1 with a `Source`)
- `id`, `source_id` (unique FK → sources), `user_id` (FK → users), `manifest_url`, `producer_instance_name` (display, from manifest metadata), `collection_name` (snapshot), `last_cursor` (opaque string from manifest pagination, nullable), `last_synced_at`, `last_error`, `last_error_at`, `item_count` (cached), `created_at`, `updated_at`.
- `source_id` unique ensures one `RemoteCollection` per `Source`.
- Uniqueness on `[user_id, manifest_url]` (normalised) to prevent subscribing to the same collection twice.

### No changes to existing models
- `Item`, `Tag`, `Tagging`, `Follow` unchanged. Relay items are just `Item`s under the `stray_collection` `Source`. Tags come through `ExtractedContent.tags` → existing `SourcePollJob#apply_extractor_tags`. `Follow` created on import as usual.

### Why `remote_collections` is a separate table (not columns on `Source`)
Sync state (cursor, `last_synced_at`, error, `item_count`) is conceptually distinct from source identity (`url`, `kind`, `name`). Keeping `Source` clean for non-relay kinds avoids nullable columns that only apply to one `kind`, and avoids branching in `Source`-related code that doesn't care about relay vs. RSS.

## JSON manifest format (v1)

### Endpoints on instance A (unauthenticated, unlisted)

All keyed by `slug`, not `id`, so URLs are shareable and don't leak row counts:
- `GET /c/:slug/manifest.json` → JSON manifest (paginated)
- `GET /c/:slug/feed.xml` → RSS/Atom feed (latest ~50 items, for RSS readers)
- `GET /c/:slug` → HTML preview page (for humans clicking the link in chat/email before pasting into Stray)

All return 404 if collection is `private`. `unlisted` serves to anyone with the URL. No auth, no token.

### Manifest JSON structure

```json
{
  "format": "stray-collection",
  "version": 1,
  "collection": {
    "name": "Economics Blogs",
    "description": "Curated econ feeds",
    "slug": "a1b2c3d4e5f6...",
    "item_count": 142
  },
  "producer": {
    "instance_name": "Alice's Stray",
    "instance_domain": "stray.alice.example",
    "stray_version": "0.1.0"
  },
  "sources": [
    { "url": "https://feeds.example.com/econ1", "kind": "rss_feed", "name": "Econ Blog A", "icon_url": null }
  ],
  "items": [
    {
      "external_id": "abc123",
      "title": "Why interest rates matter",
      "url": "https://econblog.com/post/1",
      "content_text": "...",
      "content_html": "...",
      "thumbnail_url": "https://...",
      "published_at": "2026-08-15T10:00:00Z",
      "duration": null,
      "tags": ["economics", "monetary-policy"]
    }
  ],
  "pagination": {
    "next_cursor": "eyJ0IjoxMDB9",
    "next_url": "https://stray.alice.example/c/economics-blogs/manifest.json?cursor=eyJ0IjoxMDB9",
    "has_more": true
  }
}
```

### Pagination design

- **Cursor-based**, opaque to B. A encodes the offset/last-external-id in a base64 of a small JSON like `{"offset":100}`. B treats the cursor as opaque and just appends `?cursor=` on the next fetch.
- **Page size:** 100 items per page (configurable via `AppConfig` later; hardcoded constant for v1).
- **Order:** `published_at DESC` across all items in the collection (union of member sources' items).
- B's sync job fetches pages until `has_more: false`, then stops. Next sync re-fetches from page 1 (cursor `null`) and walks forward until it hits items it already has (by `external_id`), then stops early — this catches items A re-published and avoids re-walking the whole history every time.

### Versioning

- `version: 1`. If v2 adds fields (e.g. item snapshots with embeddings, `creator_identity`), B ignores unknown fields and still works. B logs a warning if `version` is higher than it understands but still attempts parse.

### What's NOT in the manifest (v1)

- Embeddings (B re-embeds with its own model — embeddings are local-model-specific and wouldn't transfer anyway).
- `creator_identity` (deferred to v2).
- Item state (saved/hidden) — that's A's private state, never shared.
- `summary` (LLM-generated, private to A).

### Content sharing scope

`content_text` is shared in full (the extracted readable text, what FTS5 indexes and the reader view shows). This is the relay's value — B can search and read items without re-scraping the origin. The line against AGENTS.md's "full page/transcript content stays private by default": `content_text` is the readable extraction (summary-equivalent metadata), not the raw page HTML or full video transcript. `summary` (A's LLM output) and `embedding` (model-specific) stay private.

## Consumer-side extractor & sync flow

### `Stray::Extractors::RemoteCollection`

New extractor in `lib/stray/extractors/remote_collection.rb`, registered in `config/initializers/extractors.rb`:

```ruby
def self.handles_kind?(kind) = kind == "stray_collection"
def self.matches?(url) = url =~ %r{/c/[^/]+/manifest\.json\z}
```

**`extract_feed(url)`** — fetches `url` (which already contains `?cursor=` for pages > 1), parses JSON, maps each `items[]` entry to a `Stray::ExtractedContent` struct, populating `tags` from the manifest's `tags` array. Returns a `Stray::Extractor::FeedResult` carrying `items`, `next_cursor`, and `has_more`.

### `Stray::Extractor::FeedResult` (new Data struct)

```ruby
Stray::Extractor::FeedResult = Data.define(:items, :next_cursor, :has_more)
```

`SourcePollJob` checks if the return value is a `FeedResult`; if so it acts on pagination. Existing extractors returning plain arrays still work (treat as `has_more: false`). Backwards-compatible — no breaking change to `RssAtomExtractor`/`YoutubeRss`/`YtDlp`.

Rejected alternative: storing cursor/`has_more` on the `Source` or `RemoteCollection` row inside the extractor. Couples extraction to persistence, against the extractor-as-plugin principle.

### Sync flow (`SourcePollJob` changes)

Minimal additions to `app/jobs/source_poll_job.rb`:
1. After `extract_and_persist`, if the extractor returned a `FeedResult` with `has_more: true`, enqueue `SourcePollJob.perform_later(source.id, result.next_cursor)` — a new optional second argument (default `nil`).
2. The `url` passed to `extract_feed` becomes `source.url + (cursor ? "?cursor=#{cursor}" : "")`.
3. After a full sync (page with `has_more: false`), update `RemoteCollection.last_cursor = nil` (or the final cursor), `last_synced_at = Time.current`, `item_count = source.items.count`.
4. Early-stop optimization: track which `external_id`s were already present in this sync run; if a page contains *only* previously-seen `external_id`s, stop fetching further pages (the rest are older). This is in `upsert_items` via a `seen_external_ids` set threaded through the pagination loop.

### `RemoteCollectionSyncJob` vs. reusing `SourcePollJob`

Reusing `SourcePollJob` with the cursor argument. It already handles polling state, broadcasts, domain mutex (relay skips the mutex — no shared origin domain), `recalculate_next_crawl!`, error tracking. A separate job would duplicate this. The only relay-specific concern is updating the `RemoteCollection` row, which the poll job can do via `source.remote_collection` (1:1 association) without branching heavily.

### Adaptive polling for relay sources

`Source#recalculate_next_crawl!` already adapts based on `items.published_at`. Relay sources get the same treatment — their items come from the manifest, and the interval adapts to A's publishing cadence. No special-casing needed, but cap the relay poll interval at 15 minutes minimum (A's manifest shouldn't be hammered every 30s). Configurable constant for v1.

## Controllers & UI

### Producer side (instance A)

**`CollectionsController`** (`app/controllers/collections_controller.rb`)
- Standard CRUD: `index`, `new`, `create`, `show`, `edit`, `update`, `destroy`. All scoped to `current_user.collections`.
- `show` renders a management view: member sources list, share URL section, item count, RSS URL.

**Routes:**
```ruby
resources :collections
get "c/:slug", to: "collections#public_show", as: :public_collection       # HTML preview
get "c/:slug/manifest.json", to: "collections#manifest", as: :collection_manifest  # JSON
get "c/:slug/feed.xml", to: "collections#feed", as: :collection_feed       # RSS/Atom
```
`public_show`/`manifest`/`feed` find by `slug` (not `id`), return 404 if `private`. No auth check on these three. The `CollectionsController` CRUD actions require auth as usual.

**UI surface:**
- Collections list in the existing sidebar/nav (`app/views/sources/_sidebar.html.erb` or a new `_collections.html.erb`), alongside Sources and Tags.
- New `app/views/collections/` directory: `index`, `show`, `new`, `edit`, `_form`, `_collection`, `_member`.
- On the Collection `show` page: a "Share" panel with two copy-buttons: manifest URL and RSS URL. Uses the existing pattern from `sources/show.html.erb` (action links, phosphor icons). Share icon = `phosphor_icon "share-network"`.
- "Add source to collection" — a multi-select from the user's followed sources on the collection edit page. Reuses the tag-search typeahead pattern (`tags#search`) if source list is long, or a simple checkbox list if short (likely fine for v1 single-user scale).

### Consumer side (instance B)

**`RemoteCollectionsController`** (`app/controllers/remote_collections_controller.rb`)
- `new` — renders a form with a single `manifest_url` field.
- `create` — fetches the manifest (first page only), builds a preview: collection name, producer instance, source list, item count. Does NOT create records yet. Renders a `preview` view with a "Subscribe" button carrying the `manifest_url` in a hidden field.
- `subscribe` (POST) — creates the `Source` (kind `:stray_collection`, url = `manifest_url`), `Follow`, `RemoteCollection`, kicks off `SourcePollJob.perform_later(source.id)`. Redirects to the Source's `show` page, which reuses the existing `sources/show.html.erb` template — no new item view needed. The polling indicator, item list, and date filters all work unchanged.
- `destroy` — deletes the `Source` (cascades to items via existing `dependent: :destroy`) and `RemoteCollection` (cascades or explicit). This is the "unsubscribe" action. Reuses `SourcesController#destroy`'s pattern.

**Routes (consumer):**
```ruby
resource :remote_collection, only: [:new, :create, :destroy] do
  post :subscribe
end
```
Placed under the main `resources`, not nested.

**UI surface:**
- A new "Subscribe to remote collection" entry point — on the Sources index page (`app/views/sources/index.html.erb`), next to "Add source", using `phosphor_icon "cloud-arrow-down"`. Links to `new_remote_collection_path`.
- The preview page (`app/views/remote_collections/preview.html.erb`) shows: collection name, producer instance name, source count, latest item titles (first ~5 from the first manifest page), and a "Subscribe" button.

### No changes to existing controllers
- `FeedController`, `ItemsController`, `SourcesController`, `TagsController` unchanged. Relay items appear in the feed, are taggable/filterable, and show up under their `stray_collection` `Source` exactly like any other source's items.

### Authorisation
- Producer CRUD: `current_user` only (existing `Authentication` concern).
- Manifest/feed/public_show: no auth, gated only by `unlisted` visibility (URL is the secret).
- Consumer side: `current_user` only, as with all existing controllers.

## Tag relay

Items' `tags` array flows through `ExtractedContent.tags` → existing `SourcePollJob#apply_extractor_tags` (source_poll_job.rb:99) → `Tag`/`Tagging` on B → filterable in `FeedController#index` (feed_controller.rb:14) via the existing `?tag=` param. No new filter code needed.

## Testing strategy

Minitest + fixtures + VCR (existing convention). The existing `SourcePollJobTest` mocks `ExtractorRegistry.find_for_source` and stubs `extract_feed` returning arrays. The `FeedResult` struct change is backwards-compatible with this (arrays still work).

**Unit (model tests):**
- `test/models/collection_test.rb` — name presence, slug uniqueness per user, visibility enum
- `test/models/collection_membership_test.rb` — uniqueness on `[collection_id, source_id]`
- `test/models/remote_collection_test.rb` — 1:1 with source, required fields, uniqueness on `[user_id, manifest_url]`
- `test/models/source_test.rb` (extend) — `:stray_collection` enum value, `has_one :remote_collection`

**Unit (extractor):**
- `test/lib/stray/extractors/remote_collection_test.rb` — `handles_kind?`, `matches?`, `extract_feed` parses a fixture manifest JSON and returns `FeedResult` with correct `items`/`next_cursor`/`has_more`; tags are populated on each `ExtractedContent`. VCR cassettes with sample manifest JSON.

**Job (extend `source_poll_job_test.rb`):**
- New test: extractor returns `FeedResult` with `has_more: true` → job enqueues next `SourcePollJob` with cursor arg; `has_more: false` → no further enqueue, `RemoteCollection.last_synced_at` updated, `last_cursor` set.
- New test: early-stop — all items on a page already exist → job stops fetching further pages.
- New test: relay source skips `DomainMutex` (or uses a per-manifest-host mutex, not origin).

**Controller:**
- `test/controllers/collections_controller_test.rb` — CRUD auth (owner-only), 404 on other users' collections, `manifest`/`feed`/`public_show` serve unauthenticated, `private` returns 404 on public routes.
- `test/controllers/remote_collections_controller_test.rb` — `new`/`create`/`subscribe`/`destroy` with auth; `create` fetches manifest (VCR), `subscribe` creates Source+Follow+RemoteCollection and enqueues `SourcePollJob`.

**Integration:**
- `test/integration/collection_sync_flow_test.rb` (new) — End-to-end: A creates collection, adds sources, exports manifest; B's `RemoteCollectionsController#create` fetches it (VCR cassette against a local manifest), `subscribe` creates records, `SourcePollJob` runs, items appear in B's feed, tags filterable via `?tag=`.

**System (optional for v1):**
- `test/system/collections_test.rb` — Create collection, add sources, copy share URL.
- `test/system/remote_collections_test.rb` — Paste manifest URL, see preview, subscribe, see items in feed.

## Security

### Producer-side
- **Manifest content privacy:** Only `content_text`/`content_html`/`thumbnail_url`/`tags`/`url`/`title`/`published_at`/`external_id`/`duration` are shared. No `summary` (LLM, private), no `state`/`Interaction` data, no `embedding` (model-specific).
- **Unlisted is the only access control** — slug is a secret. No auth handshake. Document this clearly in the UI ("Anyone with this link can view"). Slug entropy: long random token (`has_secure_token :slug, length: 24`).
- **Rate limiting:** Manifest/feed endpoints should be rate-limited to avoid abuse. Use Rails `config.cache_store`-backed rate limiter or a simple IP-based limiter in a `before_action`. Defer to implementation plan.

### Consumer-side
- **SSRF protection:** B fetches an arbitrary URL the user pastes. Risk: a malicious user points Stray at an internal address (`http://localhost:6379`, `http://169.254.169.254` AWS metadata, etc.). Mitigate by:
  - Refusing URLs whose host resolves to private/link-local/loopback IP ranges (check `Resolv.getaddresses` against `IPAddr` ranges for `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`). This is the critical SSRF guard.
  - Limiting manifest response size (reject if `Content-Length` > 5MB for v1) and following redirects cautiously (no more than 3 hops).
  - Setting a fetch timeout (10s connect, 30s read).
- **Manifest validation:** Reject if `format != "stray-collection"` or `version` not understood. Treat as `last_error` on the Source; do not crash the sync job.
- **Payload validation:** Cap items per page accepted from a remote (e.g. trust the 100/page contract but reject if a page returns >1000, defensive).
- **No auth between instances** is fine for unlisted — but document that share URLs are bearer tokens effectively.

**Brakeman:** The new controllers add `render`/redirect paths and a URL fetch. Run `bin/brakeman` after implementation. The SSRF guard is the main thing Brakeman won't catch (it's a logic bug, not a pattern it flags).

## Edge cases

1. **A deletes the collection or sets it private** — B's next sync gets 404. B's `RemoteCollection.last_error` = "Producer collection gone (404)". Source stays active so B can pause/destroy manually; no auto-unsubscribe.
2. **A removes a source from the collection** — B already has those items under the `stray_collection` Source. They stay. B doesn't re-fetch from the removed origin (it never did). No action needed.
3. **A re-publishes an item (new `published_at`, same `external_id`)** — `Item.upsert_all` with `unique_by: [:source_id, :external_id]` updates the row in place. Existing behaviour.
4. **Duplicate `external_id` across two of A's member sources** — B's Source is one row, `external_id` unique per `source_id`. First one wins, second is silently dropped by upsert. A's manifest builder should dedup across members (producer-side responsibility).
5. **B subscribes to the same collection twice** — `RemoteCollectionsController#subscribe` detects an existing `RemoteCollection` with the same `manifest_url` for that user and redirects with a notice instead of creating a duplicate. Uniqueness validation on `[user_id, manifest_url]` (normalised).
6. **Item count drift** — A's `item_count` in manifest metadata may differ from what B has (B subscribed late). Not an error; B's sync walks pages until it hits known items. Display "syncing…" until first sync completes.
7. **Producer goes offline mid-pagination** — B's sync job catches the error on page N, records `last_error`, keeps pages 1..N-1's items. Next run retries from page 1 (cursor reset on failure). No partial-state corruption because upsert is idempotent.

## Documentation update (first plan step)

AGENTS.md and README.md have outdated roadmap references that this feature invalidates:

**AGENTS.md:**
- Line 16 (Principle 6): "Shared feeds output plain RSS/Atom in v1. A Stray-specific cross-instance protocol is v4+, only after v3.5 proves the pull/export model." — update to reflect that Collections + cross-instance relay are now in-scope, RSS/Atom export is built alongside the manifest.
- Line 104: "Collection — v3 (sharing): name, visibility (private/unlisted/public), tag_filter." — update to reflect Collection is now built, v1 uses explicit source list (no `tag_filter`).
- Line 131: "Collections, sharing, RSS/Atom export → v3 / v3.5." — update to "built".
- Line 132: "Cross-instance pull → v4..." — update to "built (relay via JSON manifest); real-time federation still deferred".

**README.md:**
- Line 61, 76-77: matching text updates.

The implementation plan's first task is updating these docs so the repo reflects the new scope before code is written.

## Open decisions (for implementation plan)

- Rate limiting approach for manifest/feed endpoints (cache-backed limiter vs. `rack-attack` vs. simple `before_action`).
- Whether to extract the SSRF guard into `lib/stray/url_fetcher.rb` (reusable) or inline it in `RemoteCollectionsController` + `RemoteCollectionExtractor`.
- VCR cassette strategy for the integration test (record against a local manifest served by the test app, or a static fixture JSON file).
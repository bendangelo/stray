# Stray Source Feeds + Collection Feed Consistency — Design

**Date:** 2026-08-20
**Status:** Approved (brainstormed 2026-08-20)
**Author:** Pair session (user + assistant)
**Related:** `2026-08-16-collection-sharing-relay-design.md`

## Goal

Every `Source` exposes an RSS 2.0 feed and a Stray JSON manifest at unauthenticated, slug-gated URLs — mirroring the existing `Collection` output. Both source and collection feeds stop excluding `hidden` items, so feeds are a faithful "everything this source/collection published" stream.

This closes the asymmetry noted in AGENTS.md Principle 6: collections already interop via RSS + manifest; sources do not. A user can now subscribe to a single source in any RSS reader or relay a single source to another Stray instance, without subscribing to the source on the consumer side.

## Non-goals (deferred)

- Atom 1.0 format (no `.atom.builder` today; not adding).
- A per-feed auth token separate from the slug. The slug *is* the token.
- Feed access logging / analytics.
- A dedicated "Copy RSS URL" button UI (source edit/share view may add one later; separate spec).
- Changing `private`/`public` collection visibility behavior. `private` collections still return 404; `public` (enum value 2) still reserved.
- A source-level visibility concept. All sources are servable via their slug; the slug is opt-in (only created on demand).

## Architecture

Mirror the existing collection output path. Sources gain a 24-char `slug` (identical mechanism to `Collection#slug`), exposed at sibling routes under `/s/:slug/...`:

```
GET /s/:slug             → sources#public_show   (HTML landing, unauthenticated)
GET /s/:slug/feed.xml     → sources#feed          (RSS 2.0, unauthenticated)
GET /s/:slug/manifest.json → sources#manifest     (Stray JSON manifest v1, unauthenticated)
```

`SourcesController` adds `allow_unauthenticated_access only: %i[public_show feed manifest]`. Authenticated source management routes (`/sources/:id`, `pull`, `mute`, `unmute`) are unchanged.

Collection routes and controllers stay where they are; only the `where.not(state: :hidden)` filter is dropped in both `feed` and `manifest` actions for consistency.

## Data model change

### Schema migration (structure only)

```ruby
add_column :sources, :slug, :string, null: false
add_index :sources, :slug, unique: true
```

### Source model

```ruby
has_secure_token :slug, length: 24
validates :slug, presence: true, uniqueness: true
```

`external_id` remains the dedup key (`external_id` + `source_id`) and is **not** a credential. The new `slug` is the credential and is independent of source identity, so it can be rotated without affecting dedup.

### Data migration (backfill)

A `data_migrate` migration assigns a 24-char token to each existing `Source` row. Per AGENTS.md: schema migration for structure, data migration for the backfill. New sources get a slug automatically via `has_secure_token`.

### Slug rotation

Authenticated member route on `sources`:

```ruby
post "sources/:id/rotate_slug", to: "sources#rotate_slug", as: :rotate_source_slug
```

Action regenerates the token via `source.regenerate_token` (the `has_secure_token` helper for the named token) and saves. Old slug returns 404 on the public feed/manifest immediately. UI surface (a "Rotate link" button on the source edit/share view) is out of scope for this spec.

## Controllers

### `SourcesController`

```ruby
allow_unauthenticated_access only: %i[public_show feed manifest]

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
  source = current_user.sources.find(params[:id])
  source.regenerate_token(:slug)
  redirect_to source, notice: "Feed link rotated."
end
```

No `state` filter on `feed` or `manifest` — all item states are served (see "Feed item inclusion" below).

### `CollectionsController`

Remove `.where.not(state: :hidden)` from both `feed` (line 63) and `manifest` (delegated to `CollectionManifest`, see below). No route changes.

## Views & services

### Source RSS builder

`app/views/sources/feed.xml.builder` — near-copy of `app/views/collections/feed.xml.builder`, with:

- `xml.title @source.display_name`
- `xml.link @source.url`
- `xml.description @source.display_name`
- self-link via `request.url`
- per-item block identical to the collection builder (title, link, guid, pubDate, description, enclosure)

### Shared item payload

Extract a small shared module so the manifest item shape and the cursor logic stay identical between `CollectionManifest` and `SourceManifest`:

- `app/services/feed_item_payload.rb` — module with `payload(item)` and `tags(item)` methods, mixed into both manifest services. The item payload fields are unchanged from `CollectionManifest#item_payload` (`external_id`, `title`, `url`, `content_text`, `content_html`, `thumbnail_url`, `published_at`, `duration`, `tags`).
- `app/services/manifest_cursor.rb` — module with `decode_offset`/`encode_offset`/`next_url` (the existing cursor logic from `CollectionManifest`, lines 82–103). Parameterized by the manifest's `next_url` path.

### `SourceManifest` service

`app/services/source_manifest.rb` mirrors `CollectionManifest`:

```ruby
{
  format: "stray-source",      # distinct from "stray-collection"
  version: 1,
  source: {
    name: source.display_name,
    url: source.url,
    kind: source.kind,
    icon_url: source.icon_url,
    slug: source.slug,
    item_count: total
  },
  producer: { ... },           # identical to CollectionManifest
  items: page_items.map { ... },
  pagination: { ... }          # identical, path = /s/<slug>/manifest.json
}
```

Note: `format: "stray-source"` (not `"stray-collection"`) so a consumer can distinguish a single-source relay from a collection relay. There is no `sources:` array (it's a single source; its metadata lives under `source:`).

### `CollectionManifest` changes

Drop `.where.not(state: :hidden)` from the `items_scope` (line 22). Otherwise unchanged.

## Feed item inclusion (all states)

Both source and collection feeds now include **all item states** — `unseen`, `seen`, `saved`, and `hidden`. Rationale:

- A source feed is "everything this source published." Hiding is a personalization signal for the *homepage ranking*, not a deletion. Excluding hidden items from the source's own feed would silently drop content the user's RSS subscribers expect to see.
- A collection feed that excludes hidden while a source feed includes hidden would be inconsistent and surprising.
- A user who wants a curated "best of" feed has the saved-state option (future spec); the default is faithful-to-source.

The `state` field is not part of the manifest item payload (unchanged) — `state` is a per-user local concern and should not leak to consumers.

## Security & threat model

- **The slug is the only credential.** 24 chars from `has_secure_token` (~142 bits entropy). Same model collections already use; no new attack surface.
- **No auth headers, no cookies required.** Feeds work in any RSS reader, any HTTP client, any language. This is the AGENTS.md Principle 6 requirement: interoperability before inventing a protocol.
- **Slug leakage = feed leakage.** The realistic risk is "the URL gets shared," not "an attacker brute-forces a 24-char token." Rotation is the mitigation; one button, instant invalidation of the old URL.
- **`private` collections still return 404** (no change). **All sources are servable** via their slug. `has_secure_token` assigns a slug on every `Source` creation, so every source has a feed URL from the moment it exists — but the URL is only *discoverable* if the owner copies it from the source's share/edit view. Rotation is the mitigation if a slug leaks.
- **No access logging in v1.** Explicitly out of scope; flag for later if feed analytics become wanted.

## Testing

Mirror the existing collection feed test pattern in `test/controllers/collections_controller_test.rb` (lines 102–113, 115–119):

**Source feed tests (`test/controllers/sources_controller_test.rb`):**
- `feed` serves RSS 2.0 unauthenticated; returns 404 for unknown slug.
- `manifest` serves JSON unauthenticated; paginates with `cursor`; returns 404 for unknown slug.
- `public_show` renders unauthenticated.
- `rotate_slug` requires authentication; after rotation, the old slug 404s on `feed`/`manifest` and the new slug works.

**Collection feed tests (update existing):**
- Add a `hidden` fixture item and assert it *is* now included in the RSS body and the manifest items array. Replace any assertion that hidden items are excluded.

**Manifest service tests:**
- `SourceManifest` produces the `stray-source` format with the expected source metadata block and pagination path `/s/<slug>/manifest.json`.
- Shared `FeedItemPayload` module produces the same field set as before (regression coverage for `CollectionManifest`).

## Out of scope (recap)

- Atom 1.0 format.
- Per-feed auth token separate from slug.
- Feed access logging/analytics.
- Dedicated "Copy RSS URL" button UI.
- Collection `public` visibility support.
- Source-level visibility concept.
- Changing the manifest version number (still v1 for both `stray-collection` and `stray-source`).
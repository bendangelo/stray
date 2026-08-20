---
name: video-extraction
description: Use when adding, fixing, or extending a site extraction adapter (Rumble, Bitchute, Odysee, Peertube, or a new video site) in lib/stray/extractors. Documents the exact fields every channel and video must/may expose — duration, publish time, thumbnail, tags, views, creator — and the normalized Hash contract the core returns and HashMapper consumes.
---

# Video Channel & Video Extraction Contract

Stray's site extractors live in a gem-ready core (`lib/stray/extractors/<site>.rb`, pure Ruby, no Rails) behind thin Rails adapters (`app/services/extractors/<site>.rb`). This skill defines the **information every channel and video must and may expose**.

## File layout

```
lib/stray/extractors/<site>.rb        # core: HTTP fetch + parse → Array<Hash>/Hash
lib/stray/extractors/helpers.rb       # shared: dehumanize, find_meta, find_thumbnail, ...
lib/stray/extractors.rb               # gem entrypoint, require all cores
app/services/extractors/<site>.rb     # thin adapter: matches?/handles_kind?/extract/extract_feed
app/services/extractors/hash_mapper.rb# maps core Hash → Stray::ExtractedContent
config/initializers/extractors.rb     # register the adapter (before GenericPage)
app/services/url_classifier.rb        # route URLs → category/source_kind
app/jobs/link_intake_job.rb           # intake branches for channel_feed / single video
app/models/source.rb                  # Source.kind enum entry
```

## The core contract

The core returns a **normalized Hash** (symbol keys). `HashMapper` copies it into a `Stray::ExtractedContent`. `Stray::ExtractedContent` (defined in `lib/stray/extracted_content.rb`) is:

```ruby
ExtractedContent = Data.define(
  :url, :title, :content_text, :content_html,
  :thumbnail_url, :published_at,
  :external_id, :duration,
  :creator_identity,
  :tags
)
```

### Video hash (one item)

`channel_feed` returns `Array<Hash>`; `video_page` returns a single `Hash`.

| Key | Kind | Required | Meaning / format |
|---|---|---|---|
| `url` | String | **yes** | Canonical permalink to the video. `Item` validates presence. |
| `title` | String | **yes** | Video title. `Item` validates presence. |
| `external_id` | String | **yes** | Stable unique ID (dedup key, scoped to source). **Never** the URL hash if a real id exists. Prefer `item["id"]`/`uuid`/claim id. |
| `duration` | Integer | preferred | **Seconds** (not `"5:32"`, not minutes). Missing → item flagged `incomplete_metadata` and `MetadataEnrichmentJob` backfills. |
| `published_at` | Time | preferred | Publish timestamp, ISO8601/UTC. Missing → enrichment backfill. |
| `thumbnail_url` | String | preferred | Absolute URL. Missing → enrichment backfill. |
| `content_text` | String | optional | Plain-text description/body. **This is what FTS5 indexes.** |
| `content_html` | String | optional | HTML body for the reader view (rarely set; content_html is `nil` for most video cores). |
| `tags` | Array<String> | optional | Lowercased topic tags, max ~5. |
| `views` | Integer | optional | View count → rendered into the summary block. |
| `live` | Boolean | optional | Is a live stream. |
| `is_short` | Boolean | optional | Is a short. |
| `creator_identity` | Hash | optional | Channel the video belongs to (see below). |

### Channel identity (`creator_identity`)

Maps to `Stray::CreatorIdentity` (`lib/stray/creator_identity.rb`):

```ruby
CreatorIdentity = Data.define(:name, :url, :external_id, :thumbnail_url)
```

| Key | Kind | Required | Meaning |
|---|---|---|---|
| `name` | String | preferred | Channel display name. Used as the Source `name` when empty. |
| `url` | String | preferred | Channel permalink (e.g. `https://rumble.com/c/BrightInsight`). Used as the Source `url`/`channel_url` for single-video intake. |
| `external_id` | String | **yes** | Stable channel identifier. Becomes the Source `external_id` (dedup key). **Must be stable across videos.** |
| `thumbnail_url` | String | optional | Channel avatar. |

## Field formats (do not skip)

- **`duration` must be seconds (Integer).** Convert `"1:02:05"`, `"5m"`, `"5 minutes"` with `Helpers.dehumanize`.
- **`published_at` must be a `Time`.** Convert ISO8601 with `Time.iso8601`, or humanized strings with `Helpers.dehumanize_time`.
- **`thumbnail_url` must be absolute.** Resolve relative paths against the base host (`Helpers.absolute_url`).
- **`external_id` must be stable and unique.** If the source page exposes a real ID (`id`, `eid`, `uuid`, claim id), use it — never derive from the URL unless no other id exists.
- **Don't leave `duration`/`published_at`/`thumbnail_url` out when the site provides them.** They are "preferred" (enrichment can backfill) but capturing them at extraction is cheaper and more reliable than a later network round-trip.

## Where to find each field per site type

| Source type | title | duration | published_at | thumbnail | external_id | channel |
|---|---|---|---|---|---|---|
| Embedded JSON (`<script>`/`<rum-videos-grid>`) | `item["title"]` | `item["duration"]` (already seconds) | `item["upload_date"]` (ISO8601) | `item["thumb"]` | `item["id"]` | `item["by"]` |
| JSON-LD `VideoObject` (`<script type="application/ld+json">`) | `name` | `duration` (ISO8601 duration) | `uploadDate` | `thumbnailUrl` | `url` | `author`/`by` |
| RSS/Atom (feedjira) | `entry.title` | `entry.itunes_duration` | `entry.published` | first `<img>`/`media:thumbnail` | `entry.entry_id`/`url` | feed `title`/channel handle |
| REST API (e.g. Peertube `/api/v1/video-channels/<h>/videos`) | `name` | `duration` (seconds) | `publishedAt` | `thumbnailPath` | `uuid`/`id` | `channel` |
| OG meta (fallback) | `find_meta(doc, "og:title")` | `find_meta(doc, "duration")` → `Helpers.dehumanize` | `find_meta(doc, "uploadDate"/"datePublished")` | `find_meta(doc, "og:image")` | URL slug | `find_meta(doc, "author")` |

## Using the shared helpers

```ruby
Helpers.dehumanize("1:02:05")          # => 3725  (duration to seconds)
Helpers.dehumanize("1.2k")             # => 1200  (views)
Helpers.dehumanize_time("2023-05-22T19:01:43+00:00") # => Time
Helpers.find_meta(doc, "og:image")     # meta by name/property/itemprop
Helpers.find_thumbnail(doc)            # og:image → twitter:image → thumbnailUrl → poster
Helpers.find_publish_date(doc)         # .video-publish-date → uploadDate → datePublished → article:published_time
Helpers.find_duration(doc)             # meta "duration", humanized → seconds
Helpers.absolute_url(path, base: host) # resolve relative → absolute
```

## Writing a new site core (checklist)

1. `self.matches?(url)` — host/path predicate. Return `false` on `URI::InvalidURIError`.
2. `self.channel_slug(url)` / `self.video_id(url)` — stable identifiers from the URL.
3. `channel_feed(url)` → `Array<Hash>` of video hashes, each with a `creator_identity` whose `external_id` is the **channel** id.
4. `video_page(url)` → one video Hash (may leave some fields `nil`).
5. `fetch(url)` — raise `Stray::ExtractionError` on non-200; reuse the Faraday browser-UA pattern.
6. Populate `duration`, `published_at`, `thumbnail_url` whenever the site exposes them.
7. Register the thin adapter in `config/initializers/extractors.rb` **before** `Extractors::GenericPage`.
8. Add a `Source.kind` enum value, `UrlClassifier` branch, and `LinkIntakeJob` branch.

## Testing checklist

- Core test against a saved HTML/JSON fixture in `test/fixtures/files/` — assert `duration` is seconds, `published_at` is a `Time`, `thumbnail_url` is absolute, `external_id` is stable.
- Adapter test asserts the core Hash maps to `Stray::ExtractedContent` via `HashMapper`.
- `UrlClassifier` test for channel + video categories.
- `LinkIntakeJob` test for the channel-feed and single-video paths.
- Run `bin/rails test`, `bin/rubocop`, `bin/brakeman --no-pager`.

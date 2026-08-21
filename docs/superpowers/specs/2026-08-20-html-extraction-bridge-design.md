# Design: Bridge Abstraction & Generic HTML Extraction

Date: 2026-08-20
Status: Approved
Supersedes: Naming/dispatch conventions in `2026-08-13-extractor-design.md` (runtime rename `Extractor` → `Stray::Bridge`; the underlying architecture and job flow are unchanged)

## Purpose

Stray is a community, single-gem self-hosted content router. This design unifies and expands the extraction layer so it can support *all* sites, not just the original five. It introduces the **Bridge** abstraction (a rename and formalization of the existing Extractor system), closes the "HTML list page → many items" gap that today collapses into a single bookmark, adds per-source auth secrets for bridges that need login/API keys, and puts selector-rot alerting in place so a community-maintained fleet of bridges stays healthy.

The build order mirrors the user's priorities: **Phase A — video coverage & governance** (mostly done), **Phase B — RSS feeds** (add discovery + politeness), **Phase C — generic HTML** (list-page extractor, the real new work).

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| RSS Bridge relationship | Native Ruby bridges only; no RSS Bridge sidecar, no port of PHP bridges | Single coherent gem; community contributes to Stray directly; avoids maintaining a divergent fork of ~300 rotting parsers |
| Bridge distribution | Single gem forever; bridges bundled in repo under `app/bridges/` + `lib/stray/bridges/` | Simplest contribution path (PR to Stray); discoverable; no gem-scaffolding friction. Spec stays gem-ready in case of future extraction, but extraction is explicitly out of scope. |
| Naming | Clean rename `Extractor` → `Stray::Bridge`, `ExtractorRegistry` → `Stray::BridgeRegistry`, `Extractors::*` → `Bridges::*` | "Bridge" is the community-facing word; consistency matters for a plugin ecosystem. One-time churn across ~9 adapters + jobs + `UrlClassifier`. |
| Bridge metadata | Declared on the base class: `trust_level`, `site_homepage`, `last_tested_against`, `requires_auth`, `secret_fields`, `author`, `source_url`, `license` | Makes a community project governable: trust surfacing, rot detection, attribution. |
| Per-source secrets | New `SourceSecret` model with `encrypts`, sealed by existing `STRAY_ENCRYPTION_KEY` (same infra as `Setting.smtp_password`) | Reuses the sanctioned DB-config encryption path; keeps AGENTS.md's "no Rails.credentials / master.key" principle intact. `Setting` is a global singleton with no per-source scoping, so a new model is required. |
| `requires_auth` bridges | In scope. Bridges declare `secret_fields`; polling job hydrates them at runtime. | Many real bridges (logged-in Rumble, Patreon, private Peertube) need per-source cookies/keys. Without this, those sites are unreachable. |
| Generic HTML list vs. bookmark | New `generic_list` Source kind (enum int 9), distinct from `generic_page` (bookmark) | Clean `handles_kind?` dispatch: `generic_list` → `GenericListBridge`, `generic_page` → `GenericPage`. No runtime sniffing on every poll. `UrlClassifier` decides at intake. |
| Stable `external_id` for list items | Permalink hash (`Digest::SHA2.hexdigest(canonical_item_url)`), never array position | Re-orderings must not create dupes. Non-negotiable. |
| Explainability of `:guessed_dom` items | Visible "structurally detected, not from a known schema" marker in the "why is this here" UI; user can distrust | Principle #2. Auto-detected list items are opaque by default; the user must see the provenance. |
| Selector-rot alerting | `Source#consecutive_empty_polls` counter + `status: :degraded` (new enum value) | A bridge "succeeding" with zero new items is silent breakage. Visible rot → community maintainer action. |
| Ferrum | Out of scope (deferred) | Headless Chrome in a single-user self-host Docker is heavy; per-site JSON-API / ld+json / OG-meta covers ~95% of cases. Reserved for genuinely JS-only, no-API sites. |
| ToS/legal scope for generic HTML | Extract title/url/thumbnail/published_at only; no full-body re-hosting | Honors AGENTS.md "full page/transcript content stays private by default." Generic scraping is metadata + link, not content. |

## Architecture

The overall job flow (`LinkIntakeJob` → classify → bridge → Items; `SourcePollSweepJob` → `SourcePollJob` → bridge → upsert) is unchanged from `2026-08-13-extractor-design.md`. What changes: the adapter boundary is renamed and formalized, a new bridge and Source kind are added, and secrets/rot-alerting become first-class.

```
User adds URL → LinkIntakeJob (async)
  → classify via UrlClassifier
      known video site → its bridge (Rumble/Bitchute/Odysee/Peertube/YouTube-RSS)
      any other video  → YtDlp fallback (new: widened at registry dispatch)
      real RSS/Atom    → RssAtom
      stray_collection → RemoteCollection
      otherwise        → try GenericListBridge.detect
                          list found? → generic_list Source + GenericListBridge
                          no list?    → generic_page Source + GenericPage (bookmark)

Hourly cron → SourcePollSweepJob
  → Sources due_for_poll + stuck
  → SourcePollJob per source
      Stray::BridgeRegistry.find_for_source(source) → bridge
      (new: if video_channel kind and no dedicated bridge → YtDlp fallback)
      hydrate SourceSecret onto bridge if bridge.requires_auth?  (new)
      conditional GET: send If-None-Match / If-Modified-Since from Source  (new)
      304? skip parse, refresh last_polled_at only  (new)
      bridge.extract_feed(url) → Array[Stray::ExtractedContent] or FeedResult
      upsert_items (dedup via external_id + source_id)
      (new: track consecutive_empty_polls → status: :degraded if threshold)
      recalculate_next_crawl!
```

## §1 — The Bridge abstraction

### Base class

`Stray::Bridge` (was: `Extractor`). Single inheritance, top-level under `Stray`. The runtime interface is preserved from the current `Extractor`; metadata fields are added.

```ruby
module Stray
  class Bridge
    # --- Runtime interface (unchanged from Extractor) ---
    def self.matches?(url)        = raise NotImplementedError
    def self.handles_kind?(kind)  = false
    def extract(url)              = raise NotImplementedError
    def extract_feed(url)         = raise NotImplementedError
    def enrich_tags(url)          = nil

    # --- Bridge metadata (new) ---
    def self.trust_level          = :scraped_html          # override per bridge
    def self.site_homepage        = nil
    def self.last_tested_against  = nil                    # e.g. "2026-08" or "rumble API v3"
    def self.requires_auth?       = false
    def self.secret_fields         = []                    # e.g. [:api_key, :cookies]
    def self.author               = nil
    def self.source_url           = nil
    def self.license              = "AGPL-3.0"             # default for Stray-native bridges
  end
end
```

`trust_level` values: `:official_api`, `:hidden_rss`, `:scraped_html`, `:guessed_dom`. Surfaced in the "why is this here" per-item expandable. A `:guessed_dom` item's ranking is visibly lower-trust than an `:official_api` one.

`last_tested_against` is a free-form string (date or site API version). The `Bridge::Health` service reads it alongside recent poll results to flag stale bridges.

`secret_fields` is an array of symbols naming the per-source secrets this bridge needs (e.g. `[:cookies]`, `[:api_key]`, `[:auth_header]`). The polling job reads matching `SourceSecret` rows and hydrates them into the bridge instance before `extract_feed` is called.

### Registry

`Stray::BridgeRegistry` (was: `ExtractorRegistry`). Same two dispatch paths (`find_for(url)`, `find_for_source(source)`), same registration-order priority. One new behavior: **video fallback at dispatch** — if `find_for_source` returns nil for a `video_channel` kind, fall back to `YtDlp`. This makes "add a new video site" = "create a Source with kind `video_channel`" with zero new code for the long tail.

```ruby
module Stray
  class BridgeRegistry
    def self.find_for_source(source)
      bridge = @bridges.find { |k| k.handles_kind?(source.kind) }&.new
      return bridge if bridge
      return YtDlp.new if source.kind == "video_channel"   # new: long-tail fallback
      nil
    end
  end
end
```

### `Stray::ExtractedContent`

Unchanged struct (already has `url`, `duration`, `creator_identity`, `tags` beyond the original spec). No new fields needed for this design.

### Plugin isolation (Principle #5, for real)

Bridges live in `app/bridges/` (Rails-tier, was `app/services/extractors/`) and `lib/stray/bridges/` (pure-Ruby cores, was `lib/stray/extractors/`). Registered in `config/initializers/bridges.rb` (was `extractors.rb`). Ranking, tagging, and feed code never touch bridges — this boundary already holds and is preserved. The only addition: a `Stray::Bridge::Health` service that reads bridge metadata + poll results to mark bridges degraded, surfaced in an admin "Bridges" page (see §5).

### Rename plan

One-time, mechanical rename. Files and constants:

| From | To |
|---|---|
| `app/services/extractor.rb` | `app/bridges/stray/bridge.rb` (class `Stray::Bridge`) |
| `app/services/extractor_registry.rb` | `lib/stray/bridge_registry.rb` |
| `app/services/extractor/feed_result.rb` | `lib/stray/bridge/feed_result.rb` |
| `app/services/extractors/*.rb` | `app/bridges/*.rb` (drop `Extractors::` → `Bridges::`) |
| `lib/stray/extractors/*.rb` | `lib/stray/bridges/*.rb` |
| `config/initializers/extractors.rb` | `config/initializers/bridges.rb` |
| class `Extractor` | `class Stray::Bridge` |
| `ExtractorRegistry` | `Stray::BridgeRegistry` |
| `Extractor::FeedResult` | `Stray::Bridge::FeedResult` |
| `Source#extractor_class` | `Source#bridge_class` |
| AGENTS.md "Extractor adapter interface" section | "Bridge interface" |

Update call sites: `Source#extractor_class`, `SourcePollJob`, `LinkIntakeJob`, `UrlClassifier`, `MetadataEnrichmentJob`, all tests under `test/services/extractors/` and `test/lib/stray/extractors/`. The `extract_feed`/`extract`/`enrich_tags`/`matches?`/`handles_kind?` method names stay (community familiarity; RSS Bridge uses similar verbs).

## §2 — Phase A: Video (coverage & governance)

Video extraction is largely already solved. This phase is small.

1. **Coverage audit.** Audit sources the user follows that aren't one of Rumble/Bitchute/Odysee/Peertube/YouTube. For each, prefer order: native/hidden RSS → site JSON API / ld+json → yt-dlp fallback. Add a dedicated bridge only if yt-dlp can't handle it (rare).
2. **Retrofit bridge metadata** onto the existing 6 video adapters (`Rumble`, `Bitchute`, `Odysee`, `Peertube`, `YoutubeRss`, `YtDlp`). Their trust levels: `Rumble`/`Bitchute`/`Peertube` → `:scraped_html` (ld+json/API), `Odysee` → `:hidden_rss` (LBRY RSS), `YoutubeRss` → `:hidden_rss`, `YtDlp` → `:official_api` (yt-dlp as the de facto API).
3. **Widen yt-dlp fallback** at the registry dispatch layer (see §1). `YtDlp#matches?` stays narrow (Bitchute); the fallback happens in `BridgeRegistry.find_for_source` for any `video_channel` kind with no dedicated bridge.
4. **Honest `external_id` audit.** Verify each video bridge uses the site's stable video ID, never the URL path or array index. `HashMapper` already does this for Rumble/Bitchute/Odysee/Peertube; a quick test pass confirms.

No new architecture in this phase.

## §3 — Phase B: RSS (discovery + politeness)

`RssAtom` already does one-item-per-entry correctly. Three additions:

### 3.1 Auto feed-discovery

New `Stray::FeedDiscovery` service: given a site homepage URL, fetch it (via `PoliteCrawl`), parse `<link rel="alternate" type="application/rss+xml" href="...">` and `<link rel="alternate" type="application/atom+xml" href="...">` via Nokogiri. If found, the `LinkIntakeJob` uses the discovered feed URL (not the homepage) when creating the `Source`. If multiple feeds are linked, prefer the first `application/rss+xml` or `application/atom+xml` and surface alternatives to the user.

Pure Nokogiri. Cheap, high-value — closes the "I gave you the homepage, not the feed URL" gap.

### 3.2 Conditional GET

Add `ETag` / `If-Modified-Since` handling to `PoliteCrawl` (not per-bridge). Store response `ETag` and `Last-Modified` headers on the `Source` (two new nullable columns: `etag :string`, `last_modified :string`). On subsequent polls, send `If-None-Match` and `If-Modified-Since`. On 304, skip parsing entirely, refresh `last_polled_at`, recalculate `next_crawl_at`, done.

This is a **prerequisite** for the generic-HTML phase, not a nice-to-have. Without it, scraping many list pages on an interval is wasteful and gets Stray IP-banned on small sites.

### 3.3 Uniform `UrlGuard`

Currently `GenericPage` and `RemoteCollection` call `UrlGuard.allowed?`; `RssAtom`, `YoutubeRss`, `Rumble`, `Bitchute`, `Odysee`, `Peertube` do not. Close this gap by moving the `UrlGuard.allowed?` check into `PoliteCrawl` itself, so every bridge is SSRF-protected by default, not per-bridge opt-in. Remove the per-bridge `UrlGuard` calls (no double-check).

## §4 — Phase C: Generic HTML (the real new work)

### 4a — The bookmark path (already works)

`GenericPage` (becomes `Bridges::GenericPage`) already produces one `Stray::ExtractedContent` per page via `ruby-readability` + OG/meta tags. For a page with no list, this is the bookmark. **No change** except the rename and bridge metadata (`trust_level: :scraped_html`).

### 4b — The new `GenericListBridge`

A bridge that decomposes an HTML page into many items. This is the missing architectural piece. Detection order, each step more brittle than the last:

1. **JSON-LD `ItemList` / `BreadcrumbList`** — schema.org structured data embedded in `<script type="application/ld+json">`. Highest trust among the auto paths. Many e-commerce and news sites emit this. Each `ListItem` → one `Stray::ExtractedContent` with `url`, `name` (→ title), `image` (→ thumbnail), `datePublished` (→ published_at). `trust_level: :scraped_html` but structured.
2. **Repeating-element detection** — find the most-repeated sibling structure in the DOM (e.g. `<article>`, `<li class="post">`) and treat each instance as an item. Heuristic. `trust_level: :guessed_dom`. This is the explainability danger zone — every item gets a visible "structurally detected, not from a known schema" marker so the user can distrust it. Algorithm: group sibling elements by tag+class signature, pick the signature with the highest count above a minimum (e.g. ≥3), extract per-item title (first heading), url (first `<a href>`), thumbnail (first `<img src>`), published_at (`<time datetime>` if present).
3. **Per-site specialized extractors** — for high-traffic sites where precision matters (a Rumble channel without API, a blog index with a known selector), write a dedicated bridge that returns `:scraped_html` with confidence. This is where community bridges earn their keep. Each ships with `last_tested_against` so rot is visible.

### 4c — `generic_list` Source kind

Add `generic_list: 9` to the `Source.kind` enum (current max is `peertube_channel: 8`). `generic_page` stays the bookmark path. `UrlClassifier` decides at intake:

```
known video site → video kind
real RSS/Atom    → rss_feed
stray_collection → stray_collection
otherwise        → fetch page, run GenericListBridge.detect
                    list found (≥3 items)? → generic_list Source + GenericListBridge
                    no list?                → generic_page Source + GenericPage (bookmark)
```

`GenericListBridge` exposes a class method `detect(url)` returning a count or nil, used by `UrlClassifier` at intake without creating items. The Source is created with the decided kind; subsequent polls dispatch to the right bridge via `handles_kind?` with no runtime sniffing.

`GenericListBridge#handles_kind?` → true for `generic_list`. `GenericPage#handles_kind?` → true for `generic_page` (unchanged).

### 4d — Stable `external_id` rule

Non-negotiable: the item's permalink hash, never array position. Use `Digest::SHA2.hexdigest(canonical_item_url)` when no native ID exists. If a list reorders, items must not dup. This rule applies to `GenericListBridge` and any per-site specialized list bridge. Video bridges already comply (they use site video IDs).

### 4e — `SourceSecret` model (per-source auth)

New model for bridges with `requires_auth: true`. Reuses the existing `encrypts` + `STRAY_ENCRYPTION_KEY` infrastructure (same as `Setting.smtp_password` / `Setting.ai_provider_api_key`).

```ruby
class SourceSecret < ApplicationRecord
  belongs_to :source
  encrypts :value            # Rails ActiveRecord Encryption, sealed by STRAY_ENCRYPTION_KEY

  validates :source_id, :field_name, presence: true
  validates :field_name, inclusion: { in: ->(secret) { secret.source&.bridge_class&.secret_fields || [] } }
end
```

Schema: `id`, `source_id` (fk, indexed), `field_name` (string, e.g. `"cookies"`, `"api_key"`, `"auth_header"`), `value` (text, encrypted), timestamps. Unique index on `[source_id, field_name]`.

Bridges declare `secret_fields` (e.g. `[:cookies]`). The polling job, before calling `extract_feed`, reads matching `SourceSecret` rows and hydrates them onto the bridge instance:

```ruby
# in SourcePollJob, after resolving the bridge:
if bridge.class.requires_auth?
  bridge.secrets = source.secrets.index_by(&:field_name)  # Hash { "cookies" => SourceSecret }
end
contents = bridge.extract_feed(source.url)
```

Bridges access secrets via `secrets[:cookies]&.value` (decrypted transparently by `encrypts`). If a `requires_auth?` bridge has no matching `SourceSecret` rows, the poll fails fast with a clear error ("bridge requires `cookies` secret; none configured") and sets `status: :failed` with a user-actionable `last_error`.

This keeps AGENTS.md's "no Rails.credentials / master.key" principle intact — secrets live in the encrypted DB column, sealed by the env-supplied key, exactly like `Setting.smtp_password` already does. The principle was about app config; per-source secrets are user data.

### 4f — ToS scope

`GenericListBridge` extracts title/url/thumbnail/published_at only. It does **not** re-host full body `content_html` — that stays the per-item reader-view fetch, honor AGENTS.md "full page/transcript content stays private by default." Generic scraping is metadata + link, not content.

## §5 — Governance & blind spots

### 5.1 Selector-rot alerting

Without this, a bridge silently "succeeds" with zero new items when selectors break.

- Add `consecutive_empty_polls :integer, default: 0` to `Source`.
- In `SourcePollJob#upsert_items`: if zero new items are created on a poll (all `external_id`s already existed), increment `consecutive_empty_polls`. If any new item is created, reset to 0.
- Add `degraded: 3` to the `Source.status` enum (was `{ pending: 0, ok: 1, failed: 2 }` → `{ pending: 0, ok: 1, failed: 2, degraded: 3 }`). When `consecutive_empty_polls` reaches a threshold (3), set `status: :degraded`.
- `degraded` is distinct from `failed` — the bridge ran without error, it just found nothing. The source stays active and keeps polling (selectors might come back; the site might genuinely have no new items), but is visibly flagged.
- Admin "Bridges" page shows degraded bridges + their `last_tested_against` date, so a community maintainer sees "Rumble bridge hasn't produced items since June, selectors likely drifted."

### 5.2 Per-domain rate budget

`DomainMutex` serializes fetches per domain but doesn't cap aggregate rate across many Sources sharing a host. Add a token-bucket per domain on top of the mutex before Phase C scales up. Implementation: a lightweight in-memory (Solid Cache-backed) token bucket keyed by domain, refilled at a configurable rate (e.g. 6 requests/minute/domain), checked in `PoliteCrawl` before issuing the GET. Prevents Stray from hammering a small site across many Sources.

### 5.3 Conditional GET

(See §3.2.) Prerequisite for generic HTML at scale. Ship with Phase B.

### 5.4 Uniform `UrlGuard`

(See §3.3.) Close before generic HTML widens attack surface. Ship with Phase B.

### 5.5 Explainability of `:guessed_dom`

(See §4b step 2.) Visible trust marker in the "why is this here" UI. User can distrust `:guessed_dom` items. Principle #2 compliance.

### 5.6 ToS/legal

(See §4f.) Generic HTML scraping stays metadata + link, not full-body re-hosting.

### 5.7 `docs/PLAN.md` reference

AGENTS.md references `docs/PLAN.md` ("Full product roadmap lives in `docs/PLAN.md`") but the file does not exist. Minor — create it or remove the reference so contributors aren't misled. Not a blocker for this design.

## Out of scope

- **Ferrum** (headless Chrome) — deferred. Per-site JSON-API / ld+json / OG-meta covers ~95% of cases. Reserved for genuinely JS-only, no-API sites.
- **RSS Bridge sidecar** — rejected. Native Ruby bridges only; no PHP dependency, no upstream divergence.
- **Multi-gem distribution** — rejected. Single gem forever. Bridges bundled in repo.
- **Public collection visibility, per-recipient share tokens, item-deletion propagation** — later (per AGENTS.md).
- **Real-time federation (ActivityPub or bespoke)** — later. v1 relay model (poll a JSON manifest) validates first.
- **`sqlite-vec` migration** — only when brute-force cosine is a real bottleneck.
- **Implicit behavioral tracking** — not in v1 or v2 (per AGENTS.md).

## Build order

1. **§1 Bridge rename + metadata** — mechanical rename across the codebase, add metadata to base class, retrofit onto 6 video adapters. Unblock the rest.
2. **§2 Phase A (video)** — coverage audit, widen yt-dlp fallback, `external_id` audit. Small.
3. **§3 Phase B (RSS)** — `FeedDiscovery`, conditional GET on `PoliteCrawl` + `Source` columns, uniform `UrlGuard`. Prerequisite for §4.
4. **§4 Phase C (generic HTML)** — `GenericListBridge`, `generic_list` kind, `SourceSecret`, `UrlClassifier` intake routing. The bulk of new work.
5. **§5 Governance** — `consecutive_empty_polls` + `degraded` status, admin Bridges page, per-domain rate budget. Ship alongside §4.
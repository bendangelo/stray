# Design: Background Job Extractor for Stray

Date: 2026-08-13
Status: Approved

## Purpose

Stray is a personal content router. This design covers the extraction pipeline: how a user adds a URL, how Stray classifies it, fetches content, resolves creators into followable sources, polls them for new content, and surfaces items on the homepage. The scope spans models, extractors, background jobs, and UI, decomposed into five phases.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| User-scoping | `user_id` on Source/Item/Follow/Tag from v1 | Avoids painful v3 migration. AGENTS.md updated. |
| YouTube polling | RSS fast-path (`youtube.com/feeds/videos.xml?channel_id=UC...`) | Free, no API key, no quota, no subprocess, no anti-bot risk |
| All video sites | yt-dlp subprocess (`--dump-json`, `--flat-playlist`) | 1000+ site extractors maintained by community; zero per-site scraping code |
| Add-link detection | Async (`LinkIntakeJob` + Turbo Stream broadcast) | Nothing blocks in request cycle; user sees "checking..." state |
| Video page → follow | Auto-resolve channel from metadata, auto-follow | One step; single video item still created |
| Polling | Cadence-predicted `next_crawl_at`, hourly sweep, auto-pause dead sources | Ported from stray_video; accurate, self-tuning |
| Gems | faraday (+ follow_redirects, retry), nokogiri, feedjira | faraday for HTTP with retries/redirects; nokogiri for HTML; feedjira for RSS/Atom |
| Architecture | Extractor registry per AGENTS.md | Plugins don't touch ranking/feed code; proven in stray_video |
| Phase 1 scope | Models + extractors + yt-dlp runner + Dockerfile + tests only | Cleanest isolation; verifiable via console/rake |
| yt-dlp wrapper | Start in `lib/stray/yt_dlp/`, extract to gem once API stabilizes | Avoid premature gem overhead; pure Ruby, no Rails deps |

## Architecture

```
User adds URL → LinkIntakeJob (async)
  → classify URL via Stray::ExtractorRegistry.find_for(url)
  → extract via matched extractor
      YouTube channel RSS → YoutubeRss (Faraday + Feedjira)
      YouTube video page  → YtDlp --dump-json (gets channel_id) → then YoutubeRss for polling
      Any other video URL → YtDlp --dump-json or --flat-playlist
  → resolve creator_identity → create/refresh Source (channel) + auto-Follow
  → create Items (videos) with dedup (external_id + source_id)
  → broadcast via Turbo Stream: "Following X — N new videos"

Hourly cron → SourcePollSweepJob
  → finds Sources where next_crawl_at <= now AND active = true
  → enqueues SourcePollJob per source
  → SourcePollJob dispatches to registered extractor:
      YouTube channel → YoutubeRss (RSS fetch, fast path)
      Other video site → YtDlp --flat-playlist (channel listings)
  → new Items created (upsert_all, dedup-safe)
  → source.recalculate_next_crawl! (cadence prediction)
  → source.update(last_polled_at: now)

Homepage (logged-in) → FeedController#index
  → Items from followed Sources, reverse-chronological
  → FTS5 searchable via full_search gem
```

## Extractor adapter interface

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
    def self.matches?(url) = raise NotImplementedError
    def extract(url) = raise NotImplementedError
  end
end
```

`extract` returns a single `ExtractedContent` (for a video page) or an array of `ExtractedContent` (for a channel listing). `creator_identity` is nullable — present when the extractor can identify the channel/creator; used by `LinkIntakeJob` to create/refresh the channel `Source` and auto-follow.

## Extractor registry

`Stray::ExtractorRegistry` — an ordered array of extractor classes. `find_for(url)` returns the first extractor whose `matches?` returns true. Order = priority (registration order). YouTube RSS is checked first (specific), YtDlp is last (universal fallback, matches any video URL).

Registration in `config/initializers/extractors.rb`:

```ruby
Rails.application.config.to_prepare do
  Stray::ExtractorRegistry.register(Stray::Extractors::YoutubeRss)
  Stray::ExtractorRegistry.register(Stray::Extractors::YtDlp)
end
```

New site support = new extractor class + one `register` line. Ranking, tagging, and feed code never change.

## yt-dlp runner

`Stray::YtDlp::Runner` — a pure Ruby wrapper around the `yt-dlp` subprocess.

```ruby
module Stray::YtDlp
  class Runner
    def initialize(binary: "yt-dlp", timeout: 30)
      # config passed in, not read from env
    end

    def single_video(url)       # yt-dlp --dump-json → Hash
    def channel_listings(url)   # yt-dlp --flat-playlist --dump-json → [Hash]
  end

  class Error < StandardError; end
  class Timeout < Error; end
  class NotFound < Error; end
end
```

**Critical constraint: `Stray::YtDlp::Runner` must be pure Ruby with zero Rails/ActiveRecord dependencies.** Config (timeout, binary path) passed via constructor, not read from env or AppConfig. No references to Source, Item, or any Stray domain class. Tests load only the file under test, not Rails. This ensures clean extraction to a standalone MIT-licensed gem once the API stabilizes.

Subprocess via `Open3.capture3`. Parses JSON output (one JSON object per line for `--flat-playlist`). Errors wrapped in `Stray::YtDlp::Error` subclasses.

## Extractors

### Stray::Extractors::YoutubeRss

- `matches?` — true for `youtube.com/feeds/videos.xml?channel_id=UC...` URLs (RSS feed URLs, not channel page URLs)
- `extract(url)` — Faraday GET → Feedjira parse → map entries to `ExtractedContent` array
- Each entry: `external_id` = `yt:videoId`, `title` = `media:title`, `content_text` = `media:description`, `thumbnail_url` = first `media:thumbnail`, `published_at` = `published`, `duration` = nil (RSS doesn't include it)
- `creator_identity` = feed-level author (name, channel URL, channel ID)

### Stray::Extractors::YtDlp

- `matches?` — true for any video URL not already matched by YoutubeRss. Acts as the universal fallback.
- `extract(url)` — calls `Stray::YtDlp::Runner.new.single_video(url)`, maps result to `ExtractedContent`
- Maps: `title`, `description` → `content_text`, `thumbnail` → `thumbnail_url`, `upload_date` → `published_at`, `id` → `external_id`, `duration` → `duration`
- `creator_identity` from `channel`, `channel_url`, `channel_id`, `thumbnails`

### Channel listing mode (for polling non-YouTube sites)

`Stray::Extractors::YtDlp#extract_channel(source)` — calls `Runner#channel_listings(source.url)`, returns array of `ExtractedContent` (title, url, external_id only — lightweight). Full metadata fetched lazily or on a separate enrichment path if needed in future.

## Intake classification (used by Phase 2's LinkIntakeJob)

When a user pastes a URL, the classification logic determines the extractor and the flow:

1. **YouTube channel URL** (`/channel/UC...`, `/@handle`, `/c/name`, `/user/name`) → resolve to RSS feed URL (`https://www.youtube.com/feeds/videos.xml?channel_id=UC...`) → use `YoutubeRss` → creates a `Source` with `kind: youtube_channel`, polls via RSS
2. **YouTube video URL** (`watch?v=...`, `youtu.be/...`) → use `YtDlp` single-video → extract `channel_id` from metadata → create channel `Source` (with RSS poll URL) + auto-follow + create single video `Item`
3. **Any other video URL** → use `YtDlp` → extract creator → create `Source` (with `kind: video_channel`) + auto-follow + create `Item`(s)

Channel ID resolution for YouTube handles (`@name`, `/c/name`, `/user/name` → `UC...`) uses yt-dlp's `--dump-json` on a known video or the channel URL itself (yt-dlp resolves it). Alternatively, fetch the channel page and regex `"channelId":"UC..."` (stray_video's `Scrapetube.fetch_channel_id` approach) as a fallback.

## Data model

All tables in the primary database (`db/migrate/`). `user_id` on Source/Item/Follow/Tag per the updated AGENTS.md principle.

### sources

```ruby
create_table :sources do |t|
  t.references :user, null: false, foreign_key: true
  t.string :kind, null: false          # youtube_channel, video_channel, rss_feed, generic_page
  t.string :url, null: false           # poll URL (RSS feed URL or channel page URL)
  t.string :name                        # resolved channel/site name
  t.string :icon_url                    # channel avatar / site icon
  t.string :external_id                 # channel id / feed url hash — dedup key
  t.datetime :last_polled_at
  t.datetime :next_crawl_at
  t.integer :poll_interval, default: 1800  # seconds, fallback
  t.boolean :active, default: true
  t.timestamps
  t.index [:user_id, :external_id, :kind], unique: true
  t.index [:next_crawl_at, :active], where: "active = true"
end
```

- `kind` enum: `youtube_channel`, `video_channel`, `rss_feed`, `generic_page` (extensible)
- `url` is the poll URL — for YouTube, the RSS feed URL; for other video sites, the channel page URL (yt-dlp handles it)
- `external_id` + `user_id` + `kind` is the uniqueness constraint (same channel can't be added twice by the same user)
- `next_crawl_at` + `active` index supports the "due for poll" sweep query efficiently

### items

```ruby
create_table :items do |t|
  t.references :source, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.string :external_id, null: false    # video id / guid — dedup
  t.string :title, null: false
  t.string :url, null: false
  t.text :content_text                   # FTS5 indexes this
  t.text :content_html                   # reader view (nullable for video items)
  t.text :summary                        # LLM-generated, nullable
  t.string :thumbnail_url
  t.integer :duration                    # seconds, nullable
  t.datetime :published_at
  t.datetime :fetched_at
  t.binary :embedding                    # nullable, async-populated by Phase 4
  t.string :state, default: "unseen"     # unseen/seen/saved/hidden
  t.timestamps
  t.index [:source_id, :external_id], unique: true  # dedup key
  t.index [:user_id, :state, :published_at]
end
```

- `external_id` + `source_id` is the dedup key — re-polling must never create duplicates. Enforced by unique index + `upsert_all` in jobs.
- `content_text` is what `full_search` (FTS5) indexes. `content_html` is what a reader view would render (nullable for video items — the "content" is the video itself).
- `embedding` is nullable, populated asynchronously. Never assume present in request/response code.
- `state` enum drives the homepage feed filter (default: `unseen`).

### follows

```ruby
create_table :follows do |t|
  t.references :user, null: false, foreign_key: true
  t.references :source, null: false, foreign_key: true
  t.float :weight, default: 1.0
  t.timestamps
  t.index [:user_id, :source_id], unique: true
end
```

- One Follow per user per Source. `weight` adjusted by mute/boost interactions (Phase 3).
- Creating a Source via intake auto-creates a Follow.

### tags + taggings

```ruby
create_table :tags do |t|
  t.references :user, null: false, foreign_key: true
  t.string :name, null: false
  t.binary :embedding                    # nullable, for zero-shot matching
  t.timestamps
  t.index [:user_id, :name], unique: true
end

create_table :taggings do |t|
  t.references :item, null: false, foreign_key: true
  t.references :tag, null: false, foreign_key: true
  t.string :source, null: false          # ai_embedding / ai_llm / user
  t.timestamps
  t.index [:item_id, :tag_id, :source], unique: true
end
```

Tables and models created in Phase 1. Tagging logic (embedding-based, LLM-based, manual) is Phase 4. `Taggings.source` provenance is mandatory from day one.

## Models

### Source

```ruby
class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_one :follow, dependent: :destroy

  enum :kind, { youtube_channel: "youtube_channel", video_channel: "video_channel",
                rss_feed: "rss_feed", generic_page: "generic_page" }

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [:user_id, :kind] }

  scope :due_for_poll, -> { where(active: true).where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current) }

  def recalculate_next_crawl!
    # Ported from stray_video's Channel#calculate_next_video_publish_time
    recent = items.order(published_at: :desc).limit(5).pluck(:published_at).compact
    if recent.empty?
      update!(next_crawl_at: 1.hour.from_now)
    elsif recent.first < 1.year.ago
      update!(active: false)  # auto-pause dead source
    else
      intervals = recent.each_cons(2).map { |a, b| a - b }.compact
      avg = intervals.empty? ? 1.hour : intervals.sum / intervals.size
      predicted = recent.first + avg
      # Cap: 30min min, 24h max
      predicted = [predicted, Time.current + 30.minutes].max
      predicted = [predicted, Time.current + 24.hours].min
      update!(next_crawl_at: predicted)
    end
  end
end
```

### Item

```ruby
class Item < ApplicationRecord
  belongs_to :source
  belongs_to :user
  has_many :taggings, dependent: :destroy

  enum :state, { unseen: "unseen", seen: "seen", saved: "saved", hidden: "hidden" }

  validates :external_id, uniqueness: { scope: :source_id }

  # full_search integration: index content_text + title
  # (specific DSL depends on full_search gem API)
end
```

### Follow

```ruby
class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :source

  validates :source_id, uniqueness: { scope: :user_id }
end
```

### Tag, Tagging

```ruby
class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy
  validates :name, uniqueness: { scope: :user_id }
end

class Tagging < ApplicationRecord
  belongs_to :item
  belongs_to :tag
  enum :source, { ai_embedding: "ai_embedding", ai_llm: "ai_llm", user: "user" }
  validates :tag_id, uniqueness: { scope: [:item_id, :source] }
end
```

## Gems to add

```ruby
# Gemfile
gem "faraday", "~> 2.0"
gem "faraday-follow_redirects"
gem "faraday-retry"
gem "nokogiri"
gem "feedjira"
```

Faraday configured with follow_redirects + retry middleware in a shared `Stray::Http` helper or per-extractor. Nokogiri for any HTML parsing needs (Bitchute-style fallback if yt-dlp isn't used for a specific site). Feedjira for RSS/Atom parsing.

## Dockerfile change

```dockerfile
# Add Python + yt-dlp
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip && \
    pip3 install --break-system-packages yt-dlp && \
    rm -rf /var/lib/apt/lists/*
```

yt-dlp is updated periodically. Users update via `bin/update` (git pull + rebuild) or `docker compose build`. Document in README.

## AGENTS.md update

In the **Principles** section, item 1 changes from:

> Single user first. Multi-user/groups is v3, not v1. Do not add user-scoping complexity unless v3 explicitly asks for it.

To:

> Single user first. The app is built for one user to self-host and dogfood. Models carry `user_id` from v1 to avoid a painful v3 migration, but no multi-user UI, per-user isolation, or access control is built until v3. Treat the `user_id` as a forward-compatible schema decision, not an active feature.

In the **Data model** section, the model descriptions already show `user_id` — no change needed there.

## Phase 1 — Data model + extraction core

Scope: models, migrations, extractors, yt-dlp runner, Dockerfile, tests. No jobs, no UI. Verifiable via Rails console and rake tasks.

### Deliverables

1. Migrations for `sources`, `items`, `follows`, `tags`, `taggings` (primary DB)
2. Models with associations, validations, enums, scopes
3. `Source#recalculate_next_crawl!` (cadence prediction)
4. `Stray::Extractor` base class + `ExtractedContent` / `CreatorIdentity` structs (`lib/stray/extractor.rb`)
5. `Stray::ExtractorRegistry` (`lib/stray/extractor_registry.rb`)
6. `Stray::YtDlp::Runner` (`lib/stray/yt_dlp/runner.rb`) — pure Ruby, no Rails deps
7. `Stray::Extractors::YoutubeRss` (`lib/stray/extractors/youtube_rss.rb`)
8. `Stray::Extractors::YtDlp` (`lib/stray/extractors/yt_dlp.rb`)
9. `config/initializers/extractors.rb` (registry)
10. Gemfile additions (faraday, nokogiri, feedjira)
11. Dockerfile change (Python + yt-dlp)
12. AGENTS.md update (user_id principle)
13. Test suite:
    - `Stray::YtDlp::Runner` — mock `Open3.capture3` with fixture JSON, assert parsing, assert error handling
    - `Stray::Extractors::YoutubeRss` — fixture RSS XML, assert `ExtractedContent` mapping
    - `Stray::Extractors::YtDlp` — fixture `--dump-json` output, assert mapping
    - `Stray::ExtractorRegistry` — `find_for` returns correct extractor by URL
    - `Source#recalculate_next_crawl!` — given items with known intervals, asserts predicted `next_crawl_at`; dead source → `active=false`
    - Model tests: dedup (`external_id + source_id`), Follow uniqueness, state transitions

### Verification

```sh
bin/rails db:migrate
bin/rails console
  # Manually: create a Source, call recalculate_next_crawl!, verify next_crawl_at
  # Manually: Stray::ExtractorRegistry.find_for("https://youtube.com/feeds/videos.xml?channel_id=UC...")
bin/rails test
bin/rubocop
```

## Phase 2 — Background jobs + polling (preview)

- `LinkIntakeJob(user_id, url)` — classify URL, extract, resolve creator, `Source.find_or_create` + `Follow.find_or_create` + `Item.upsert_all`, broadcast Turbo Stream
- `SourcePollJob(source_id)` — dispatch to extractor, `Item.upsert_all` (dedup), `source.recalculate_next_crawl!`, `source.update(last_polled_at: now)`
- `SourcePollSweepJob` (recurring hourly) — `Source.due_for_poll.in_batches` → enqueue `SourcePollJob` per source
- `config/recurring.yml` entries
- `config/queue.yml`: add `:polling` queue with dedicated worker
- `Procfile.dev`: add `jobs: bin/jobs`
- Tests: job tests with mocked subprocess/RSS

## Phase 3 — Add-link UI + homepage feed (preview)

- `SourcesController` (new/create — paste URL, enqueue intake job, show "checking..." via Turbo Stream)
- `FeedController#index` — homepage, logged-in only, Items from followed sources reverse-chron
- `SourcesController#show` — per-creator feed view
- Item state transitions (seen/saved/hide) — minimal interactions
- Follow weight display + reset
- "Why is this here" expandable per item
- Tests: controller + system tests

## Phase 4 — Tagging + search (preview)

- Embedding job (async, populates `Item.embedding` and `Tag.embedding`)
- Zero-shot tagging job (cosine similarity against Tag embeddings)
- Optional LLM tagging via Ollama/OpenAI-compatible (async, `Taggings.source = :ai_llm`)
- FTS5 index via `full_search` (already wired in `config/initializers/full_search.rb`)
- Semantic search toggle
- Tag provenance UI (`:ai_embedding` / `:ai_llm` / `:user`)
- Manual tagging UI
- "Uncategorized" items → seed new tag embeddings

## Phase 5 — Future adapters (preview)

- `Stray::Extractors::RssAtom` (feedjira, generic RSS/Atom feeds)
- `Stray::Extractors::GenericPage` (readability-style content extraction)
- `Stray::Extractors::GithubAwesomeList` (README link list → items)
- Each: new class + one registry line. No changes to ranking/tagging/feed code.

## Future: yt-dlp gem extraction

Once the `Stray::YtDlp::Runner` API is stable (after a few weeks of dogfooding), extract to a standalone MIT-licensed gem (`yt-dlp-rb`). The pure-Ruby constraint in Phase 1 ensures this is a mechanical move:

1. Create gem repo with gemspec
2. Move `lib/stray/yt_dlp/` → gem's `lib/yt_dlp_rb/`
3. Update namespace `Stray::YtDlp` → `YtDlpRb`
4. Add gem to Stray's Gemfile
5. Update references in extractors

Stray's `Stray::Extractors::YtDlp` becomes a thin adapter mapping `YtDlpRb` output to `Stray::ExtractedContent`. Other Ruby projects (including stray_video) can adopt the gem directly.

## Open considerations

- **yt-dlp version updates**: document in README that `docker compose build` or `bin/update` pulls the latest yt-dlp. No auto-update mechanism in v1.
- **yt-dlp failure handling**: if yt-dlp returns non-zero exit, the runner raises `Stray::YtDlp::Error`. Phase 2's `LinkIntakeJob` and `SourcePollJob` catch this, mark the source/item as failed, and surface to user. Retry policy TBD in Phase 2.
- **YouTube handle → channel ID resolution**: yt-dlp resolves handles natively (`yt-dlp --dump-json "https://youtube.com/@handle"` returns `channel_id`). If yt-dlp is slow or blocked, fallback to fetching the channel page and regex-extracting `"channelId":"UC..."` (stray_video's approach). Decide during Phase 2 implementation.
- **Rate limiting per domain**: not in Phase 1. Phase 2's `SourcePollJob` should rate-limit concurrent fetches to the same domain. Solid Queue doesn't have built-in per-domain throttling; may need a simple semaphore or dedicated queues per domain bucket. Decide in Phase 2.
- **FTS5 integration specifics**: the `full_search` gem's exact DSL for declaring indexed fields needs verification during Phase 1 implementation. The initializer (`config/initializers/full_search.rb`) already sets `default_async_source_reindex = true`, so FTS reindexing happens via background jobs automatically.
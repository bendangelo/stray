# AGENTS.md — Stray

This file tells you how to work on this repo. Read the **Principles** before implementing anything. Full product roadmap lives in `docs/PLAN.md`.

## What is Stray?

A self-hosted, personal feed you control. Stray pulls content from RSS feeds, generic web pages, and followed people, and composes it into a single homepage feed that is ranked and tagged automatically — but transparently, so you can see and override exactly why anything is where it is. It is a **personal content router**, not a bookmark manager (though it does remember what you save).

## Principles (non-negotiable)

1. **Single user first.** The app is built for one user to self-host and dogfood. Models carry `user_id` from v1 to avoid a painful v3 migration, but no multi-user UI, per-user isolation, or access control is built until v3. Treat the `user_id` as a forward-compatible schema decision, not an active feature.
2. **Explainable over clever.** Every ranking decision must trace to a visible rule or similarity score. No opaque black-box behavior, ever.
3. **Works with zero AI configured.** AI (LLM tagging, semantic search) is an enhancement, never a dependency. The app must be fully usable with `STRAY_AI_PROVIDER__NAME=NONE`.
4. **One-command self-host.** `docker compose up -d` or `kamal deploy` must work from a fresh clone with only `.env` filled in.
5. **Scrape adapters are plugins, not core code.** New site support is addable without touching ranking, tagging, or feed logic.
6. **Ship interoperability before inventing a protocol.** Shared feeds output plain RSS/Atom in v1. A Stray-specific cross-instance protocol is v4+, only after v3.5 proves the pull/export model.

## Tech stack

| Layer | Choice |
|---|---|
| Framework | Rails 8, Ruby 4.0.5 (`.ruby-version`) |
| Database | SQLite |
| Background jobs | Solid Queue |
| Cache / WebSockets | Solid Cache / Solid Cable |
| Frontend | Hotwire (Turbo + Stimulus) |
| Full-text search | SQLite FTS5 via `full_search` gem |
| Vector search | Brute-force cosine in Ruby; `sqlite-vec` only if/when scale demands |
| Scraping | Ferrum (headless browser) — reserved for JS-heavy / blocked pages |
| Config | `anyway_config` → `AppConfig` (see `config/configs/app_config.rb`) |
| Testing | Minitest |
| Linting | RuboCop with `rubocop-rails-omakase` |
| Security scan | Brakeman, bundler-audit, importmap audit |
| License | AGPL-3.0 (LICENSE file pending — add before public launch) |

## Commands

```sh
bin/dev                 # dev server + tailwind watch via Procfile.dev (installs foreman)
bin/rails test          # unit/integration/controller tests
bin/rails test:system   # Capybara system tests
bin/rubocop             # lint (bin/ci uses `-f github`)
bin/brakeman --no-pager # security scan
bin/bundler-audit       # gem vuln scan
bin/importmap audit     # JS dependency vuln scan
bin/ci                  # full CI pass locally
bin/rails db:test:prepare
bin/setup-wizard        # host-only interactive setup → writes .env (never run in a container)
```

## Conventions

- Follow Omakase style (`.rubocop.yml`). Do not add comments to code unless asked.
- **Config is ENV-driven only.** Use `AppConfig` (`STRAY_*` env vars, defaults in `config/stray.yml`). Never use `Rails.credentials` or a `master.key`. `SECRET_KEY_BASE` is passed via env.
- **Icons are Phosphor via the `phosphor_icon` helper.** Never inline raw `<svg>` in ERB. Use `phosphor_icon "name", style: :regular, class: "h-5 w-5"` (weights: `regular`/`bold`/`light`/`duotone`/`fill`/`thin`). Size/color via Tailwind classes (`fill="currentColor"`). Find names at phosphoricons.com.
- **Data changes go in `db/data/` via `data_migrate`, not schema migrations.** Backfills, normalization, repairs, and one-time transformations belong in data migrations (`bin/rails g data_migration name`), run with `bin/rails data:migrate` (dev) or `bin/rails db:migrate:with_data` (deploy). Schema migrations are for structure only (`add_column`, indexes, constraints). Do not convert already-committed schema migrations that happen to touch data.
- **Extractors are plugins.** Register new adapters in `config/initializers/extractors.rb`. Ranking/tagging/feed code must never change to add a site.
- **Tagging provenance is mandatory.** Every `Tagging` stores `source` = `:ai_embedding`, `:ai_llm`, or `:user`. The UI shows it; users must be able to trust/distrust by origin.
- **Dedup key is `external_id` + `source_id`.** Re-polling a feed must never create duplicate `Item`s.
- **`embedding` is nullable and populated asynchronously** by a background job. Never assume it is present in request/response code.
- `content_text` is what FTS5 indexes; `content_html` is what the reader view renders.

## Architecture

```
[Source polling job] → fetch/scrape → [Extractor adapter] → normalize → Item created
                                                                      ↓
                                                            [Tagging job] (embedding-based, + optional LLM)
                                                                      ↓
                                                            [Embedding job] (search/ranking)
                                                                      ↓
                                                            FTS5 index updated
                                                                      ↓
                                                            Homepage feed query (ranking)
```

All steps on the right run as Solid Queue jobs. Nothing in the request/response cycle blocks on scraping, LLM calls, or embedding generation.

### Extractor adapter interface

```ruby
module Stray
  class Extractor
    def self.matches?(url) = raise NotImplementedError
    def extract(url) = raise NotImplementedError
    # extract returns a Stray::ExtractedContent struct:
    #   title, content_text, content_html, thumbnail_url, published_at,
    #   external_id, creator_identity (nullable — used for "follow this creator")
  end
end
```

v1 adapters: `GenericPageExtractor` (readability-style), `RssAtomExtractor` (`feedjira`), `YoutubeExtractor` (oEmbed/API), `GithubAwesomeListExtractor` (README link list → items).

## Data model

- **User** — email, `username`, `password_digest`.
- **Source** — `kind` enum (`rss_feed`, `generic_page`, `youtube_channel`, `github_user`, …), `url`, `name`, `icon_url`, `last_polled_at`, adaptive `poll_interval`, `active` (pause without deleting).
- **Item** — `source_id`, `external_id` (dedup), `title`, `url`, `content_text`, `content_html`, `summary` (nullable, LLM), `thumbnail_url`, `published_at`, `fetched_at`, `embedding` (nullable blob), `state` enum (`unseen`/`seen`/`saved`/`hidden`).
- **Tag** — `name`, `embedding` (nullable, for zero-shot matching).
- **Taggings** — `item_id`, `tag_id`, `source` enum (`ai_embedding`/`ai_llm`/`user`).
- **Follow** — `user_id`, `source_id`, `weight` (float, default 1.0, adjusted by mute/boost).
- **Interaction** — `item_id`, `user_id`, `kind` (`opened`/`starred`/`hidden`/`muted_source`).
- **Collection** — v3 (sharing): `name`, `visibility` (`private`/`unlisted`/`public`), `tag_filter`.

## Tagging & embeddings

Two independent techniques — do not conflate them:

- **Embedding zero-shot tagging (default, always on, no AI setup).** Embed item content with a small local model (leaning `all-MiniLM-L6-v2`, ~90MB, CPU-fast). Compare against existing `Tag` embeddings via cosine similarity; assign top-N above a threshold. Sub-threshold → "uncategorized" item the user tags manually, seeding a new tag embedding. Deterministic, no LLM.
- **Generative LLM tagging (optional upgrade).** Requires `OLLAMA` or `OPENAI_COMPATIBLE` configured. Small instruct model (e.g. `qwen2.5:1.5b`, `llama3.2:1b`). Runs async; store `Taggings.source = :ai_llm`.

The same embedding model powers semantic search (complementing FTS5) and the v2 "similar to what I save" ranking. Providers: `NONE` (default), `OLLAMA`, `OPENAI_COMPATIBLE`.

## Ranking

- **v1 only:** reverse-chronological across followed sources + per-source `Follow.weight`. Muting 3+ items from a source in a window nudges weight down; opening/starring nudges it up. Weight is visible and resettable. A muted-enough source drops from the default view but stays recoverable. Every factor must be visible in a "why is this here" per-item expandable.
- **v2 (opt-in, not default):** "similar to what I save" — average embeddings of starred/saved items into a taste vector, rank by cosine distance, show *why*.
- **Do not** implement implicit behavioral tracking (dwell time, scroll depth) in v1 or v2. A single user doesn't generate the volume, and it works against the transparent-goal.

## Self-hosting footguns

- **#1: Volumes are critical.** SQLite databases (primary/cache/queue/cable) and ActiveStorage files must be on mounted volumes in both `docker-compose` and Kamal `deploy.yml`, or redeploys wipe user data.
- Two setup wizards, don't conflate: `bin/setup-wizard` (host CLI, writes `.env`, never in a container) and the web first-run `/setup` controller (creates the first user when `User.count.zero?`).
- The app must be fully functional with `STRAY_AI_PROVIDER__NAME=NONE`. AI config is purely additive.
- Volumes note also: only metadata + the user's own notes/tags go into anything shared or exported; full page/transcript content stays private by default (legal/ToS).

## Out of scope until later

- Multi-user / per-user isolation → v3.
- `Collection`s, sharing, RSS/Atom export → v3 / v3.5.
- Cross-instance pull → v4. Real-time federation protocol (ActivityPub or bespoke) → v5, only after v4 validates the model. Do not build federation early.
- `sqlite-vec` migration → only when brute-force cosine is a real bottleneck.
- No implicit behavioral tracking in v1/v2.

## Open decisions

- Default vendored embedding model (leaning `all-MiniLM-L6-v2`).
- Whether `anyway_config` is worth keeping vs. plain `ENV.fetch` — low stakes, revisit during setup.
- Official ActivityPub stance — document in an ADR before public launch (not before v1 code).

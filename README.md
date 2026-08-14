# Stray

A self-hosted, personal feed you control.

<!-- TODO: hero screenshot / GIF -->

## Why this exists

- **Feed rot is real.** RSS feeds die, blogs go quiet, and your favorite creators scatter across platforms.
- **Algorithms you don't control.** Your feed decides what you see for reasons you can't see or change.
- **Data you don't own.** Every "save" lives on someone else's server, behind their terms.
- **No trust, no transparency.** Ranking happens in a black box.

Stray pulls content from RSS feeds, generic web pages, and followed people, and composes it into a single homepage feed — ranked and tagged automatically, but transparently. You can always see *why* an item is where it is, and you can always override it. It's a **personal content router**, not a bookmark manager (though it remembers what you save).

## Try it

<!-- TODO: live demo link -->

## Self-host it

One command, from a fresh clone with nothing but `.env` filled in:

```sh
git clone https://github.com/your-user/stray && cd stray
bin/setup-wizard          # interactive, on the host — writes .env
docker compose up -d
```

Then open your instance and create your admin account at `/setup`.

Prefer a VPS/production-style deploy? `config/deploy.yml` ships for **Kamal**:

```sh
kamal deploy
```

> **⚠️ Volumes are critical.** SQLite databases (primary/cache/queue/cable) and ActiveStorage files live on mounted volumes in both Compose and Kamal. If you remove or forget the volumes, redeploys **wipe your data**. This is the #1 self-hosting footgun — don't skip it.

The app is fully functional with **zero AI configured**. LLM tagging and semantic search are optional, additive enhancements.

## Features

- **Follow anything** — add a `Source` by URL and Stray auto-detects the kind: RSS/Atom feed, YouTube channel, generic web page, or GitHub awesome-list.
- **One homepage feed** — everything you follow, composed and ranked transparently (reverse-chronological + per-source weight you can inspect and reset).
- **Tagging you can trust** — zero-shot embedding tagging works out of the box with no AI setup; optional LLM tagging via Ollama or any OpenAI-compatible API. Every tag shows its provenance (`ai_embedding` / `ai_llm` / `user`).
- **Search** — full-text (SQLite FTS5) always available; semantic "search by meaning" as a toggle once embeddings exist.
- **Per-creator view** — browse a single source's feed directly.
- **Save, hide, mute** — `unseen`/`seen`/`saved`/`hidden` item states plus mute/boost that adjusts a source's weight.
- **Share as plain RSS/Atom** — public collections export to standard feeds any reader can pull (v3.5).
- **One-command self-host** — Docker Compose or Kamal, SQLite + Solid Queue, no external services.

<!-- TODO: screenshots per feature -->

## Tech stack

Rails 8 · SQLite · Solid Queue / Solid Cache / Solid Cable · Hotwire (Turbo + Stimulus) · SQLite FTS5 · Ruby 4.0.5

## Roadmap

Full plan lives in [`docs/PLAN.md`](docs/PLAN.md).

- **v1 (current)** — single-user auth, follow by URL, background polling, extractor adapters, FTS5 search, zero-shot + optional LLM tagging, transparent ranking, save/hide/mute, setup wizards, Docker Compose + Kamal, CI.
- **v2** — "similar to what I save" taste-vector ranking, tag-vocabulary growth, near-duplicate dedup, import (OPML / Pocket / Raindrop / Pinboard).
- **v3 / v3.5** — multi-user, `Collection`s with visibility, public collection RSS/Atom export.
- **v4+** — cross-instance pull; real-time federation only after v4 validates the model.

## Contributing

See [`AGENTS.md`](AGENTS.md) for the project principles, conventions, architecture, and how to run the test/lint/security suite.

## License

Stray is licensed under the [AGPL-3.0](LICENSE). It prevents closed-source SaaS forks without reciprocal open-sourcing.

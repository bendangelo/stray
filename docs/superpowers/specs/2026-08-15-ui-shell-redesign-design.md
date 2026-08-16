# UI Shell Redesign: Header Search, Tag Bar, Sources Sidebar, Favicon Migration

**Date:** 2026-08-15
**Status:** Approved

## Goal

Restructure the Stray UI from a single-navbar layout into a three-zone app shell: a sticky header bar (logo + search + paste-link + user menu), a horizontal tag filter bar, and a collapsible left sidebar listing followed sources with favicons and unseen counts. Migrate brand/favicon assets from `stray_old`.

## Context

The current app has:
- A top navbar with logo (hidden on mobile), an inline paste-link form, "Sources" link, and logout.
- A search bar *below* the feed heading (only on the feed page).
- No sidebar. No tag UI (Tag/Tagging models exist but nothing renders them). Sources index is a plain list with no icons or unseen counts.
- ERB templates, Tailwind v4, neobrutalist aesthetic (3px charcoal borders, flat colors).

`stray_video` (reference) places the search bar in a top `<nav>` with source filter tabs below it. `stray_old` holds the favicon set and wordmark logo to migrate.

## Design

### Layout Structure

```
┌─────────────────────────────────────────────────────────────┐
│ HEADER BAR (sticky top)                                      │
│ [☰] [logo]  [🔍 Search............] [📎 Paste link...] [user] │
├─────────────────────────────────────────────────────────────┤
│ TAG BAR (horizontal, scrollable on mobile)                   │
│  All  ruby  rails  ai  youtube  github  →                    │
├──────────┬──────────────────────────────────────────────────┤
│ SIDEBAR  │  MAIN CONTENT (feed grid)                         │
│ (left)   │                                                    │
│          │  [item] [item] [item] [item]                      │
│ Sources  │  [item] [item] [item] [item]                      │
│ ┌──────┐ │                                                    │
│ │favicon│ │                                                    │
│ │ Name  │ │                                                    │
│ │  (3)  │ │                                                    │
│ └──────┘ │                                                    │
│ ┌──────┐ │                                                    │
│ │favicon│ │                                                    │
│ │ Name  │ │                                                    │
│ │  (12) │ │                                                    │
│ └──────┘ │                                                    │
│          │                                                    │
└──────────┴──────────────────────────────────────────────────┘
│ FOOTER (fixed bottom, as now)                                │
└─────────────────────────────────────────────────────────────┘
```

### Responsive Behavior

- **Desktop (lg+):** Sidebar is a persistent `w-60` column. Header has logo + search (`max-w-xl`, `flex-1`) + paste input (`w-48 lg:w-64`) + user menu.
- **Tablet (md):** Sidebar narrows to `w-52`. Both inputs visible; paste shrinks to `w-36`.
- **Mobile (<md):** Sidebar becomes a slide-in drawer toggled by the ☰ hamburger. Header shows ☰ + compact favicon icon (32px) + search (`flex-1`) + paste (`w-24`). Tag bar scrolls horizontally with `overflow-x-auto`. Feed grid drops to 2 columns (already does).

### Header Bar

- **Hamburger** — `md:hidden`, toggles sidebar drawer via `sidebar_controller`.
- **Logo** — stray_old wordmark (`stray-logo.svg`), `w-20 lg:w-28`, visible from `md` up. On mobile (`<md`), show `apple-touch-icon.png` as a compact 32px mark so brand presence remains without the wordmark.
- **Search** — moves from `feed/_search` partial into the header. GET form to `root_path`, same `q` param. Styled like stray_video's searchbox: `rounded-md border-3 border-charcoal bg-athens-400`, `h-12` input, magnifier-icon submit button (`w-14`, carrot-colored, inverts on hover). Present on all authenticated pages.
- **Paste input** — the existing `links_path` POST form, `turbo_stream: true`. Always visible. `w-48 lg:w-64`. Same `+` submit button. Wire up proper success/feedback via the existing `turbo_stream_from "user_#{id}_intake"` channel (currently no view consumes it — add a turbo stream response that updates `#intake_status` with a confirmation and auto-dismisses).
- **User menu** — username + "Log out" (compact, `text-sm`).

### Tag Bar

- Sits directly below the header, above the sidebar+content split. Full width.
- Horizontal row of tag chips: "All" (active by default, clears `tag` param) + each tag name.
- Active tag gets `border-b-6 border-carrot` underline + `font-semibold text-carrot` (matching stray_video's `nav_filters` style).
- Clicking a tag navigates to `root_path(tag: name)` — filters the current followed-sources feed. Combinable with `q` (search): `/?q=rails&tag=ai`.
- Tags sourced from `Tag` model, ordered by item count desc (most-used first), limited to tags that have at least one item in the user's followed sources.
- Renders only on the feed page (not on source show, sources index, or other pages — those pages keep header + sidebar but no tag bar).
- Scrolls horizontally on mobile: `overflow-x-auto whitespace-nowrap`.

### Left Sidebar — Sources List

- New partial `app/views/sources/_sidebar.html.erb`.
- "Sources" heading at top + link to full `sources_path` index.
- Each source row: favicon/avatar (32px), source name (truncate), unseen count badge.
- Favicon source priority: `source.icon_url` if present → DuckDuckGo fallback `https://icons.duckduckgo.com/ip3/#{domain}.ico` (extracted from `source.url`) → generated initial letter in a bordered box.
- Unseen count: `Item.where(source: source, state: :unseen).count`. Computed via a grouped query (`group(:source_id).count` filtered by `state: :unseen` and followed source IDs) to avoid N+1.
- Count badge: small pill, `bg-carrot text-champagne text-xs`, only shown when count > 0.
- Clicking a source row navigates to `source_path(source)` (existing route).
- Desktop: persistent `w-60` column, `border-r-3 border-charcoal`, `bg-champagne`, full height with `overflow-y-auto`.
- Mobile: `fixed inset-y-0 left-0 z-40 w-64` drawer, `translate-x-[-100%]` when closed, `translate-x-0` when open. Backdrop overlay (`fixed inset-0 bg-charcoal/50`) click closes. Controlled by `sidebar_controller`.

### Feed Controller Changes

- Add `@tag = params[:tag].presence` filter: when present, join `taggings` + `tags` where `tags.name = @tag`.
- Add `@tags` collection for the tag bar: tags with item counts for the current user's followed sources. Query: join tags → taggings → items → sources → follows, group by tag, count, order by count desc.
- Both `@q` (search via `full_search`) and `@tag` can combine.
- Pagy pagination unchanged.

### Logo & Favicon Migration from stray_old

Copy these assets from `/home/bendangelo/Projects/stray_old`:

| From | To |
|------|-----|
| `app/assets/images/favicon/favicon.svg` | `app/assets/images/favicon/favicon.svg` |
| `app/assets/images/favicon/favicon.ico` | `app/assets/images/favicon/favicon.ico` |
| `app/assets/images/favicon/favicon-96x96.png` | `app/assets/images/favicon/favicon-96x96.png` |
| `app/assets/images/favicon/apple-touch-icon.png` | `app/assets/images/favicon/apple-touch-icon.png` |
| `app/assets/images/favicon/web-app-manifest-192x192.png` | `app/assets/images/favicon/web-app-manifest-192x192.png` |
| `app/assets/images/favicon/web-app-manifest-512x512.png` | `app/assets/images/favicon/web-app-manifest-512x512.png` |
| `app/assets/images/stray-logo.svg` | `app/assets/images/stray-logo.svg` (replaces current) |
| `public/favicon.ico` | `public/favicon.ico` |

Create `app/views/layouts/_favicon.html.erb` (port from stray_old's Slim partial):
```erb
<link rel="icon" type="image/png" href="<%= asset_path('favicon/favicon-96x96.png') %>" sizes="96x96">
<link rel="icon" type="image/svg+xml" href="<%= asset_path('favicon/favicon.svg') %>">
<link rel="shortcut icon" href="<%= asset_path('favicon/favicon.ico') %>">
<link rel="apple-touch-icon" sizes="180x180" href="<%= asset_path('favicon/apple-touch-icon.png') %>">
<meta name="apple-mobile-web-app-title" content="Stray">
```

Update `application.html.erb` to render `_favicon` partial instead of current `icon.png`/`icon.svg` links. Remove/replace `public/icon.svg` and `public/icon.png`.

Add PWA manifest: create `app/views/pwa/manifest.json.erb` referencing the 192/512 PNGs. Add routes `get "manifest" => "rails/pwa#manifest"` and `get "service-worker" => "rails/pwa#service_worker"` if not present.

### Stimulus Controllers

- **New: `sidebar_controller.js`** — values: `open` (Boolean, default false). Targets: `sidebar`, `backdrop`. Actions: `toggle` (on hamburger click), `close` (on backdrop click), `close` on Escape keypress. Toggles `translate-x-[-100%]`/`translate-x-0` on sidebar target and `hidden`/`block` on backdrop target.
- **Existing `player_controller.js`** — unchanged.

### Files to Create/Modify

| Action | File |
|--------|------|
| Modify | `app/views/layouts/application.html.erb` — new shell structure: header + tag bar slot + sidebar + content |
| Modify | `app/views/layouts/_navbar.html.erb` — becomes the header bar (logo + search + paste + user) |
| Create | `app/views/layouts/_favicon.html.erb` |
| Create | `app/views/shared/_tag_bar.html.erb` |
| Create | `app/views/sources/_sidebar.html.erb` |
| Create | `app/javascript/controllers/sidebar_controller.js` |
| Modify | `app/controllers/feed_controller.rb` — add tag filter + tags collection |
| Modify | `app/views/feed/index.html.erb` — remove inline search, render tag bar, adapt grid for sidebar layout |
| Create/modify | `app/helpers/sources_helper.rb` — favicon fallback helper |
| Copy | favicon set + logo from stray_old |
| Modify | `config/routes.rb` — add PWA routes if missing |
| Create | `app/views/pwa/manifest.json.erb` |

### Out of Scope

- No tag management UI (create/rename/delete tags) — display + filter only.
- No source create/edit/delete/pause UI — paste-link remains the only add path.
- No autocomplete on search (separate enhancement).
- No dark mode.
- No rebranding of the wordmark (keeping "Stray Video" as-is from stray_old).
- No changes to ranking, tagging jobs, or extractors.

### Testing

- `FeedControllerTest`: add tests for `tag` param filtering (items filtered by tag), combined `q` + `tag`, `@tags` collection populated, no tag → all items.
- `SourcesHelperTest` (if created): favicon fallback helper returns icon_url, DuckDuckGo URL, or initial.
- System test: sidebar toggle on mobile viewport, tag bar click filters feed, header search submits to `root_path` with `q` param.
- Existing tests must still pass: feed index, source show, item update, links create.
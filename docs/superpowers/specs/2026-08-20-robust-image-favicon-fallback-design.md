# Design: Robust Image & Favicon Fallback

Date: 2026-08-20
Status: Proposed

## Purpose

External images shown in Stray — source favicons (via DuckDuckGo's `icons.duckduckgo.com` favicon service), item thumbnails (YouTube/Rumble/Odysee/etc. CDN URLs), and channel avatars — can 404, disappear, or fail to load for reasons outside the app's control (third-party outage, CDN rot, hotlink protection, network). Today the app handles **only the nil-URL case** server-side (`item.thumbnail_url || missing_thumb`, `source.icon_url || DuckDuckGo`). There is no runtime fallback: when a remote image URL is present but the browser fails to fetch it, the user sees a broken-image icon with no recovery.

This design adds a single, generic client-side fallback mechanism so any `<img>` referencing an external URL degrades gracefully. It also consolidates the currently scattered image rendering (raw `<img>` tags across four views + one helper method) into one helper, so the fallback is applied consistently and future image changes have one home.

The long-term question — whether to download/cache favicons and thumbnails locally to survive third-party outages and improve privacy — is explicitly **deferred**. A note is added to `docs/PLAN.md` so it isn't lost, but this design does not add ActiveStorage, a proxy controller, or any storage/jobs. Rationale: it violates the "one-command self-host, zero-setup" principle (storage growth, cleanup, volume sizing), and the robust fallback below solves the visible-broken-image problem for a single-user app without that cost.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where the fallback runs | Client-side (Stimulus + `onerror`) | Server-side can't know if a URL will 404 without fetching it. The app deliberately does not proxy/cache images (deferred decision), so it can't pre-validate. The browser is the only place that knows the fetch failed. |
| Mechanism | A single generic Stimulus controller (`image-fallback`) on the `<img>` element, driven by `data-*` attributes | One controller serves both image types (thumbnails + source icons). No per-image-type JS. Matches existing Stimulus usage in the repo (`dropdown`, `sidebar`, `player`). |
| Source-icon fallback target | Letter avatar (first letter of source name in a styled `<div>`) | Matches the existing server-side letter-avatar fallback in `sources_helper.rb:42-46`. Visual consistency: whether the URL was nil from the start or 404'd at runtime, the user sees the same thing. |
| How the letter avatar appears on error | Render both `<img>` and a hidden letter `<div>` as siblings inside a wrapper; controller hides the img and shows the div on error | Swapping an `<img>` for a `<div>` by replacing DOM nodes in `onerror` is fragile (the `error` handler can't easily synthesize the div, and the replacement can't carry the controller's own state cleanly). Pre-rendering the fallback and toggling visibility is simpler and robust. The extra DOM is two elements per source icon — negligible. |
| Item-thumbnail fallback target | Local `missing-video.jpg` asset (already exists) | Already the server-side fallback for nil thumbnails. Runtime fallback reuses the same asset for consistency. |
| Preventing infinite fallback loops | Controller sets a `fallbackApplied` flag after the first swap and ignores further `error` events | If the local fallback asset itself somehow fails (shouldn't, but defensive), the browser would fire `error` again. The flag breaks the cycle. The local asset is served by the app itself, so this is belt-and-suspenders. |
| Helper consolidation | New `ImagesHelper` with `fallback_image_tag` and `source_icon_tag`; existing `SourcesHelper#source_icon` becomes a thin delegate | Today image rendering is spread across raw `<img>` in 4 views + `source_icon` in `sources_helper.rb`. A dedicated helper gives fallback logic one home and makes future image changes (e.g. adding `referrerpolicy`, `loading=lazy`) a single-file edit. `source_icon` stays as a delegate so `_source.html.erb` and `show.html.erb` call sites don't change. |
| Schema/storage | None | No ActiveStorage, no new columns, no jobs. This is a view-layer change only. |
| Local image caching (future) | Deferred; noted in `docs/PLAN.md` | Solves a different problem (third-party outage resilience + privacy) than this design solves (broken-image UX). Worth doing eventually but not now — see "Out of scope." |

## Architecture

```
View renders:
  <div data-controller="image-fallback">
    <img src="<external URL>"
         data-action="error->image-fallback#onError"
         data-image-fallback-target="primary"
         ...>
    <div data-image-fallback-target="fallback" class="hidden ...">A</div>   # source icon only
  </div>

Browser fails to load external URL → fires `error` on <img>
  → Stimulus ImageFallbackController.onError()
      → if already applied, return (loop guard)
      → if has fallbackTarget: hide primaryTarget, un-hide fallbackTarget
      → else if has fallbackSrcValue: primaryTarget.src = fallbackSrcValue
      → set fallbackApplied flag
```

For item thumbnails, no sibling fallback element is rendered — the controller swaps `src` to the local `missing-video.jpg` asset via `fallbackSrcValue`. For source icons, no `src` swap happens — the `<img>` is hidden and the letter `<div>` is shown, so there's no risk of the fallback image itself 404'ing.

## §1 — `ImageFallbackController`

New file: `app/javascript/controllers/image_fallback_controller.js`

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "primary", "fallback" ]
  static values = { fallbackSrc: String }

  connect() {
    this.fallbackApplied = false
  }

  onError() {
    if (this.fallbackApplied) return
    this.fallbackApplied = true

    if (this.hasFallbackTarget) {
      this.primaryTarget.classList.add("hidden")
      this.fallbackTarget.classList.remove("hidden")
    } else if (this.fallbackSrcValue) {
      this.primaryTarget.src = this.fallbackSrcValue
    }
  }
}
```

The controller lives on a **wrapper element** (a `<span>` or `<div>`), not on the `<img>` itself. This is so the wrapper can hold both the `<img>` (primary target) and the letter `<div>` (fallback target) as siblings, and the controller can toggle both. The `<img>` carries `data-action="error->image-fallback#onError"` and `data-image-fallback-target="primary"`; the letter div carries `data-image-fallback-target="fallback"` and starts `hidden`.

For the thumbnail-only path (no letter fallback), the wrapper is still used but no `fallback` target is present — the controller falls through to the `fallbackSrcValue` branch.

### Loop guard

`onError` checks `this.fallbackApplied` and returns early if already true. This prevents a cascade if the local fallback asset also fails (it shouldn't — it's served by the app — but the guard is cheap insurance). The flag resets on `connect` (i.e. on Turbo navigation that re-connects the controller), which is correct because a re-rendered image is a fresh attempt.

### Why not put the controller directly on `<img>`?

Two reasons:
1. For source icons we need a sibling letter `<div>` to show on error. The controller must reach both elements via targets, and Stimulus targets must be within the controller's element subtree. An `<img>` can't have child elements, so it can't host a `fallback` target.
2. Keeping the wrapper consistent (even for the thumbnail path with no sibling) means one controller pattern, one set of attribute names, and less branching in the helper.

## §2 — `ImagesHelper`

New file: `app/helpers/images_helper.rb`

```ruby
module ImagesHelper
  # Renders an <img> with a runtime fallback to a local asset when the
  # remote src fails to load. If `src` is nil, renders the fallback
  # directly with no controller (nothing to fail).
  def fallback_image_tag(src, fallback: missing_thumb, alt: "", class: "", **opts)
    if src.blank?
      return image_tag(fallback, alt: alt, class: class, **opts)
    end

    content_tag :span, class: "inline-flex", data: { controller: "image-fallback" } do
      image_tag(src,
        alt: alt, class: class, loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError",
          image_fallback_fallback_src_value: fallback
        },
        **opts)
    end
  end

  # Renders a source icon with the full fallback chain:
  #   source.icon_url → DuckDuckGo favicon → letter avatar.
  # When a URL resolves, renders an <img> + hidden letter <div>; the
  # ImageFallbackController hides the img and shows the letter on error.
  # When no URL resolves at all, renders just the letter <div> (no controller).
  def source_icon_tag(source, size: "w-8 h-8", class: "", **opts)
    url = source_icon_url(source)
    letter = source.name.to_s.first.upcase
    letter_classes = "#{size} rounded border-2 border-charcoal bg-charcoal " \
                     "text-white font-bold text-sm flex items-center justify-center shrink-0"

    if url.blank?
      return content_tag(:div, letter, class: "#{letter_classes} #{class}".strip, **opts)
    end

    content_tag :span, class: "inline-flex #{class}".strip,
                data: { controller: "image-fallback" } do
      concat(image_tag(url,
        alt: source.name, class: "#{size} rounded border-2 border-charcoal shrink-0 object-contain bg-white p-0.5",
        loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError"
        }))
      concat(content_tag(:div, letter, class: "hidden #{letter_classes}", data: { image_fallback_target: "fallback" }))
    end
  end
end
```

### Existing `SourcesHelper#source_icon`

Becomes a thin delegate so existing call sites (`_source.html.erb:6`, `show.html.erb:9`) keep working unchanged:

```ruby
# app/helpers/sources_helper.rb
def source_icon(source, size: "w-8 h-8")
  source_icon_tag(source, size: size)
end
```

`source_icon_url` (the URL resolver, `sources_helper.rb:25-36`) stays where it is — it's pure URL logic, used by manifests and jobs, not just views. The new helper calls it.

### `missing_thumb`

Already exists in `ApplicationHelper` (`application_helper.rb:80-82`). The new helper references it; since both helpers are mixed into the same view base, no change needed. (If we wanted to be tidy, `missing_thumb` could move into `ImagesHelper`, but that's cosmetic and not required for this design.)

## §3 — View migrations

Each raw `<img>` site is replaced with a helper call. The wrapper `<span class="inline-flex">` carries the controller; the `<img>` carries the error action and target. Existing Tailwind classes on the `<img>` are preserved verbatim.

| File:Line | Was | Becomes |
|---|---|---|
| `items/_item.html.erb:8-11` | raw `<img src="<%= item.thumbnail_url \|\| missing_thumb %>" class="...">` | `<%= fallback_image_tag(item.thumbnail_url, alt: item.title, class: "group-hover:border-2 border-carrot-400 object-cover w-full aspect-video rounded-md border-3 border-charcoal") %>` |
| `items/_item.html.erb:18-20` | raw `<img src="<%= icon %>" class="absolute left-2 bottom-2 w-5 h-5 ...">` (inside `if (icon = source_icon_url(item.source))`) | `<%= source_icon_tag(item.source, size: "w-5 h-5", class: "absolute left-2 bottom-2") %>` (the `if` wrapper is no longer needed — the helper handles the no-URL case) |
| `items/_player.html.erb:12-13` | raw `<img src="<%= item.thumbnail_url %>" class="...">` | `<%= fallback_image_tag(item.thumbnail_url, alt: item.title, class: "object-cover w-full lg:mx-6 lg:w-1/2 h-72 lg:h-96 rounded-md border-3 border-charcoal") %>` |
| `items/_player.html.erb:33-35` | raw `<img src="<%= icon %>" class="w-5 h-5 ...">` (inside `if`) | `<%= source_icon_tag(item.source, size: "w-5 h-5") %>` |
| `items/show.html.erb:34-35` | raw `<img src="<%= @item.thumbnail_url %>" class="...">` | `<%= fallback_image_tag(@item.thumbnail_url, alt: @item.title, class: "object-cover w-full aspect-video rounded-md border-3 border-charcoal") %>` |
| `items/show.html.erb:51-52` | raw `<img src="<%= @item.thumbnail_url %>" class="... mb-4">` | `<%= fallback_image_tag(@item.thumbnail_url, alt: @item.title, class: "object-cover w-full aspect-video rounded-md border-3 border-charcoal mb-4") %>` |
| `sources/_sidebar.html.erb:18-21` | raw `<img src="<%= source_icon_url(source) \|\| missing_thumb %>" class="w-8 h-8 ...">` | `<%= source_icon_tag(source, size: "w-8 h-8") %>` (note: the old `|| missing_thumb` was a weaker fallback — it only fired when the URL *resolver* returned nil, not when the remote image 404'd; the new helper covers both) |
| `sources_helper.rb:38-47` | full `source_icon` implementation | delegate to `source_icon_tag` (see §2) |

### Positioning note for the item-card source icon overlay

The current `<img>` at `_item.html.erb:18-20` is absolutely positioned (`absolute left-2 bottom-2`) inside a `relative` thumbnail container. The wrapper `<span class="inline-flex absolute left-2 bottom-2">` carries the positioning; the inner `<img>` and letter `<div>` inherit the `w-5 h-5` size. The helper's `class:` param is applied to the wrapper, so the positioning classes move from the `<img>` to the `<span>`. This preserves the exact visual placement.

## §4 — Tests

### Helper tests

New file: `test/helpers/images_helper_test.rb`

Covers:

**`fallback_image_tag`**
- With a non-nil `src`: renders a `<span data-controller="image-fallback">` wrapper containing an `<img>` with `data-image-fallback-target="primary"`, `data-action="error->image-fallback#onError"`, and `data-image-fallback-fallback-src-value` set to the fallback asset path. Asserts the `src` is the given URL.
- With a nil `src`: renders the fallback `<img>` directly, no controller, no wrapper. Asserts `src` is the fallback asset and no `data-controller` attribute.

**`source_icon_tag`**
- With `icon_url` present: renders wrapper + `<img>` (src = icon_url) + hidden letter `<div>` (data-image-fallback-target="fallback"). Asserts the letter is the upcased first char of the source name, and that the fallback div has the `hidden` class.
- With `icon_url` nil but a valid source URL (DuckDuckGo path): same as above, src = DuckDuckGo favicon URL.
- With no resolvable URL (invalid source URL): renders only the letter `<div>`, no wrapper, no controller, no `<img>`. Asserts the letter and classes.

**`source_icon` (delegate)**
- Existing `sources_helper_test.rb` tests pass unchanged (the delegate produces equivalent markup: an `<img>` when a URL resolves, a letter `<div>` when not). The one difference: when a URL resolves, there is now also a hidden sibling letter `<div>` inside a wrapper. Update the two assertions that check `assert_match(/<img/, html)` to also accept the wrapper, or assert on the `<img>` substring specifically. The "renders letter avatar for invalid URLs" test is unchanged (no `<img>` in that branch).

### System test

New file: `test/system/image_fallback_test.rb`

A Capybara system test that:
1. Visits a page rendering an item with a deliberately broken thumbnail URL (e.g. set `item.thumbnail_url = "http://localhost:9/definitely-broken.jpg"` in a fixture or via a test helper route).
2. Programmatically fires the `error` event on the `<img>` (Capybara's headless browser won't actually 404 a localhost URL reliably, so use `execute_script` to dispatch a real `error` Event on the target element).
3. Asserts the `src` attribute on the `<img>` has swapped to the `missing-video.jpg` asset path.

For the source-icon letter-avatar fallback:
1. Visit a page with a source icon whose URL is broken.
2. Fire `error` on the `<img>`.
3. Assert the hidden letter `<div>` is now visible (no `hidden` class) and the `<img>` is hidden (has `hidden` class).

This is the minimum to prove the controller wiring works end-to-end through the view helper. It does not test against a real third-party 404 (flaky); the `execute_script` approach is deterministic.

## §5 — `docs/PLAN.md` note

Add a one-line entry under a "Future / deferred" section in `docs/PLAN.md` (creating the file if it doesn't exist, since AGENTS.md already references it):

> **Local image cache / proxy.** Download favicons and item thumbnails once, serve from the app (ActiveStorage or a `/img/proxy?u=...` controller with Solid Cache). Survives third-party outages, improves privacy (no referrer leaks to CDNs), and enables offline-ish reading. Deferred — adds storage growth, cleanup jobs, and volume-sizing concerns that conflict with the one-command self-host principle for v1. Revisit when the broken-image fallback (added 2026-08-20) proves insufficient. See `docs/superpowers/specs/2026-08-20-robust-image-favicon-fallback-design.md`.

This ensures the long-term question isn't lost without committing to it now.

## Out of scope

- **ActiveStorage / local image caching / proxy controller** — deferred (see §5). This design is a view-layer fallback only.
- **`referrerpolicy` / `crossorigin` attributes** — not added. Some third-party CDNs reject hotlinks based on referrer; adding `referrerpolicy="no-referrer"` would help but is a separate concern from fallback and can be a one-line follow-up in `ImagesHelper` later. Noting here so it's not forgotten.
- **Lazy-loading tuning** — `loading="lazy"` is added uniformly by the new helper where it wasn't before (some raw `<img>` sites lacked it). This is a side-benefit, not a goal.
- **Image proxying for privacy** — deferred with the cache (§5).
- **A default "globe" or "feed" favicon asset** for sources with no letter-avatar-appropriate name — not needed; the letter avatar already handles the no-name case (empty string → the div renders empty, which is fine; a `source.name` of nil is guarded by `.to_s`).

## Build order

1. **`ImageFallbackController`** — write the controller, add to `app/javascript/controllers/` (auto-registered via `eagerLoadControllersFrom` in `index.js`, no registration change needed).
2. **`ImagesHelper`** — write `fallback_image_tag` and `source_icon_tag`. Make `SourcesHelper#source_icon` delegate.
3. **Migrate views** — update the 7 call sites in §3. Run the app, eyeball that source icons and thumbnails render identically (no visual regression).
4. **Helper tests** — write `images_helper_test.rb`; update the two assertions in `sources_helper_test.rb`.
5. **System test** — write `image_fallback_test.rb`.
6. **`docs/PLAN.md`** — add the deferred-cache note.
7. **Verify** — `bin/rails test`, `bin/rubocop`, `bin/rails test:system`. Fix any failures.
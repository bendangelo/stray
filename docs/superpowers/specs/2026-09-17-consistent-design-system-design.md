# Stray Design System & Mobile UX

**Date:** 2026-09-17
**Status:** Approved

## Goal

Establish Stray's UI as a consistent, touch-friendly design system built on the existing visual identity (champagne/charcoal/carrot palette, `border-3` cards, Space Grotesk display font), fixing the acute dropdown usability problems (tiny click areas, nearly invisible highlight) and bringing every surface — main app, auth/setup, admin, public share pages — up to one shared component standard with a 44px minimum tap target.

## Problem

The 2026-09-17 audit found the visual identity is tokenized and mostly disciplined, but execution is inconsistent:

- **Dropdowns (chief complaint):** menu items are `px-2 py-1 text-xs` (~20px tall — app/helpers/application_helper.rb:143 `dropdown_menu_item_class`), triggers are 24–36px, and the `hover:bg-athens-300` highlight is barely perceptible against the near-white `bg-athens-400` menu surface. Dropdown markup is duplicated across 6 views with no shared partial (the `_dropdown.html.erb` planned in the 2026-09-07 plan was never created).
- **Tap targets vary widely:** hamburger ~32px, sidebar rows ~28–36px, primary buttons ~36px, pagination links small text.
- **Off-palette colors:** `text-stone-600`/`text-blue-600` (sources public show), `text-gray-800`/`text-gray-500` (items player), hardcoded hexes in `.dot-ai_*` (application.css).
- **Component drift:** two border conventions for buttons (`border-2` white action buttons on source show vs `border-3` everywhere else), three button heights (`px-4 py-2`, `h-10`, `h-12`), duplicated "Why is this here" panel (items/show.html.erb vs _why.html.erb), two near-identical tag chips, flash markup duplicated in layout + auth pages, mixed page max-widths, three card padding variants.
- **Mobile gaps:** no focus management on the drawer, no `env(safe-area-inset-*)` for the installable PWA.
- **Dead code:** `hello_controller.js` unused.

## Design

### 1. Tokens & CSS foundation

`app/assets/tailwind/application.css` stays the single CSS source. Changes:

- Add to `@theme`:
  - `--color-athens-100` — strong grey for selected states (scale currently jumps from grey-300 to near-white).
  - `--color-carrot-100` — warm tint for the menu highlight.
  - Semantic role aliases so views reference roles, not scale numbers: `--color-surface` (champagne), `--color-card` (athens-400), `--color-ink` (charcoal-600), `--color-accent` (carrot-500), `--color-danger` (cerise-500).
- Define interactive-state CSS classes in the existing custom-CSS section (alongside `.dot-*` and `mark`):
  - `.ui-menu-item` — `min-height: 2.75rem` (44px); `:hover` and `:focus-visible` get carrot-100 fill + carrot-700 text; danger variant gets cerise fill/text. Hover and keyboard nav share one visible treatment.
- Button height scale: `h-9` (sm/inline), `h-11` (default), `h-12` (form submit).
- Cleanup: delete unused `hello_controller.js`; `.dot-*` hardcoded hexes replaced with theme colors (sky/mint/charcoal scale).

### 2. Dropdown system

- `dropdown_menu_item_class` (application_helper.rb:143) rewritten to emit `.ui-menu-item` with `px-3 py-2 text-sm` — 44px items, up from ~20px.
- Trigger buttons: icon-only triggers become `h-11 w-11` (min 44px) with subtle `hover:bg-athens-300 rounded-md`; sidebar trigger rows make the full row height clickable, not just the icon.
- Menu container normalized: `min-w-44 p-1.5 border-3 border-charcoal rounded-md bg-athens-400 shadow-lg`; mobile guard `max-w-[calc(100vw-1.5rem)]` retained.
- New partial `app/views/shared/ui/_dropdown.html.erb` (trigger content, menu content, alignment options) replaces all 6 duplicated sites: item actions menu, sidebar source menu, sidebar collection menu, navbar account menu, tag-bar "More", collection membership picker.
- Same `.ui-menu-item` treatment applied to the other small-item surfaces: `tag_input_controller.js` inline results, `search/_suggestions.html.erb`, `_why.html.erb` `<details>` summary.

### 3. Mobile

- Keep the hamburger drawer pattern; harden it:
  - Hamburger trigger → 44px (`h-11 w-11`).
  - Drawer rows (sources, collections, nav links, paste-link form input + button) → `min-h-11` (44px floor).
  - Focus management: drawer close returns focus to the hamburger; backdrop gets `aria-label="Close menu"`.
  - `env(safe-area-inset-*)` padding on fixed navbar/sidebar (Stray is an installable PWA; respect notch and home indicator).
- Pagination "Newer/Older" links → proper 44px buttons; item detail header action cluster wraps cleanly with `flex-wrap gap-2`.
- Viewport stays `width=device-width,initial-scale=1` — never block zoom.
- No feed grid changes (player column computation already adapts 2→6 columns).

### 4. Component layer & consistency sweep

- New `app/helpers/ui_helper.rb` with class-string methods, one control each:
  - `ui_button(variant: :primary|:secondary|:danger, size: :sm|:md|:lg)`
  - `ui_menu_item(danger:)` (absorbs `dropdown_menu_item_class`)
  - `ui_input`, `ui_label`, `ui_card`, `ui_flash`, `ui_page(max:)`, `ui_select` (styling wrapper — native `<select>`s stay native)
- New partials in `app/views/shared/ui/`:
  - `_dropdown.html.erb`
  - `_flash.html.erb` — dedupes layout inline flash + setup/login/password copies
  - `_empty_state.html.erb` — unifies the three padding variants
  - `_tag_chip.html.erb` — one chip with provenance icon everywhere (replaces the near-duplicate in items/show)
- Sweep normalization rules applied to all 19 view dirs (main app, auth/setup, admin, public):
  - Off-palette colors → tokens (stone/blue/gray → charcoal scale; `.dot-*` → sky/mint).
  - Page max-widths: 3 tiers — `max-w-3xl` (forms), `max-w-6xl` (lists), `max-w-screen-xl` (reader detail).
  - Single "Why is this here" panel: one `_why.html.erb` used standalone (items/show) and inside the dropdown — removes duplicated ranking-explain markup.
  - All buttons `border-3`: secondary `bg-athens-400`, primary `bg-carrot-500`, danger cerise.
  - Native `<select>`s (source form, admin settings) stay native (good mobile behavior), styled consistently.
- Testing:
  - Unit tests for UiHelper class output.
  - Existing Minitest + Capybara suite stays green (class changes must not break selectors).
  - New system test: dropdown open → item click at mobile viewport (375×667).
- Deliver `docs/DESIGN.md`: token list, component inventory, 44px tap-target rule, "how to add a new dropdown" recipe — the reference future sessions follow.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Keep the current visual identity (champagne/charcoal/carrot, `border-3`, Space Grotesk) | Distinctive and already tokenized in `@theme`; standardize on it and clean up leaks |
| 2 | Light-mode only; no `dark:` variants | Cheapest path; semantic role tokens keep a future dark theme easy to retrofit |
| 3 | Keep the hamburger drawer for mobile nav | Pattern already works; effort goes to touch-friendliness inside it |
| 4 | 44px minimum tap targets everywhere (`min-h-11`) | Apple HIG minimum; keeps menus from over-towering |
| 5 | Menu highlight: warm carrot tint (carrot-100 fill + carrot-700 text) | Clearly visible against near-white menu, on-brand accent |
| 6 | Component layer via helpers + shared partials + CSS state classes; no ViewComponent, no CSS-only | Matches existing conventions (`dropdown_menu_item_class` already exists), zero new dependencies |
| 7 | Scope: every surface — main app, auth/setup, admin, public pages | One coordinated pass |
| 8 | Big-bang structure: components first, then full sweep | Chosen over phased rollout; single coordinated normalization |

## Out of scope

- Dark mode (tokens are structured so it can be added later).
- Bottom tab bar navigation.
- Feed grid / player column changes.
- New pages or features — this pass normalizes what exists.
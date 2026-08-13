# Stray — Design Foundation

**Date:** 2026-08-12
**Phase:** Phase 0 — Design Foundation
**Status:** Approved

## Purpose

Port the visual identity from `~/Projects/stray_video` into the Stray feed reader project. Establish the design system, layout shell, logo, favicon, and placeholder homepage before any feature work begins. This is the visual container that all future V1+ features will live in.

## Context

The Stray repo is a fresh Rails 8.1 scaffold (Ruby 4.0.5) with SQLite, Solid Queue/Cache/Cable, Tailwind v4, Hotwire, and Importmap. It has no models, no controllers beyond `ApplicationController`, no routes, stock layout, and stock README. CI is already configured (Brakeman, bundler-audit, RuboCop, Minitest, system tests).

The `stray_video` project is a video search engine built with Rails 8, Slim templates, Tailwind v3 (with `tailwind.config.js`), and a distinctive visual identity: champagne background, charcoal text, carrot orange accents, thick borders, and the "STRAY" wordmark logo.

This spec ports that identity into Stray using Tailwind v4 conventions (CSS-based `@theme` config, no JS config file) and ERB templates (translated from Slim).

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Template engine | ERB (keep scaffold default) | No new dependency; Slim components translated to ERB |
| Tailwind config | v4 `@theme` in CSS (no `tailwind.config.js`) | Project already on Tailwind v4.3.3; v4 uses CSS-based config |
| Logo | Copy `stray-logo.svg` wordmark as-is | Same brand, fill `#2a2a2a` works on champagne background |
| Favicon | Rails 8 default (`public/icon.png` + `public/icon.svg`) | Personal self-hosted app; modern browsers support SVG favicons; no gem needed |
| Body font | System font stack | Zero font loading overhead, no external requests, native feel on every platform |
| Header font | Space Grotesk, vendored locally in `app/assets/fonts/` | No external runtime requests; `@font-face` declaration in CSS; Propshaft serves fingerprinted files |
| Font management gem | None | System stack needs nothing; Space Grotesk is one variable woff2 file with a `@font-face` declaration — simpler than a gem |
| Color palette | Full 10 ramps (charcoal, champagne, athens, carrot, cerise, amber, mint, teal, sky, cotton) | Available for future features without re-configuring; charcoal/champagne/athens/carrot/cerise have 50–950, amber/mint/teal/sky/cotton have 100–900 (matching stray_video source) |
| Layout scope | Shell + navbar + footer + placeholder homepage | Visual container for all future pages; no feature-specific content yet |

## Section 1: Design Tokens (Tailwind v4 `@theme`)

All design tokens live in `app/assets/tailwind/application.css` via the `@theme` directive. Tailwind v4 reads `@theme` CSS variables and auto-generates utility classes from them.

### Colors

Ported from `stray_video/config/tailwind.config.js`, translated from nested JS objects to flat `--color-{name}-{shade}` CSS variables:

| Color | Base (500) | Role |
|---|---|---|
| charcoal | `#2A2A2A` | Text, borders |
| champagne | `#F8F2E8` | Page background |
| athens | `#EFF0F3` | Neutral surfaces, inputs |
| carrot | `#FF8E3C` | Primary accent |
| cerise | `#D9376E` | Secondary accent |
| amber | `#fbbd23` | Available for future use |
| mint | `#85d699` | Available for future use |
| teal | `#349d86` | Available for future use |
| sky | `#7d98f2` | Available for future use |
| cotton | `#d058ee` | Available for future use |

Each color includes its full ramp from the stray_video config. Charcoal, champagne, athens, carrot, and cerise have 50–950 shades. Amber, mint, teal, sky, and cotton have 100–900 (no 50 or 950 in the source). Notably, champagne and athens have white (`#FFFFFF`) clamped across 50–400 (and athens-400 is `#fffffe`), giving a light, airy palette with strong dark anchors.

Full ramp reference (from `stray_video/config/tailwind.config.js`):

```
charcoal:  50:#868686 100:#7C7C7C 200:#676767 300:#535353 400:#3E3E3E 500:#2A2A2A 600:#0E0E0E 700-950:#000000
champagne: 50-400:#FFFFFF 500:#F8F2E8 600:#EBDABD 700:#DEC192 800:#D1A967 900:#C4913C 950:#AE8135
athens:    50-300:#FFFFFF 400:#fffffe 500:#EFF0F3 600:#CFD2DB 700:#AFB4C3 800:#8F96AB 900:#6F7893 950:#626B83
carrot:    50:#FFF8F4 100:#FFEDDF 200:#FFD5B6 300:#FFBD8E 400:#FFA665 500:#FF8E3C 600:#FF6D04 700:#CB5500 800:#933E00 900:#5B2600 950:#3F1A00
cerise:    50:#F6D1DE 100:#F3C0D1 200:#ED9EB9 300:#E67CA0 400:#E05987 500:#D9376E 600:#B52254 700:#861A3E 800:#571129 900:#280813 950:#100308
amber:     100:#fef2d3 200:#fde5a7 300:#fdd77b 400:#fcca4f 500:#fbbd23 600:#c9971c 700:#977115 800:#644c0e 900:#322607
mint:      100:#e7f7eb 200:#ceefd6 300:#b6e6c2 400:#9ddead 500:#85d699 600:#6aab7a 700:#50805c 800:#35563d 900:#1b2b1f
teal:      100:#d6ebe7 200:#aed8cf 300:#85c4b6 400:#5db19e 500:#349d86 600:#2a7e6b 700:#1f5e50 800:#153f36 900:#0a1f1b
sky:       100:#e5eafc 200:#cbd6fa 300:#b1c1f7 400:#97adf5 500:#7d98f2 600:#647ac2 700:#4b5b91 800:#323d61 900:#191e30
cotton:    100:#f6defc 200:#ecbcf8 300:#e39bf5 400:#d979f1 500:#d058ee 600:#a646be 700:#7d358f 800:#53235f 900:#2a1230
```

### Border widths

Custom thick border widths (the distinctive stray_video border aesthetic):

```css
--border-width-3: 3px;
--border-width-6: 6px;
--border-width-8: 8px;
```

Generates `border-3`, `border-6`, `border-8` utilities. Active states use thick bottom borders (e.g. `border-b-6 border-carrot`) instead of filled backgrounds — a flat, line-driven design language.

### Fonts

```css
--font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", "Noto Sans", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";
--font-display: "Space Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
```

- `--font-sans` is the system font stack (Tailwind v4's default, kept as-is for body/UI chrome). No `@font-face` needed, no external requests.
- `--font-display` generates `font-display` utility class for headers. Space Grotesk is loaded via `@font-face` from vendored woff2 files (see Section 4).

## Section 2: Layout Shell

### `app/views/layouts/application.html.erb`

The main layout shell, replacing the scaffold's stock `<main class="container mx-auto mt-28 px-5 flex">` wrapper:

- `<body class="bg-champagne">` — full champagne canvas
- `<head>`: title (`content_for(:title) || "Stray"`), viewport meta, apple/mobile meta tags, CSRF/CSP meta tags, favicon links (already in scaffold: `icon.png`, `icon.svg`, `apple-touch-icon`), `stylesheet_link_tag :app` with `data-turbo-track: "reload"`, `javascript_importmap_tags`
- Body structure:
  ```erb
  <body class="bg-champagne">
    <%= render "layouts/navbar" %>
    <main>
      <%= yield %>
    </main>
    <%= render "layouts/footer" %>
  </body>
  ```

### `app/views/layouts/_navbar.html.erb`

Top navigation bar, translated from `stray_video/app/views/search/_navbar.html.slim`:

- Thick charcoal bottom border (`border-b-3 border-charcoal`)
- Left side: Stray wordmark logo (`stray-logo.svg`), linking to root path
  - Responsive width: `w-0 md:w-20 lg:w-28` (collapses on mobile, matching stray_video)
  - Hidden text `<span class="hidden">Stray</span>` for accessibility
- Right side: placeholder space for future nav items (Sources, Tags, Settings). For now, minimal/empty — no search box yet (that comes with V1 features)
- Padding: `pb-2 md:pt-2 md:pl-2 pt-1` (matching stray_video)

### `app/views/layouts/_footer.html.erb`

Fixed footer, translated from `stray_video/app/views/layouts/_footer.html.slim`:

- `footer.fixed.inset-x-0.bottom-0` — fixed to viewport bottom
- Three-column flex row (`flex.w-full.px-2.py-3.space-x-8.sm:px-6.lg:px-8.text-sm`):
  - Left: contact link (placeholder email `hello@stray.feed`)
  - Grow: privacy & terms link (`privacy_and_terms_path`)
  - Right: `© Stray`
- Text styling: `text-gray-800`, links with `hover:text-black hover:underline`

### `app/views/pages/index.html.erb`

Placeholder homepage, adapted from `stray_video/app/views/pages/index.html.slim`:

- Centered single-column hero: `main.flex.flex-col.items-center.justify-center class="mt-[24vh]"`
- Logo centered, responsive width: `lg:w-5/12 md:w-6/12 w-7/12`
- Tagline below logo: "Your personal feed, ranked and tagged, your way." (replacing "Unlocking video freedom.")
  - Styling: `text-sm text-charcoal`
- No search box (that comes with V1 features)
- Footer rendered via layout

### `app/controllers/pages_controller.rb`

Minimal controller:
- `index` action — renders homepage
- `privacy_and_terms` action — renders placeholder legal page

### Routes (`config/routes.rb`)

```ruby
root "pages#index"
get "privacy_and_terms", to: "pages#privacy_and_terms"
```

## Section 3: Logo & Favicon Assets

### Logo

- Copy `stray_video/app/assets/images/stray-logo.svg` to `app/assets/images/stray-logo.svg`
- No modifications — the "STRAY" wordmark (vector paths, fill `#2a2a2a`, viewBox `0 0 357 141`)
- Referenced via `image_path("stray-logo.svg")` in navbar partial and homepage (Propshaft handles fingerprinting)

### Favicon (Rails 8 default)

- Copy `stray_video/app/assets/images/master_favicon.png` to `public/icon.png`
- Create `public/icon.svg` — a simple SVG containing the "S" letterform extracted from the wordmark's first path, with `#2a2a2a` fill, sized to a square viewBox (e.g. `0 0 100 100`). This is the favicon mark, separate from the full wordmark.
- The scaffold layout already has the link tags:
  ```erb
  <link rel="icon" href="/icon.png" type="image/png">
  <link rel="icon" href="/icon.svg" type="image/svg+xml">
  <link rel="apple-touch-icon" href="/icon.png">
  ```
- No `rails_real_favicon` gem, no favicon partial, no webmanifest/browserconfig routes

### Font assets

- Download Space Grotesk variable woff2 file from Google Fonts
- Place in `app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2`
- `@font-face` declaration in `app/assets/tailwind/application.css` (see Section 4)
- Propshaft fingerprints and serves the file; no external requests at runtime

## Section 4: CSS Structure

`app/assets/tailwind/application.css` (currently just `@import "tailwindcss"`) becomes the single source of design tokens.

```css
@import "tailwindcss";

/* Font: Space Grotesk (headers only, vendored locally) */
@font-face {
  font-family: "Space Grotesk";
  src: url("../fonts/space-grotesk/SpaceGrotesk-Variable.woff2") format("woff2-variations");
  font-weight: 300 700;
  font-display: swap;
}

/* Design tokens — ported from stray_video's tailwind.config.js */
@theme {
  /* Fonts */
  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", "Noto Sans", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";
  --font-display: "Space Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;

  /* Custom border widths (thick-border aesthetic) */
  --border-width-3: 3px;
  --border-width-6: 6px;
  --border-width-8: 8px;

  /* Charcoal */
  --color-charcoal-50: #868686;
  --color-charcoal-100: #7C7C7C;
  --color-charcoal-200: #676767;
  --color-charcoal-300: #535353;
  --color-charcoal-400: #3E3E3E;
  --color-charcoal-500: #2A2A2A;
  --color-charcoal-600: #0E0E0E;
  --color-charcoal-700: #000000;
  --color-charcoal-800: #000000;
  --color-charcoal-900: #000000;
  --color-charcoal-950: #000000;

  /* Champagne */
  --color-champagne-50: #FFFFFF;
  --color-champagne-100: #FFFFFF;
  --color-champagne-200: #FFFFFF;
  --color-champagne-300: #FFFFFF;
  --color-champagne-400: #FFFFFF;
  --color-champagne-500: #F8F2E8;
  --color-champagne-600: #EBDABD;
  --color-champagne-700: #DEC192;
  --color-champagne-800: #D1A967;
  --color-champagne-900: #C4913C;
  --color-champagne-950: #AE8135;

  /* Athens */
  --color-athens-50: #FFFFFF;
  --color-athens-100: #FFFFFF;
  --color-athens-200: #FFFFFF;
  --color-athens-300: #FFFFFF;
  --color-athens-400: #fffffe;
  --color-athens-500: #EFF0F3;
  --color-athens-600: #CFD2DB;
  --color-athens-700: #AFB4C3;
  --color-athens-800: #8F96AB;
  --color-athens-900: #6F7893;
  --color-athens-950: #626B83;

  /* Carrot */
  --color-carrot-50: #FFF8F4;
  --color-carrot-100: #FFEDDF;
  --color-carrot-200: #FFD5B6;
  --color-carrot-300: #FFBD8E;
  --color-carrot-400: #FFA665;
  --color-carrot-500: #FF8E3C;
  --color-carrot-600: #FF6D04;
  --color-carrot-700: #CB5500;
  --color-carrot-800: #933E00;
  --color-carrot-900: #5B2600;
  --color-carrot-950: #3F1A00;

  /* Cerise */
  --color-cerise-50: #F6D1DE;
  --color-cerise-100: #F3C0D1;
  --color-cerise-200: #ED9EB9;
  --color-cerise-300: #E67CA0;
  --color-cerise-400: #E05987;
  --color-cerise-500: #D9376E;
  --color-cerise-600: #B52254;
  --color-cerise-700: #861A3E;
  --color-cerise-800: #571129;
  --color-cerise-900: #280813;
  --color-cerise-950: #100308;

  /* Amber */
  --color-amber-100: #fef2d3;
  --color-amber-200: #fde5a7;
  --color-amber-300: #fdd77b;
  --color-amber-400: #fcca4f;
  --color-amber-500: #fbbd23;
  --color-amber-600: #c9971c;
  --color-amber-700: #977115;
  --color-amber-800: #644c0e;
  --color-amber-900: #322607;

  /* Mint */
  --color-mint-100: #e7f7eb;
  --color-mint-200: #ceefd6;
  --color-mint-300: #b6e6c2;
  --color-mint-400: #9ddead;
  --color-mint-500: #85d699;
  --color-mint-600: #6aab7a;
  --color-mint-700: #50805c;
  --color-mint-800: #35563d;
  --color-mint-900: #1b2b1f;

  /* Teal */
  --color-teal-100: #d6ebe7;
  --color-teal-200: #aed8cf;
  --color-teal-300: #85c4b6;
  --color-teal-400: #5db19e;
  --color-teal-500: #349d86;
  --color-teal-600: #2a7e6b;
  --color-teal-700: #1f5e50;
  --color-teal-800: #153f36;
  --color-teal-900: #0a1f1b;

  /* Sky */
  --color-sky-100: #e5eafc;
  --color-sky-200: #cbd6fa;
  --color-sky-300: #b1c1f7;
  --color-sky-400: #97adf5;
  --color-sky-500: #7d98f2;
  --color-sky-600: #647ac2;
  --color-sky-700: #4b5b91;
  --color-sky-800: #323d61;
  --color-sky-900: #191e30;

  /* Cotton */
  --color-cotton-100: #f6defc;
  --color-cotton-200: #ecbcf8;
  --color-cotton-300: #e39bf5;
  --color-cotton-400: #d979f1;
  --color-cotton-500: #d058ee;
  --color-cotton-600: #a646be;
  --color-cotton-700: #7d358f;
  --color-cotton-800: #53235f;
  --color-cotton-900: #2a1230;
}
```

**Notes:**
- `--font-sans` is the system font stack — Tailwind v4's default, kept as-is for body/UI chrome. No `@font-face` needed.
- `--font-display` generates `font-display` utility class for headers (e.g. `<h1 class="font-display">`).
- All color ramps translate from the JS config's nested objects into flat `--color-{name}-{shade}` variables.
- Tailwind v4 reads these `@theme` vars and auto-generates `bg-champagne-500`, `text-carrot-600`, `border-charcoal`, etc.
- No `@layer` blocks needed, no custom CSS beyond `@font-face` and `@theme`.
- `app/assets/stylesheets/application.css` stays minimal (Propshaft manifest entry, loaded alongside the Tailwind build).

## Section 5: File Inventory

### New files

| File | Purpose |
|---|---|
| `app/assets/images/stray-logo.svg` | Logo wordmark (copied from stray_video) |
| `app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2` | Header font, vendored locally |
| `app/views/layouts/_navbar.html.erb` | Top navigation bar partial |
| `app/views/layouts/_footer.html.erb` | Fixed footer partial |
| `app/views/pages/index.html.erb` | Placeholder homepage |
| `app/views/pages/privacy_and_terms.html.erb` | Placeholder legal page |
| `app/controllers/pages_controller.rb` | Homepage controller |
| `public/icon.png` | Favicon PNG (derived from stray_video's master_favicon.png) |
| `public/icon.svg` | Favicon SVG (derived from the wordmark) |

### Modified files

| File | Changes |
|---|---|
| `app/assets/tailwind/application.css` | Add `@font-face`, `@theme` block with all color ramps, border widths, font tokens |
| `app/views/layouts/application.html.erb` | Replace scaffold `<main>` with navbar + yield + footer structure |
| `config/routes.rb` | Add `root "pages#index"` and `get "privacy_and_terms"` route |

### Deleted

None.

### Unchanged (already correct from scaffold)

- `app/assets/stylesheets/application.css` — stays minimal
- `config/importmap.rb` — no JS additions needed
- `app/javascript/application.js` — stays as Hotwire import
- `Gemfile` — no new gems needed
- `.github/workflows/ci.yml` — already covers lint/test/security

## Section 6: Testing & Verification

### What to test

- `PagesController#index` renders the homepage with the logo image tag present
- `PagesController#privacy_and_terms` renders without error
- Root route (`/`) returns 200 and contains the tagline text
- Favicon assets exist at `public/icon.png` and `public/icon.svg`
- Logo SVG asset exists and is servable

### Tests to write

`test/controllers/pages_controller_test.rb`:
- Test: homepage GET `/` returns 200 and response body contains "Stray" (logo alt text)
- Test: privacy_and_terms GET `/privacy_and_terms` returns 200

Keep it minimal — this is a static foundation, no complex assertions needed.

### Verification commands

- `bin/rails test` — Minitest controller tests
- `bin/rails server` + manual check that `/` loads with champagne background, logo visible, footer fixed, navbar rendering
- `bin/rubocop` — lint passes
- `bin/brakeman` — security scan passes (no secrets, no injection risks in static pages)

### CI coverage

The existing `.github/workflows/ci.yml` already runs RuboCop, Brakeman, bundler-audit, Minitest, and system tests. No CI changes needed.
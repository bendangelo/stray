# Design Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the visual identity from `~/Projects/stray_video` into the Stray project — design tokens, layout shell, logo, favicon, fonts, and a placeholder homepage.

**Architecture:** Tailwind v4 `@theme` CSS variables replace the stray_video `tailwind.config.js` approach. ERB templates replace Slim. System font stack for body, Space Grotesk vendored locally for headers. Rails 8 default favicon approach (no gem).

**Tech Stack:** Rails 8.1, Ruby 4.0.5, Tailwind v4.3.3 (via `tailwindcss-rails`), Propshaft, Hotwire, Importmap, Minitest

**Spec:** `docs/superpowers/specs/2026-08-12-design-foundation-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `app/assets/tailwind/application.css` | Modify | `@font-face` for Space Grotesk + `@theme` block with all design tokens |
| `app/assets/images/stray-logo.svg` | Create | Logo wordmark (copied from stray_video) |
| `app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2` | Create | Header font, vendored locally |
| `app/views/layouts/application.html.erb` | Modify | Replace scaffold body with navbar + yield + footer, add `bg-champagne` |
| `app/views/layouts/_navbar.html.erb` | Create | Top navigation bar with logo |
| `app/views/layouts/_footer.html.erb` | Create | Fixed footer with contact/legal/copyright |
| `app/views/pages/index.html.erb` | Create | Placeholder homepage with logo + tagline |
| `app/views/pages/privacy_and_terms.html.erb` | Create | Placeholder legal page |
| `app/controllers/pages_controller.rb` | Create | Homepage + privacy_and_terms actions |
| `config/routes.rb` | Modify | Add root + privacy_and_terms routes |
| `public/icon.png` | Create | Favicon PNG (copied from stray_video's master_favicon.png) |
| `public/icon.svg` | Create | Favicon SVG (S letterform from wordmark) |
| `test/controllers/pages_controller_test.rb` | Create | Controller tests for homepage + privacy_and_terms |

---

## Task 1: Copy Logo and Favicon Assets

**Files:**
- Create: `app/assets/images/stray-logo.svg`
- Create: `public/icon.png`
- Create: `public/icon.svg`

- [ ] **Step 1: Copy the logo SVG from stray_video**

```bash
cp ~/Projects/stray_video/app/assets/images/stray-logo.svg app/assets/images/stray-logo.svg
```

- [ ] **Step 2: Copy the favicon PNG from stray_video**

```bash
cp ~/Projects/stray_video/app/assets/images/master_favicon.png public/icon.png
```

- [ ] **Step 3: Create the favicon SVG (S letterform from the wordmark)**

Write `public/icon.svg` with this content — a square 100x100 viewBox containing the "S" path extracted from the wordmark, filled with `#2a2a2a`:

```svg
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100" height="100" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <path d="M28.8,78.5c16.4,0 27.1,-8.7 27.1,-22.1c0,-13.3 -10.3,-18.2 -23.3,-21.3l-5.6,-1.4c-10,-2.5 -16,-5.2 -16,-13.3c0,-8.1 6.5,-12.6 16.5,-12.6c10.4,0 17.9,4.5 17.9,15.4l0,4.5l8.9,0l0,-4.5c0,-15.4 -11.7,-23.3 -26.9,-23.3c-15.2,0 -25.5,7.9 -25.5,20.6c0,12.7 9.1,17.9 22.5,21.2l5.6,1.4c10.1,2.4 16.9,5.2 16.9,13.5c0,8.1 -6.4,14 -18.2,14c-11.5,0 -19.7,-5.9 -19.7,-18.6l0,-2.3l-8.9,0l0,2.3c0,17.7 12.1,26.4 28.6,26.4Z" style="fill:#2a2a2a;fill-rule:nonzero;"/>
</svg>
```

- [ ] **Step 4: Verify the files exist**

```bash
ls -la app/assets/images/stray-logo.svg public/icon.png public/icon.svg
```

Expected: all three files listed with non-zero sizes.

- [ ] **Step 5: Commit**

```bash
git add app/assets/images/stray-logo.svg public/icon.png public/icon.svg
git commit -m "feat: add logo and favicon assets

Port stray-logo.svg wordmark from stray_video.
Use Rails 8 default favicon approach: public/icon.png (from
master_favicon.png) + public/icon.svg (S letterform from wordmark)."
```

---

## Task 2: Download and Vendor Space Grotesk Font

**Files:**
- Create: `app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2`

- [ ] **Step 1: Create the fonts directory and download Space Grotesk variable woff2**

```bash
mkdir -p app/assets/fonts/space-grotesk
curl -L -o app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2 \
  "https://github.com/fontsquirrel/Space-Grotesk/raw/master/fonts/variable/SpaceGrotesk[wght].woff2"
```

Note: If the URL doesn't work, download from Google Fonts API or fontsquirrel.com. The file is a variable woff2 covering weights 300–700. The exact source URL may vary — the key requirement is a single variable woff2 file named `SpaceGrotesk-Variable.woff2` in `app/assets/fonts/space-grotesk/`.

- [ ] **Step 2: Verify the font file exists and is non-trivial in size**

```bash
ls -la app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2
```

Expected: file exists, size > 20KB (variable woff2 with multiple weights).

- [ ] **Step 3: Commit**

```bash
git add app/assets/fonts/space-grotesk/SpaceGrotesk-Variable.woff2
git commit -m "feat: vendor Space Grotesk variable font locally

Header font for the design system. No external runtime requests.
Variable woff2 covers weights 300-700."
```

---

## Task 3: Write Design Tokens CSS

**Files:**
- Modify: `app/assets/tailwind/application.css`

- [ ] **Step 1: Replace the contents of `app/assets/tailwind/application.css`**

The file currently contains just `@import "tailwindcss";`. Replace it entirely with:

```css
@import "tailwindcss";

@font-face {
  font-family: "Space Grotesk";
  src: url("../fonts/space-grotesk/SpaceGrotesk-Variable.woff2") format("woff2-variations");
  font-weight: 300 700;
  font-display: swap;
}

@theme {
  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", "Noto Sans", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";
  --font-display: "Space Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;

  --border-width-3: 3px;
  --border-width-6: 6px;
  --border-width-8: 8px;

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

  --color-amber-100: #fef2d3;
  --color-amber-200: #fde5a7;
  --color-amber-300: #fdd77b;
  --color-amber-400: #fcca4f;
  --color-amber-500: #fbbd23;
  --color-amber-600: #c9971c;
  --color-amber-700: #977115;
  --color-amber-800: #644c0e;
  --color-amber-900: #322607;

  --color-mint-100: #e7f7eb;
  --color-mint-200: #ceefd6;
  --color-mint-300: #b6e6c2;
  --color-mint-400: #9ddead;
  --color-mint-500: #85d699;
  --color-mint-600: #6aab7a;
  --color-mint-700: #50805c;
  --color-mint-800: #35563d;
  --color-mint-900: #1b2b1f;

  --color-teal-100: #d6ebe7;
  --color-teal-200: #aed8cf;
  --color-teal-300: #85c4b6;
  --color-teal-400: #5db19e;
  --color-teal-500: #349d86;
  --color-teal-600: #2a7e6b;
  --color-teal-700: #1f5e50;
  --color-teal-800: #153f36;
  --color-teal-900: #0a1f1b;

  --color-sky-100: #e5eafc;
  --color-sky-200: #cbd6fa;
  --color-sky-300: #b1c1f7;
  --color-sky-400: #97adf5;
  --color-sky-500: #7d98f2;
  --color-sky-600: #647ac2;
  --color-sky-700: #4b5b91;
  --color-sky-800: #323d61;
  --color-sky-900: #191e30;

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

- [ ] **Step 2: Build Tailwind to verify the CSS compiles**

```bash
bin/rails tailwindcss:build
```

Expected: command succeeds, no errors. The build output goes to `app/assets/builds/tailwind.css`.

- [ ] **Step 3: Commit**

```bash
git add app/assets/tailwind/application.css
git commit -m "feat: add design tokens via Tailwind v4 @theme

Port all 10 color ramps (charcoal, champagne, athens, carrot, cerise,
amber, mint, teal, sky, cotton) from stray_video's tailwind.config.js.
Add custom border widths (3px, 6px, 8px) for the thick-border aesthetic.
Add @font-face for Space Grotesk (headers, vendored locally).
System font stack for body (--font-sans, no external requests)."
```

---

## Task 4: Create the PagesController

**Files:**
- Create: `app/controllers/pages_controller.rb`
- Create: `test/controllers/pages_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/controllers/pages_controller_test.rb`:

```ruby
require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "GET root renders homepage with logo" do
    get root_path

    assert_response :success
    assert_select "img[alt=?]", "Stray Logo"
  end

  test "GET privacy_and_terms renders successfully" do
    get privacy_and_terms_path

    assert_response :success
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: FAIL with `No route matches [GET] "/"` or `uninitialized constant PagesController` — because the controller and routes don't exist yet.

- [ ] **Step 3: Create the controller**

Create `app/controllers/pages_controller.rb`:

```ruby
class PagesController < ApplicationController
  def index
  end

  def privacy_and_terms
  end
end
```

- [ ] **Step 4: Add routes (temporarily, to make the test pass)**

Modify `config/routes.rb` — replace the entire file with:

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#index"
  get "privacy_and_terms", to: "pages#privacy_and_terms"
end
```

- [ ] **Step 5: Run test to verify it still fails (views don't exist yet)**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: FAIL with `Missing template pages/index` — controller exists but views don't. This is expected; we create views in Task 5.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/pages_controller.rb config/routes.rb test/controllers/pages_controller_test.rb
git commit -m "feat: add PagesController with homepage and privacy_and_terms

Controller renders static pages. Routes: root -> pages#index,
GET /privacy_and_terms -> pages#privacy_and_terms.

Tests assert 200 responses and logo alt text presence."
```

---

## Task 5: Create Views (Homepage, Privacy & Terms)

**Files:**
- Create: `app/views/pages/index.html.erb`
- Create: `app/views/pages/privacy_and_terms.html.erb`

- [ ] **Step 1: Create the homepage view**

Create `app/views/pages/index.html.erb`:

```erb
<main class="flex flex-col items-center justify-center mt-[24vh]">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-5/12 md:w-6/12 w-7/12" %>

  <div class="mt-7 flex lg:w-7/12 md:w-8/12 w-11/12">
    <p class="px-2 py-1 text-sm text-charcoal">Your personal feed, ranked and tagged, your way.</p>
  </div>
</main>
```

- [ ] **Step 2: Create the privacy & terms placeholder view**

Create `app/views/pages/privacy_and_terms.html.erb`:

```erb
<main class="container mx-auto mt-28 px-5 max-w-2xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Privacy & Terms</h1>

  <p class="text-charcoal leading-relaxed">
    Stray is a self-hosted personal feed reader. Your data stays on your server.
    This page will be updated with the full privacy policy and terms of service.
  </p>
</main>
```

- [ ] **Step 3: Run the controller test to verify it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: PASS — both tests green. The homepage renders with the logo image (alt text "Stray Logo"), and privacy_and_terms renders successfully.

- [ ] **Step 4: Commit**

```bash
git add app/views/pages/
git commit -m "feat: add homepage and privacy_and_terms views

Homepage: centered Stray logo + tagline, matching stray_video hero layout.
Privacy & Terms: placeholder page using font-display for the heading."
```

---

## Task 6: Create Layout Partials (Navbar and Footer)

**Files:**
- Create: `app/views/layouts/_navbar.html.erb`
- Create: `app/views/layouts/_footer.html.erb`

- [ ] **Step 1: Create the navbar partial**

Create `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="pb-2 md:pt-2 md:pl-2 pt-1 border-b-3 border-charcoal">
  <div class="flex pl-2 mx-auto md:pl-4 lg:pl-16 lg:ml-2">
    <div class="flex items-center lg:mr-4 md:mr-2 mr-1">
      <%= link_to root_path, tabindex: "-1" do %>
        <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "w-0 md:w-20 lg:w-28" %>
        <span class="hidden">Stray</span>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 2: Create the footer partial**

Create `app/views/layouts/_footer.html.erb`:

```erb
<footer class="fixed inset-x-0 bottom-0">
  <div class="flex w-full px-2 py-3 space-x-8 sm:px-6 lg:px-8 text-sm">
    <div class="shrink">
      <%= link_to "Contact", "mailto:hello@stray.feed", class: "text-gray-800 mt-1 hover:text-black hover:underline" %>
    </div>
    <div class="grow">
      <%= link_to "Privacy & Terms", privacy_and_terms_path, class: "text-gray-800 mt-1 hover:text-black hover:underline" %>
    </div>
    <span class="text-gray-800">&copy; Stray</span>
  </div>
</footer>
```

- [ ] **Step 3: Run tests to verify nothing is broken**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: PASS — tests still green. The partials aren't rendered yet (the layout doesn't include them), but the files exist and are valid ERB.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/_navbar.html.erb app/views/layouts/_footer.html.erb
git commit -m "feat: add navbar and footer layout partials

Navbar: logo with responsive width (collapses on mobile), thick
charcoal bottom border. Footer: fixed to viewport bottom with
contact, privacy & terms, and copyright links."
```

---

## Task 7: Update the Application Layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Replace the layout body with the new shell structure**

Modify `app/views/layouts/application.html.erb`. The current `<body>` section is:

```erb
  <body>
    <main class="container mx-auto mt-28 px-5 flex">
      <%= yield %>
    </main>
  </body>
```

Replace it with:

```erb
  <body class="bg-champagne">
    <%= render "layouts/navbar" %>
    <main>
      <%= yield %>
    </main>
    <%= render "layouts/footer" %>
  </body>
```

The full file should now read:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "Stray" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Stray">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <%# Enable PWA manifest for installable apps (make sure to enable in config/routes.rb too!) %>
    <%#= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%# Includes all stylesheet files in app/assets/stylesheets %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="bg-champagne">
    <%= render "layouts/navbar" %>
    <main>
      <%= yield %>
    </main>
    <%= render "layouts/footer" %>
  </body>
</html>
```

- [ ] **Step 2: Run tests to verify the layout renders correctly**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: PASS — both tests green. The navbar and footer partials now render within the layout. The homepage test checks for `img[alt="Stray Logo"]` which appears in both the navbar and the homepage content.

- [ ] **Step 3: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass (the two pages controller tests plus any existing scaffold tests).

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: update application layout with navbar and footer

Replace scaffold main container with champagne background,
navbar partial, yield, and footer partial. Favicon links
and stylesheet/importmap tags unchanged from scaffold."
```

---

## Task 8: Lint and Security Verification

**Files:**
- No file changes — verification only

- [ ] **Step 1: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses. If offenses are found, fix them (the code in this plan follows omakase style, but adjust if RuboCop flags anything).

- [ ] **Step 2: Run Brakeman**

```bash
bin/brakeman
```

Expected: no security warnings. The static pages and controller have no injection vectors.

- [ ] **Step 3: Run the full test suite one final time**

```bash
bin/rails test
```

Expected: all tests pass.

- [ ] **Step 4: Manual visual check (optional but recommended)**

```bash
bin/rails server
```

Open `http://localhost:3000` in a browser and verify:
- Champagne (`#F8F2E8`) background fills the page
- Stray logo wordmark is centered on the homepage
- Tagline "Your personal feed, ranked and tagged, your way." is visible below the logo
- Navbar appears at the top with the logo and a thick charcoal bottom border
- Footer is fixed to the bottom of the viewport with Contact, Privacy & Terms, and © Stray
- Favicon appears in the browser tab

If any visual element is wrong, fix the relevant file before committing.

---

## Task 9: Final Commit (if any fixes were needed in Task 8)

- [ ] **Step 1: If Task 8 required any fixes, commit them**

```bash
git add -A
git commit -m "fix: address lint/style issues from design foundation verification"
```

If no fixes were needed, skip this task entirely.

---

## Verification Summary

After all tasks are complete, verify:

| Check | Command | Expected |
|---|---|---|
| Tests pass | `bin/rails test` | All green |
| Lint passes | `bin/rubocop` | No offenses |
| Security scan passes | `bin/brakeman` | No warnings |
| Tailwind builds | `bin/rails tailwindcss:build` | No errors |
| Homepage renders | `bin/rails server` + visit `/` | Champagne bg, logo, tagline, navbar, footer |
| Favicon loads | Check browser tab | Icon visible |
| Font loads | Inspect headers in browser | Space Grotesk served from local assets, no external font requests |
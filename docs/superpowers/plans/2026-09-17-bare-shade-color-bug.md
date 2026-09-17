# Bare-Shade Color Bug Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 408 bare-shade color utilities (`text-charcoal`, `border-charcoal`, `text-cerise`, `bg-champagne`, etc.) actually render by adding missing base color variables to the Tailwind v4 `@theme` block.

**Architecture:** One CSS-only change: add 9 unnumbered `--color-*` variables to the `@theme` block in `app/assets/tailwind/application.css` (values mirror each scale's -500 step, following the existing `--color-mint` precedent). Tailwind v4 then generates every bare utility and its opacity-modifier forms at the next build. Verify with a system test that asserts computed styles, plus a compiled-CSS grep step.

**Tech Stack:** Rails 8, Tailwind CSS v4 via `tailwindcss-rails` (`bin/rails tailwindcss:build`), Minitest + Capybara (Cuprite/headless Chrome).

**Spec:** `docs/superpowers/specs/2026-09-17-bare-shade-color-bug-design.md`

**Background for the engineer (why this is a bug):** In Tailwind v4, a utility like `text-charcoal` is only generated if a `--color-charcoal` variable exists in `@theme`. This app's `@theme` defines only *numbered* shades (`--color-charcoal-500: #2A2A2A` etc.), so all bare utilities are silently skipped at build time. Result: `<body class="bg-champagne">` renders transparent/white, `text-cerise` danger text renders in browser-default blue/black, the mobile drawer backdrop (`bg-charcoal/50`) is invisible. Only `bg-mint` works because `--color-mint: #85d699` exists unnumbered at application.css:88.

**IMPORTANT — how tests must run:** System tests require the compiled stylesheet to reflect source changes. The test harness does NOT rebuild Tailwind. After editing `app/assets/tailwind/application.css`, ALWAYS run `bin/rails tailwindcss:build` before running system tests, or the test will exercise the stale CSS and lie to you.

---

### Task 1: Failing system test asserting bare utilities render

**Files:**
- Create: `test/system/bare_shade_colors_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/system/bare_shade_colors_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class BareShadeColorsTest < ApplicationSystemTestCase
  test "body renders the champagne background from bg-champagne" do
    visit root_path

    bg = find("body").evaluate_script("getComputedStyle(this).backgroundColor")
    assert_equal "rgb(248, 242, 232)", bg,
      "body should have champagne-500 (#F8F2E8) background once bg-champagne resolves"
  end

  test "bare text-charcoal resolves to charcoal-500 ink" do
    visit about_path

    copy = find("main p", match: :first)
    color = copy.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(42, 42, 42)", color,
      "text-charcoal should resolve to #2A2A2A (charcoal-500)"
  end

  test "mobile drawer backdrop is dimmed by bg-charcoal/50" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    assert_selector "aside#sidebar:not(.-translate-x-full)", wait: 5

    backdrop = find("[data-sidebar-target='backdrop']")
    bg = backdrop.evaluate_script("getComputedStyle(this).backgroundColor")
    refute_equal "rgba(0, 0, 0, 0)", bg,
      "backdrop must not be fully transparent — bg-charcoal/50 is currently missing from the build"
  end

  test "flash alert uses cerise danger color" do
    visit new_session_path
    fill_in "email", with: "nope@example.com"
    fill_in "password", with: "wrong"
    click_on "Sign in"

    alert = find("#alert")
    color = alert.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(217, 55, 110)", color,
      "flash alert text-cerise should resolve to #D9376E (cerise-500)"
  end
end
```

Notes on the test design:
- `about_path` (pages#privacy_and_terms) needs no authentication and its `<p class="text-charcoal">` is the first `main p` on the page — a stable probe for the bare utility.
- The backdrop test intentionally asserts only non-transparency (not an exact alpha value) so it stays robust if the alpha compositing format varies across Chrome versions.
- The sign-in path exercises the real flash rendering (`app/views/layouts/application.html.erb:47`) using the actual failed-login flow — no fixture hacking.
- `sign_in_as` and `resize_to_mobile` are existing helpers (`test/test_helpers/session_test_helper.rb:2`, `test/application_system_test_case.rb:11`).

- [ ] **Step 2: Build the current CSS so the test exercises today's real output**

Run: `bin/rails tailwindcss:build`
Expected: `Done in ...ms` (no errors)

- [ ] **Step 3: Run the test to verify it fails**

Run: `bin/rails test test/system/bare_shade_colors_test.rb`
Expected: FAILURES — at minimum the body-background and ink tests fail (`rgb(255, 255, 255)` or `rgba(0, 0, 0, 0)` instead of `rgb(248, 242, 232)` / `rgb(42, 42, 42)`); backdrop and flash tests fail with the transparency/default-color assertions. If all four pass, STOP — the bug premise is wrong; investigate before proceeding.

- [ ] **Step 4: Commit the failing test**

```bash
git add test/system/bare_shade_colors_test.rb
git commit -m "test: bare-shade color utilities do not render"
```

(Committing the red test first documents the bug independently of the fix.)

---

### Task 2: Add the missing base color variables to @theme

**Files:**
- Modify: `app/assets/tailwind/application.css:10-128` (the `@theme` block)

- [ ] **Step 1: Add base variables to the @theme block**

In `app/assets/tailwind/application.css`, inside the existing `@theme { ... }` block, immediately after the `--border-width-*` lines (after line 16, i.e. after `--border-width-8: 8px;`), insert:

```css
  --color-charcoal: #2A2A2A;
  --color-champagne: #F8F2E8;
  --color-athens: #fffffe;
  --color-carrot: #FF8E3C;
  --color-cerise: #D9376E;
  --color-amber: #fbbd23;
  --color-teal: #349d86;
  --color-sky: #7d98f2;
  --color-cotton: #d058ee;
```

Do NOT touch any numbered shade (`--color-charcoal-500` etc. stays exactly as is) and do NOT touch the existing `--color-mint: #85d699` at line 88 — it is already correct.

Each value mirrors the -500 (primary) step of its scale, matching the mint precedent: charcoal-500 `#2A2A2A`, champagne-500 `#F8F2E8`, athens-400 `#fffffe` (the card surface — athens' -400 is its defined surface tone; -500 is a hover grey, so the base is -400 here), carrot-500 `#FF8E3C`, cerise-500 `#D9376E`, amber-500 `#fbbd23`, teal-500 `#349d86`, sky-500 `#7d98f2`, cotton-500 `#d058ee`.

- [ ] **Step 2: Rebuild the compiled CSS**

Run: `bin/rails tailwindcss:build`
Expected: `Done in ...ms`

- [ ] **Step 3: Verify the bare utilities now exist in the build output**

Run:

```bash
grep -c "text-charcoal{" app/assets/builds/tailwind.css
grep -c "bg-champagne{" app/assets/builds/tailwind.css
grep -o "bg-charcoal\/50[^{]*{[^}]*}" app/assets/builds/tailwind.css | head -1
grep -o "text-cerise{[^}]*}" app/assets/builds/tailwind.css | head -1
```

Expected: first two print non-zero counts (≥1); the third prints a rule containing `color-mix` (Tailwind v4 compiles `/50` alpha via `color-mix(in oklab, var(--color-charcoal) 50%, transparent)`); the fourth prints `.text-cerise{color:var(--color-cerise)}`.

- [ ] **Step 4: Run the Task 1 test to verify it passes**

Run: `bin/rails test test/system/bare_shade_colors_test.rb`
Expected: 4 runs, 0 failures, 0 errors

- [ ] **Step 5: Commit the fix**

```bash
git add app/assets/tailwind/application.css
git commit -m "fix: define base color tokens so bare-shade utilities render"
```

---

### Task 3: Regression sweep

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: 0 failures, 0 errors. Pay attention to:
- `test/system/sidebar_background_test.rb` — it asserts the sidebar background differs from the body; the body now actually has `#F8F2E8` while the sidebar is `champagne-50` (`#FFFFFF`), so it still differs, differently.
- `test/system/item_state_visuals_test.rb` — asserts `.bg-mint.rounded-full` (unseen dot); the dot's `ring-charcoal/50` now also renders, which only adds a ring, doesn't affect those selectors.
- `test/system/feed_flow_test.rb` — asserts `.bg-carrot-500` badge in sidebar; unaffected.

If any system test fails because a previously-invisible element is now visible/colored, read the failure, and fix the VIEW markup only if it was relying on the broken rendering (e.g. something accidentally designed against a transparent backdrop). Do not weaken assertions to make tests pass.

- [ ] **Step 2: Run the lint and security passes**

Run: `bin/rubocop`
Expected: no offenses (CSS file isn't linted, but confirm nothing else was touched)

- [ ] **Step 3: Full CI pass**

Run: `bin/ci`
Expected: all green

- [ ] **Step 4: Manual visual smoke check (optional but recommended)**

Run: `bin/dev` and open the app. Confirm:
- Body is warm champagne, not white.
- Delete/danger text (e.g. "Delete" in a source dropdown) is pink-red, not blue/black.
- On a narrow window (<768px), opening the sidebar dims the page behind the drawer.
- Source letter avatars (a source with no icon) show a dark square with white letter.

Then stop the server. No commit — no code changed in this task.

---

## Self-Review (performed by plan author)

1. **Spec coverage:** Spec's fix (9 `@theme` variables) → Task 2. Spec's testing requirement (compiled-CSS grep + system test on body/backdrop/cerise) → Task 2 Step 3 + Task 1. Spec's "suite stays green" → Task 3. Off-palette sweep explicitly deferred to the design-system plan — not covered here, correctly.
2. **Placeholders:** none — every step has exact code or exact commands with expected output.
3. **Consistency:** `rgb(248, 242, 232)` = `#F8F2E8` (champagne-500), `rgb(42, 42, 42)` = `#2A2A2A` (charcoal-500), `rgb(217, 55, 110)` = `#D9376E` (cerise-500) — all match the hex values in Task 2 and the spec.
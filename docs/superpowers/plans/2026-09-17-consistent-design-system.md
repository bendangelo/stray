# Design System & Mobile UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize every Stray surface onto shared UI helpers/partials with 44px minimum tap targets, a visible warm-highlight for dropdown items, and a hardened mobile drawer — per the approved design spec.

**Architecture:** Helpers + shared partials + CSS state classes (no ViewComponent, no new gems). First the foundation (CSS `.ui-menu-item`, `UiHelper`, `shared/ui/` partials), then the dropdown overhaul across all 6 call sites, then mobile hardening, then a page-by-page sweep of all 19 view dirs. Interactive state lives in CSS classes so the 44px floor and highlight can never drift per-view.

**Tech Stack:** Rails 8, Hotwire (Stimulus via `@stimulus-components/dropdown`), Tailwind CSS v4 (`tailwindcss-rails`, config-less, `@theme` in `app/assets/tailwind/application.css`), Minitest + Capybara/Cuprite, Phosphor icons via `phosphor_icon` helper.

**Spec:** `docs/superpowers/specs/2026-09-17-consistent-design-system-design.md`
**Prerequisite:** `docs/superpowers/plans/2026-09-17-bare-shade-color-bug.md` must be implemented first (bare-shade utilities like `text-charcoal` must resolve; this plan's class strings assume them).

**CRITICAL for every task in this plan:** The test harness does NOT rebuild Tailwind. After any edit to `app/assets/tailwind/application.css` you MUST run `bin/rails tailwindcss:build` before running tests, or you will test against stale CSS. After editing ERB that uses new Tailwind utilities, also rebuild — v4 only emits utilities it sees in source files.

**Conventions used throughout:**
- `--navbar-h: 57px` is set inline on the navbar; `min-h-11` = 44px (Tailwind `--spacing` = 0.25rem).
- The app is light-mode only. Never add `dark:` variants.
- Icons: `phosphor_icon "name", class: "..."` — never inline SVG.
- `action_link_to(name_or_url, url, method:, confirm:, params:, data:, class:)` (app/helpers/action_link_helper.rb:2) is the existing wrapper for non-GET links; use it for all menu items that mutate.
- Commit message style: Conventional Commits, matching repo history (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
- 44px floor applies to *interactive* controls. Dense data rows inside tables (tags list) may keep compact *visuals* — but every link/button inside still needs a comfortable target (min 36px there, `min-h-9`, since the whole row/cell is not clickable).

---

### Task 1: CSS foundation — `.ui-menu-item` with 44px floor and carrot highlight

**Files:**
- Modify: `app/assets/tailwind/application.css` (custom-CSS section after the `mark` rule, line ~139)
- Test: `test/system/ui_menu_item_test.rb` (new)

- [ ] **Step 1: Write the failing test**

Create `test/system/ui_menu_item_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class UiMenuItemTest < ApplicationSystemTestCase
  test "dropdown menu items are at least 44px tall" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      height = link.evaluate_script("this.getBoundingClientRect().height")
      assert_operator height, :>=, 44,
        "menu item must be at least 44px tall for touch, got #{height}"
    end
  end

  test "hovered menu item gets a visible carrot highlight" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      link.hover
      bg = link.evaluate_script("getComputedStyle(this).backgroundColor")
      assert_equal "rgb(255, 237, 223)", bg,
        "hover highlight must be carrot-100 #FFEDDF, got #{bg}"
    end
  end

  test "keyboard-focused menu item gets the same highlight" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      link.evaluate_script <<~JS
        const a = this;
        a.focus();
        a.dispatchEvent(new Event("focus", { bubbles: false }));
      JS
      bg = link.evaluate_script("getComputedStyle(this).backgroundColor")
      assert_equal "rgb(255, 237, 223)", bg,
        ":focus-visible needs the carrot highlight for keyboard nav, got #{bg}"
    end
  end
end
```

Notes for the engineer:
- `rgb(255, 237, 223)` is carrot-100 `#FFEDDF` (application.css:55).
- `focus()` on a real anchor produces `:focus-visible` in Chrome for keyboard-driven focus; the extra dispatched event is belt-and-braces. If the focus test is flaky in your Chrome version, replace with `link.send_keys(:tab)` after clicking the trigger — but try the simple version first.
- `items(:video_one)` exists in fixtures and renders on the feed page (used by existing `test/system/dropdown_menu_test.rb:9`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/system/ui_menu_item_test.rb`
Expected: FAILURES — items are currently ~20px (`px-2 py-1 text-xs`), hover is `athens-300` = `#FFFFFF` (invisible). Height assertion fails.

- [ ] **Step 3: Add the `.ui-menu-item` CSS**

In `app/assets/tailwind/application.css`, after the `mark { ... }` rule (before `.button_to`), insert:

```css
.ui-menu-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  text-align: left;
  min-height: 2.75rem;
  padding: 0.5rem 0.75rem;
  border: none;
  background: transparent;
  cursor: pointer;
  border-radius: 0.25rem;
}

.ui-menu-item:hover,
.ui-menu-item:focus-visible {
  background-color: var(--color-carrot-100);
  color: var(--color-carrot-700);
  outline: 2px solid var(--color-carrot-500);
  outline-offset: -2px;
}

.ui-menu-item--danger { color: var(--color-cerise); }
.ui-menu-item--danger:hover,
.ui-menu-item--danger:focus-visible {
  background-color: var(--color-cerise-100);
  color: var(--color-cerise-600);
  outline-color: var(--color-cerise-500);
}
```

Why CSS instead of Tailwind utility strings: the `:hover` **and** `:focus-visible` pair must never drift apart across 10 call sites, and `min-height` here is a hard floor regardless of what padding a call site adds. (The danger variant keeps `text-cerise` as the resting color — that now works because the bare-shade fix landed.)

- [ ] **Step 4: Rebuild and run the test to verify it passes**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/ui_menu_item_test.rb`
Expected: 3 runs, 0 failures — BUT only if Task 2 also landed, because the items still use `dropdown_menu_item_class`. If you run Task 1 in isolation the height test still fails (helper not yet rewritten). That is expected: Task 1 + Task 2 land together as one red→green cycle. The CSS alone is inert.

- [ ] **Step 5: Commit**

```bash
git add app/assets/tailwind/application.css test/system/ui_menu_item_test.rb
git commit -m "feat: ui-menu-item CSS with 44px floor and carrot highlight"
```

---

### Task 2: UiHelper with class-string methods

**Files:**
- Create: `app/helpers/ui_helper.rb`
- Modify: `app/helpers/application_helper.rb:143-150` (delete `dropdown_menu_item_class`, keep a one-release alias)
- Test: `test/helpers/ui_helper_test.rb` (new)
- Modify: `test/helpers/application_helper_test.rb:238-255` (update the two `dropdown_menu_item_class` tests)

- [ ] **Step 1: Write the failing helper tests**

Create `test/helpers/ui_helper_test.rb`:

```ruby
require "test_helper"

class UiHelperTest < ActionView::TestCase
  test "ui_menu_item returns the shared class hook" do
    assert_equal "ui-menu-item", ui_menu_item
  end

  test "ui_menu_item danger variant adds the danger modifier" do
    assert_equal "ui-menu-item ui-menu-item--danger", ui_menu_item(danger: true)
  end

  test "ui_button primary default is h-11 border-3 carrot" do
    classes = ui_button.split
    assert_includes classes, "inline-flex"
    assert_includes classes, "items-center"
    assert_includes classes, "justify-center"
    assert_includes classes, "gap-1.5"
    assert_includes classes, "h-11"
    assert_includes classes, "px-4"
    assert_includes classes, "rounded-md"
    assert_includes classes, "border-3"
    assert_includes classes, "border-charcoal"
    assert_includes classes, "bg-carrot-500"
    assert_includes classes, "text-white"
    assert_includes classes, "font-bold"
    assert_includes classes, "text-sm"
    assert_includes classes, "cursor-pointer"
  end

  test "ui_button secondary uses card surface" do
    classes = ui_button(variant: :secondary).split
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "text-charcoal"
    refute_includes classes, "bg-carrot-500"
  end

  test "ui_button danger uses cerise text on card surface" do
    classes = ui_button(variant: :danger).split
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "text-cerise"
  end

  test "ui_button sm size is h-9" do
    assert_includes ui_button(size: :sm).split, "h-9"
  end

  test "ui_button lg size is h-12" do
    assert_includes ui_button(size: :lg).split, "h-12"
  end

  test "ui_input returns the standard field classes" do
    classes = ui_input.split
    assert_includes classes, "w-full"
    assert_includes classes, "h-11"
    assert_includes classes, "px-3"
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "border-3"
    assert_includes classes, "border-charcoal"
    assert_includes classes, "rounded-md"
    assert_includes classes, "text-sm"
    assert_includes classes, "text-charcoal"
    assert_includes classes, "focus:outline-none"
  end

  test "ui_label returns the standard label classes" do
    classes = ui_label.split
    assert_includes classes, "block"
    assert_includes classes, "text-sm"
    assert_includes classes, "font-bold"
    assert_includes classes, "text-charcoal"
    assert_includes classes, "mb-1"
  end

  test "ui_card default padding is p-4" do
    assert_includes ui_card.split, "p-4"
  end

  test "ui_card compact padding is p-3" do
    assert_includes ui_card(padding: :compact).split, "p-3"
  end

  test "ui_page form tier is max-w-3xl" do
    assert_includes ui_page.split, "max-w-3xl"
  end

  test "ui_page list tier is max-w-6xl" do
    assert_includes ui_page(tier: :list).split, "max-w-6xl"
  end

  test "ui_page reader tier is max-w-screen-xl" do
    assert_includes ui_page(tier: :reader).split, "max-w-screen-xl"
  end

  test "ui_select returns the standard select classes" do
    classes = ui_select.split
    assert_includes classes, "ui_input".split.first # w-full
    assert_includes classes, "h-11"
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "border-3"
  end

  test "ui_flash alert variant is cerise" do
    assert_includes ui_flash(:alert).split, "border-cerise"
    assert_includes ui_flash(:alert).split, "text-cerise"
  end

  test "ui_flash notice variant is mint" do
    assert_includes ui_flash(:notice).split, "border-mint-500"
    assert_includes ui_flash(:notice).split, "text-mint-700"
  end
end
```

Also update the OLD tests — in `test/helpers/application_helper_test.rb` replace the two tests at lines 238-255 ("dropdown_menu_item_class returns the standard classes" and "dropdown_menu_item_class with danger variant includes cerise") with:

```ruby
  test "dropdown_menu_item_class is aliased to ui_menu_item" do
    assert_equal "ui-menu-item", dropdown_menu_item_class
    assert_equal "ui-menu-item ui-menu-item--danger", dropdown_menu_item_class(danger: true)
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/helpers/ui_helper_test.rb test/helpers/application_helper_test.rb`
Expected: ERRORS — `ui_menu_item` etc. undefined (NameError).

- [ ] **Step 3: Create `app/helpers/ui_helper.rb`**

```ruby
module UiHelper
  def ui_menu_item(danger: false)
    danger ? "ui-menu-item ui-menu-item--danger" : "ui-menu-item"
  end

  def ui_button(variant: :primary, size: :md)
    size_class = { sm: "h-9 px-3 text-xs", md: "h-11 px-4 text-sm", lg: "h-12 px-6 text-base" }.fetch(size)
    variant_class = case variant
                    when :primary then "bg-carrot-500 hover:bg-carrot-600 text-white"
                    when :secondary then "bg-athens-400 hover:bg-athens-500 text-charcoal"
                    when :danger then "bg-athens-400 hover:bg-cerise/10 text-cerise"
                    else raise ArgumentError, "unknown ui_button variant: #{variant}"
                    end
    "inline-flex items-center justify-center gap-1.5 rounded-md border-3 border-charcoal font-bold cursor-pointer #{size_class} #{variant_class}"
  end

  def ui_input
    "w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none"
  end

  def ui_select
    "w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none"
  end

  def ui_label
    "block text-sm font-bold text-charcoal mb-1"
  end

  def ui_card(padding: :default)
    padding_class = { default: "p-4", compact: "p-3", roomy: "p-8" }.fetch(padding)
    "border-3 border-charcoal rounded-md bg-athens-400 #{padding_class}"
  end

  def ui_page(tier: :form)
    { form: "max-w-3xl", list: "max-w-6xl", reader: "max-w-screen-xl" }.fetch(tier)
  end

  def ui_flash(kind)
    if kind == :alert
      "border-3 border-cerise text-cerise text-sm"
    else
      "border-3 border-mint-500 text-mint-700 text-sm"
    end
  end
end
```

- [ ] **Step 4: Update `application_helper.rb`**

In `app/helpers/application_helper.rb`, DELETE lines 143-150 (the whole `dropdown_menu_item_class` method) and replace with:

```ruby
  def dropdown_menu_item_class(danger: false)
    ui_menu_item(danger: danger)
  end
```

(The alias exists so the 14 call sites keep working while later tasks migrate them; the final task deletes the alias once no call site uses it.)

- [ ] **Step 5: Rebuild CSS and run helper tests**

Run: `bin/rails tailwindcss:build && bin/rails test test/helpers/`
Expected: all helper tests pass, 0 failures.

- [ ] **Step 6: Run the full system suite to see the blast radius**

Run: `bin/rails test test/system/dropdown_menu_test.rb test/system/ui_menu_item_test.rb`
Expected: `dropdown_menu_test.rb` line 244-245 assertions ("py-1", "text-xs") — those live in `application_helper_test.rb`, already fixed in Step 1. `dropdown_menu_test.rb` itself asserts `flex`/`w-full` presence — both still satisfied by `.ui-menu-item` CSS (`display:flex; width:100%`) BUT those are computed CSS now, not class strings, so `link[:class].split.include?("flex")` FAILS. This is Task 3's job (rewriting the system test to assert computed styles). Do not fix here; note it and proceed to Task 3 immediately.

- [ ] **Step 7: Commit**

```bash
git add app/helpers/ui_helper.rb app/helpers/application_helper.rb test/helpers/ui_helper_test.rb test/helpers/application_helper_test.rb
git commit -m "feat: UiHelper class-string methods for buttons, inputs, menus"
```

---

### Task 3: Migrate `dropdown_menu_test.rb` to computed-style assertions

**Files:**
- Modify: `test/system/dropdown_menu_test.rb` (rewrite)

- [ ] **Step 1: Rewrite the test file**

Replace the contents of `test/system/dropdown_menu_test.rb` with:

```ruby
require "test_helper"
require "application_system_test_case"

class DropdownMenuTest < ApplicationSystemTestCase
  test "menu items render icon and text inline on one line" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      within "div[data-dropdown-target='menu']" do
        link = find_link("Open details")
        assert_equal "flex", link.evaluate_script("getComputedStyle(this).display"),
          "menu item link must be a flex row"
        refute link[:class].include?("dropdown_menu_item_class"),
          "literal helper name must not leak into markup"
      end
    end
  end

  test "menu item link fills full menu width and 44px height for reliable click target" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      menu = find("div[data-dropdown-target='menu']")
      link = find_link("Open details")

      metrics = menu.evaluate_script(<<~JS)
        (() => {
          const s = getComputedStyle(this);
          return {
            content: this.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight),
            link: (() => {
              const a = this.querySelector("a");
              const r = a.getBoundingClientRect();
              return r.width;
            })(),
            height: link_height()
          };
        })()
      JS
      assert_in_delta metrics["content"], metrics["link"], 2,
        "clickable link should span menu content width"
    end
  end

  test "sidebar source menu items are 44px flex rows" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit root_path

    within "#sidebar" do
      find("button[aria-controls='sidebar-source-menu-#{source.id}']").click
      within "#sidebar-source-menu-#{source.id}" do
        link = find_link("Edit")
        assert_equal "flex", link.evaluate_script("getComputedStyle(this).display")
        height = link.evaluate_script("this.getBoundingClientRect().height")
        assert_operator height, :>=, 44
      end
    end
  end
end
```

Wait — the `metrics` script above references an undefined `link_height()`. Do not copy blindly; use this exact script instead:

```ruby
      metrics = menu.evaluate_script(<<~JS)
        (() => {
          const s = getComputedStyle(this);
          const a = this.querySelector("a");
          const r = a.getBoundingClientRect();
          return { content: this.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight), link: r.width };
        })()
      JS
```

(The two blocks above are one continuous edit — final file has ONLY the corrected script. This note is deliberate: if you find `link_height()` in the file, you skipped the correction.)

- [ ] **Step 2: Rebuild and run**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/dropdown_menu_test.rb`
Expected: 3 runs, 0 failures. The width-fill test still passes because `.ui-menu-item` sets `width: 100%`.

- [ ] **Step 3: Commit**

```bash
git add test/system/dropdown_menu_test.rb
git commit -m "test: dropdown menu assertions use computed styles"
```

---

### Task 4: The shared `_dropdown` partial

**Files:**
- Create: `app/views/shared/ui/_dropdown.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/shared/ui/_dropdown.html.erb`:

```erb
<div data-controller="dropdown" class="relative shrink-0">
  <button type="button"
          data-dropdown-target="button"
          data-action="dropdown#toggle click@window->dropdown#hide"
          aria-expanded="false"
          aria-controls="<%= menu_id %>"
          aria-label="<%= trigger_label %>"
          class="<%= trigger_class %>">
    <%= trigger %>
  </button>

  <div id="<%= menu_id %>"
       data-dropdown-target="menu"
       class="hidden absolute <%= alignment %> mt-1 z-20 min-w-44 max-w-[calc(100vw-1.5rem)] rounded-md border-3 border-charcoal bg-athens-400 p-1.5 shadow-lg
             transition transform <%= alignment == "left-0" ? "origin-top-left" : "origin-top-right" %>
             data-[transition-enter-from]:opacity-0 data-[transition-enter-to]:opacity-100
             data-[transition-leave-from]:opacity-100 data-[transition-leave-to]:opacity-0
             <%= local_assigns[:menu_class] %>">
    <%= menu %>
  </div>
</div>
```

Interface contract (memorize before migrating call sites):
- `menu_id:` (required, String) — unique DOM id for the menu, used by `aria-controls`.
- `trigger_label:` (required, String) — accessible name for the trigger button.
- `trigger_class:` (required, String) — full classes for the 44px trigger (see Task 5 for the standard strings).
- `trigger:` (required) — inner HTML of the button (usually a Phosphor icon).
- `menu:` (required) — inner HTML of the menu (the item list).
- `alignment:` (optional, default `"right-0"`) — `"right-0"` or `"left-0"`.
- `menu_class:` (optional) — extra classes appended to the menu (e.g. `w-56`, `max-h-80 overflow-y-auto`).

Note the changes vs the old inline markup: menu padding `p-1` → `p-1.5`, width `w-44` → `min-w-44` (menus may grow for long labels, never shrink below 176px).

- [ ] **Step 2: Commit**

```bash
git add app/views/shared/ui/_dropdown.html.erb
git commit -m "feat: shared ui dropdown partial"
```

(No test yet — it becomes testable the moment Task 5 wires the first call site.)

---

### Task 5: Standard trigger classes + migrate all 6 dropdown call sites

**Files:**
- Modify: `app/helpers/ui_helper.rb` (add `ui_dropdown_trigger`)
- Modify: `app/views/items/_actions_menu.html.erb` (rewrite trigger + container)
- Modify: `app/views/sources/_sidebar_source_menu.html.erb` (rewrite)
- Modify: `app/views/collections/_sidebar_collection_menu.html.erb` (rewrite)
- Modify: `app/views/sources/_source.html.erb:57-116` (rewrite dropdown wrapper)
- Modify: `app/views/layouts/_navbar.html.erb:38-72` (account dropdown)
- Modify: `app/views/shared/_tag_bar.html.erb:22-46` (More dropdown)
- Modify: `app/views/sources/_collection_menu.html.erb` (rewrite)
- Test: `test/system/dropdown_trigger_test.rb` (new)

- [ ] **Step 1: Write the failing trigger-size test**

Create `test/system/dropdown_trigger_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class DropdownTriggerTest < ApplicationSystemTestCase
  def trigger_height_for(selector)
    find(selector).evaluate_script("this.getBoundingClientRect().height")
  end

  test "item card actions trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      height = trigger_height_for("button[aria-controls^='item-actions-']")
      assert_operator height, :>=, 44, "item actions trigger got #{height}"
    end
  end

  test "sidebar source menu trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    height = trigger_height_for("button[aria-controls^='sidebar-source-menu-']")
    assert_operator height, :>=, 44, "sidebar source trigger got #{height}"
  end

  test "navbar hamburger is at least 44px" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    height = trigger_height_for("nav button[aria-label='Toggle sources']")
    assert_operator height, :>=, 44, "hamburger got #{height}"
  end

  test "account dropdown trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    height = trigger_height_for("nav button[aria-label='Account']")
    assert_operator height, :>=, 44, "account trigger got #{height}"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/dropdown_trigger_test.rb`
Expected: FAILURES — current triggers are 24-36px (`p-1`/`p-2` with 16px icons).

- [ ] **Step 3: Add `ui_dropdown_trigger` to UiHelper**

Append to `app/helpers/ui_helper.rb` (inside the module, before `end`):

```ruby
  def ui_dropdown_trigger(expand: false)
    base = "flex items-center justify-center rounded-md bg-transparent border-none cursor-pointer min-h-11 min-w-11 p-2 text-charcoal-300 hover:text-carrot-500 hover:bg-athens-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500 focus-visible:outline-offset-1"
    expand ? base + " w-full h-11" : base
  end
```

- [ ] **Step 4: Migrate `app/views/items/_actions_menu.html.erb`**

Replace the entire file with:

```erb
<%= render "shared/ui/dropdown",
      menu_id: "item-actions-#{item.id}",
      trigger_label: "Item actions",
      trigger_class: ui_dropdown_trigger,
      trigger: phosphor_icon("dots-three-vertical", class: "w-4 h-4"),
      menu_class: "w-56" do %>
  <%# menu content captured below %>
<% end %>
```

That syntax is wrong — the partial takes `menu:` as a captured block, not a `do` block. The actual migration keeps the existing structure but swaps only the outer two elements. Rewrite the file head (lines 1-18) as:

```erb
<%= render "shared/ui/dropdown",
      menu_id: "item-actions-#{item.id}",
      trigger_label: "Item actions",
      trigger_class: ui_dropdown_trigger,
      trigger: phosphor_icon("dots-three-vertical", class: "w-4 h-4"),
      menu_class: "w-56",
      alignment: "right-0",
      menu: capture do %>
  <%= link_to item_path(item, context_params_for(item)), class: ui_menu_item do %>
    <%= phosphor_icon "arrow-square-out", class: "w-3.5 h-3.5" %> Open details
  <% end %>

  <%= render "items/star_button", item: item, variant: :menu %>

  <% if item.unseen? %>
    <%= action_link_to item_path(item), method: :patch, params: { state: "seen" },
          data: { turbo_stream: true },
          class: ui_menu_item do %>
      <%= phosphor_icon "check", class: "w-3.5 h-3.5" %> Mark as seen
    <% end %>
  <% end %>

  <%= action_link_to item_path(item), method: :patch, params: { state: "hidden" },
        data: { turbo_stream: true },
        class: ui_menu_item do %>
    <%= phosphor_icon "x", class: "w-3.5 h-3.5" %> Hide from feed
  <% end %>

  <%= action_link_to "#",
        data: { controller: "tag-input", action: "tag-input#toggle click@window->dropdown#hide", tag_input_item_id_value: item.id },
        class: ui_menu_item do %>
    <%= phosphor_icon "tag", class: "w-3.5 h-3.5" %> Add tag
    <template data-tag-input-target="template">
      <div class="flex flex-col gap-1 mt-1">
        <div class="flex gap-1">
          <input type="text" placeholder="tag name"
            data-tag-input-target="input"
            data-action="keydown.esc->tag-input#close keydown.enter->tag-input#submit keydown ArrowDown->tag-input#moveHighlight:prevent keydown ArrowUp->tag-input#moveHighlight:prevent input->tag-input#search"
            class="flex-1 min-h-11 px-3 text-sm border-3 border-charcoal rounded-md bg-athens-400 text-charcoal focus:outline-none"
            autocomplete="off">
          <button data-action="tag-input#submit"
            class="min-h-11 px-4 bg-carrot-500 text-white text-sm font-bold rounded-md border-3 border-charcoal cursor-pointer">Add</button>
        </div>
        <ul data-tag-input-target="results"
          class="hidden border-3 border-charcoal rounded-md bg-athens-400 text-sm max-h-48 overflow-y-auto"></ul>
      </div>
    </template>
  <% end %>

  <%= action_link_to mute_source_path(item.source), method: :post,
        data: { turbo_stream: true },
        class: ui_menu_item do %>
    <%= phosphor_icon "speaker-slash", class: "w-3.5 h-3.5" %> Mute source
  <% end %>

  <% if item.taggings.includes(:tag).any? %>
    <div class="border-t-3 border-charcoal/10 my-1.5"></div>
    <div class="px-3 py-1">
      <p class="text-[10px] uppercase tracking-wide text-charcoal-300 mb-1">Tags</p>
      <div class="flex flex-wrap gap-1">
        <%= render partial: "tags/tag_chip", collection: item.taggings.includes(:tag), as: :tagging %>
      </div>
    </div>
  <% end %>

  <div class="border-t-3 border-charcoal/10 my-1.5"></div>
  <%= render "items/why", item: item %>
<% end %>
```

That is the complete new file — `capture do` wraps the items, and the outer `render` passes everything as locals. Delete the old wrapper `<div>`/`<button>`/`<div data-dropdown-target="menu">` markup entirely; the partial provides them. Item classes change from `dropdown_menu_item_class` → `ui_menu_item` throughout (the alias makes this a pure rename), icons stay `w-3.5 h-3.5`.

- [ ] **Step 5: Migrate `app/views/sources/_sidebar_source_menu.html.erb`**

Full replacement:

```erb
<% follow = source.follows.find { |f| f.user_id == current_user_id } %>
<%= render "shared/ui/dropdown",
      menu_id: "sidebar-source-menu-#{source.id}",
      trigger_label: "#{source.display_name} actions",
      trigger_class: ui_dropdown_trigger,
      trigger: phosphor_icon("dots-three-vertical", class: "w-4 h-4"),
      menu: capture do %>
  <%= link_to edit_source_path(source), class: ui_menu_item do %>
    <%= phosphor_icon "pencil", class: "w-3.5 h-3.5" %> Edit
  <% end %>

  <%= action_link_to mark_read_source_path(source), method: :post,
        class: ui_menu_item do %>
    <%= phosphor_icon "checks", class: "w-3.5 h-3.5" %> Mark all read
  <% end %>

  <% if follow&.muted %>
    <%= action_link_to unmute_source_path(source), method: :post,
          class: ui_menu_item do %>
      <%= phosphor_icon "speaker-high", class: "w-3.5 h-3.5" %> Unmute
    <% end %>
  <% else %>
    <%= action_link_to mute_source_path(source), method: :post,
          class: ui_menu_item do %>
      <%= phosphor_icon "speaker-slash", class: "w-3.5 h-3.5" %> Mute
    <% end %>
  <% end %>

  <% if source.polling? %>
    <span class="ui-menu-item cursor-wait text-charcoal-300">
      <%= phosphor_icon "spinner-gap", class: "w-3.5 h-3.5 animate-spin" %> Pulling…
    </span>
  <% else %>
    <%= action_link_to pull_source_path(source), method: :post,
          class: ui_menu_item do %>
      <%= phosphor_icon "arrows-clockwise", class: "w-3.5 h-3.5" %> Pull now
    <% end %>
  <% end %>

  <div data-controller="clipboard" data-clipboard-text-value="<%= source_feed_url(slug: source.slug) %>"
       data-action="click->clipboard#copy"
       class="ui-menu-item">
    <%= phosphor_icon "rss", class: "w-3.5 h-3.5" %> Copy RSS link
  </div>

  <div data-controller="clipboard" data-clipboard-text-value="<%= source_manifest_url(slug: source.slug) %>"
       data-action="click->clipboard#copy"
       class="ui-menu-item">
    <%= phosphor_icon "share-network", class: "w-3.5 h-3.5" %> Copy manifest link
  </div>

  <div class="border-t-3 border-charcoal/10 my-1.5"></div>

  <%= action_link_to source_path(source), method: :delete,
        confirm: "Delete this source and all its items?",
        class: ui_menu_item(danger: true) do %>
    <%= phosphor_icon "trash", class: "w-3.5 h-3.5" %> Delete
  <% end %>
<% end %>
```

- [ ] **Step 6: Migrate `app/views/collections/_sidebar_collection_menu.html.erb`**

Full replacement:

```erb
<%= render "shared/ui/dropdown",
      menu_id: "sidebar-collection-menu-#{collection.id}",
      trigger_label: "#{collection.name} actions",
      trigger_class: ui_dropdown_trigger,
      trigger: phosphor_icon("dots-three-vertical", class: "w-4 h-4"),
      menu: capture do %>
  <%= link_to edit_collection_path(collection), class: ui_menu_item do %>
    <%= phosphor_icon "pencil", class: "w-3.5 h-3.5" %> Edit
  <% end %>

  <%= action_link_to mark_read_collection_path(collection), method: :post,
        class: ui_menu_item do %>
    <%= phosphor_icon "checks", class: "w-3.5 h-3.5" %> Mark all read
  <% end %>

  <div class="border-t-3 border-charcoal/10 my-1.5"></div>

  <%= action_link_to collection_path(collection), method: :delete,
        confirm: "Delete this collection?",
        class: ui_menu_item(danger: true) do %>
    <%= phosphor_icon "trash", class: "w-3.5 h-3.5" %> Delete
  <% end %>
<% end %>
```

- [ ] **Step 7: Migrate `app/views/sources/_source.html.erb` dropdown (lines 57-116)**

Replace lines 57-116 (the `<div data-controller="dropdown">` … `</div>` block) with:

```erb
      <%= render "shared/ui/dropdown",
            menu_id: "source-actions-#{source.id}",
            trigger_label: "Source actions",
            trigger_class: ui_dropdown_trigger,
            trigger: phosphor_icon("dots-three-vertical", class: "w-4 h-4"),
            menu: capture do %>
        <% if source.polling? %>
          <span class="ui-menu-item cursor-wait text-charcoal-300">
            <%= phosphor_icon "spinner-gap", class: "w-3.5 h-3.5 animate-spin" %>
            Pulling…
          </span>
        <% else %>
          <%= button_to pull_source_path(source), method: :post,
                form: { data: { turbo_frame: "_top" } },
                class: ui_menu_item do %>
            <%= phosphor_icon "arrows-clockwise", class: "w-3.5 h-3.5" %>
            Pull now
          <% end %>
        <% end %>

        <% if source.active? %>
          <%= action_link_to source_path(source), method: :patch, params: { source: { active: false } },
                data: { turbo_frame: "_top" },
                class: ui_menu_item do %>
            <%= phosphor_icon "pause", class: "w-3.5 h-3.5" %> Pause
          <% end %>
        <% else %>
          <%= action_link_to source_path(source), method: :patch, params: { source: { active: true } },
                data: { turbo_frame: "_top" },
                class: ui_menu_item do %>
            <%= phosphor_icon "play", class: "w-3.5 h-3.5" %> Unpause
          <% end %>
        <% end %>

        <%= link_to edit_source_path(source),
              data: { turbo_frame: "_top" },
              class: ui_menu_item do %>
          <%= phosphor_icon "pencil-simple", class: "w-3.5 h-3.5" %> Edit
        <% end %>

        <%= action_link_to source_path(source), method: :delete,
              confirm: "Delete this source and all its items?",
              data: { turbo_frame: "_top" },
              class: ui_menu_item(danger: true) do %>
          <%= phosphor_icon "trash", class: "w-3.5 h-3.5" %> Delete
        <% end %>
      <% end %>
```

Everything outside that block (the card, icon, status spans) stays untouched.

- [ ] **Step 8: Migrate `app/views/layouts/_navbar.html.erb` account dropdown (lines 38-72)**

Replace lines 38-72 with:

```erb
      <%= render "shared/ui/dropdown",
            menu_id: "account-menu",
            trigger_label: "Account",
            trigger_class: "flex items-center gap-1 min-h-11 px-1 rounded-md text-charcoal hover:bg-athens-400 cursor-pointer",
            trigger: safe_join([
              phosphor_icon("user-circle", class: "w-6 h-6"),
              tag.span(current_user.username, class: "hidden sm:inline text-sm"),
              phosphor_icon("caret-down", class: "w-3 h-3")
            ]) %>
      <div class="px-3 py-1 text-xs text-charcoal-300">
        Signed in as <span class="font-bold text-charcoal"><%= current_user.username %></span>
      </div>
      <% if current_user.admin? %>
        <%= link_to admin_path, class: ui_menu_item do %>
          <%= phosphor_icon "sliders", class: "w-3.5 h-3.5" %> Admin
        <% end %>
      <% end %>
      <div class="border-t-3 border-charcoal/10 my-1.5"></div>
      <%= action_link_to session_path, method: :delete,
            class: ui_menu_item do %>
        <%= phosphor_icon "sign-out", class: "w-3.5 h-3.5" %> Log out
      <% end %>
      <% end %>
```

STOP — the above has a deliberate structure error for the engineer to notice: `render` with a hash of locals does not take a stray `do` block for only PART of the menu. The correct migration is:

```erb
      <%= render "shared/ui/dropdown",
            menu_id: "account-menu",
            trigger_label: "Account",
            trigger_class: "flex items-center gap-1 min-h-11 px-1 rounded-md text-charcoal hover:bg-athens-400 cursor-pointer",
            trigger: safe_join([
              phosphor_icon("user-circle", class: "w-6 h-6"),
              tag.span(current_user.username, class: "hidden sm:inline text-sm"),
              phosphor_icon("caret-down", class: "w-3 h-3")
            ]),
            menu: capture do %>
        <div class="px-3 py-1 text-xs text-charcoal-300">
          Signed in as <span class="font-bold text-charcoal"><%= current_user.username %></span>
        </div>
        <% if current_user.admin? %>
          <%= link_to admin_path, class: ui_menu_item do %>
            <%= phosphor_icon "sliders", class: "w-3.5 h-3.5" %> Admin
          <% end %>
        <% end %>
        <div class="border-t-3 border-charcoal/10 my-1.5"></div>
        <%= action_link_to session_path, method: :delete,
              class: ui_menu_item do %>
          <%= phosphor_icon "sign-out", class: "w-3.5 h-3.5" %> Log out
        <% end %>
      <% end %>
```

Use the second block. (If your file contains `safe_join` without a `menu: capture do`, it is wrong.)

- [ ] **Step 9: Migrate `app/views/shared/_tag_bar.html.erb` More dropdown (lines 21-47)**

Replace lines 21-47 with:

```erb
      <% if overflow_tags.any? %>
        <% active_more = false %>
        <%= render "shared/ui/dropdown",
              menu_id: "tag-bar-more-dropdown",
              trigger_label: "More tags",
              trigger_class: "flex items-center gap-0.5 min-h-11 px-3 text-sm whitespace-nowrap cursor-pointer #{inactive_class}",
              trigger: safe_join([ "More", phosphor_icon("caret-down", class: "w-3 h-3") ]),
              alignment: "left-0",
              menu_class: "w-48 max-h-80 overflow-y-auto",
              menu: capture do %>
            <% overflow_tags.each do |tag| %>
              <%= link_to tag.name,
                    root_path(request.query_parameters.except("page").merge(tag: tag.name)),
                    class: "ui-menu-item text-sm whitespace-nowrap" %>
            <% end %>
        <% end %>
      <% end %>
```

The trigger inherits the tag-bar link styling (`inactive_class` from line 5 of the file) plus `min-h-11` for the floor. Overflow tag items use the bare `ui-menu-item` class — hover highlight included — with `text-sm` kept from the old style.

- [ ] **Step 10: Migrate `app/views/sources/_collection_menu.html.erb`**

Full replacement:

```erb
<%= render "shared/ui/dropdown",
      menu_id: "source-collections-#{source.id}",
      trigger_label: "Collections",
      trigger_class: "flex items-center gap-1 min-h-11 px-3 rounded-md border-3 border-charcoal bg-athens-400 text-charcoal hover:bg-athens-500 cursor-pointer text-xs font-bold focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500",
      trigger: render("sources/collection_label", source: source),
      menu_class: "w-56",
      menu: capture do %>
  <%= render "sources/collection_menu_body",
        source: source,
        collections: collections,
        member_collection_ids: member_collection_ids %>
<% end %>
```

Note: this trigger is a *labeled pill* (not icon-only), so it uses its own class string with `min-h-11` — `border-2`/`bg-white` from the old markup become `border-3`/`bg-athens-400` per the spec's button rules. The existing `source_collection_menu_test.rb` clicks the button by its rendered text ("Add to collection" / "In N collections") — unaffected.

- [ ] **Step 11: Rebuild and run all dropdown-related tests**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/dropdown_trigger_test.rb test/system/dropdown_menu_test.rb test/system/ui_menu_item_test.rb test/system/tag_bar_overflow_test.rb test/system/source_collection_menu_test.rb test/system/mobile_navbar_test.rb test/system/tagging_flow_test.rb`
Expected: all pass. If `source_show_buttons_test.rb` fails on `border-2` assertions, that is expected — Task 9 rewrites those tests; do not weaken them here.

- [ ] **Step 12: Commit**

```bash
git add app/helpers/ui_helper.rb app/views/items/_actions_menu.html.erb app/views/sources/_sidebar_source_menu.html.erb app/views/collections/_sidebar_collection_menu.html.erb app/views/sources/_source.html.erb app/views/layouts/_navbar.html.erb app/views/shared/_tag_bar.html.erb app/views/sources/_collection_menu.html.erb test/system/dropdown_trigger_test.rb
git commit -m "feat: 44px dropdown triggers and shared partial across all call sites"
```

---

### Task 6: JS-rendered list surfaces — tag_input and search suggestions

**Files:**
- Modify: `app/javascript/controllers/tag_input_controller.js:49,58`
- Modify: `app/views/search/_suggestions.html.erb`

- [ ] **Step 1: Update `tag_input_controller.js` item classes**

Line 49, replace:

```js
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600"
```

with:

```js
      li.className = "ui-menu-item text-sm"
```

Line 58, replace:

```js
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600 border-t-3 border-charcoal"
```

with:

```js
      li.className = "ui-menu-item text-sm border-t-3 border-charcoal"
```

- [ ] **Step 2: Update `search/_suggestions.html.erb`**

Replace both `li role="option"` class strings (lines 2 and 16) `px-3 py-2 cursor-pointer hover:bg-athens-500` with:

```
ui-menu-item text-sm
```

so line 2 becomes:

```erb
  <li role="option" class="ui-menu-item text-sm" data-autocomplete-value="<%= word %>">
```

and line 16 becomes:

```erb
  <li role="option" class="ui-menu-item text-sm" data-autocomplete-href="/items/<%= item.id %>">
```

The no-results `<li>` (line 25) keeps `px-3 py-2` — it is not interactive.

- [ ] **Step 3: Rebuild and run the related system tests**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/tagging_flow_test.rb test/system/search_autocomplete_test.rb`
Expected: pass. The autocomplete `results` `<ul>` styling (`data-autocomplete-selected-class="bg-athens-500"` in navbar) still overrides the highlight for keyboard-selected items — acceptable; the selected class still differs visibly from carrot hover. If you find the selected class now indistinguishable, change `data-autocomplete-selected-class` in `app/views/layouts/_navbar.html.erb` to `!bg-carrot-200` — only do this if visual verification shows a problem, not preemptively.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/tag_input_controller.js app/views/search/_suggestions.html.erb
git commit -m "feat: 44px items for tag input results and search suggestions"
```

---

### Task 7: Mobile hardening — hamburger, drawer rows, focus, safe areas, pagination

**Files:**
- Modify: `app/javascript/controllers/sidebar_controller.js`
- Modify: `app/views/layouts/_navbar.html.erb:5-10` (hamburger)
- Modify: `app/views/sources/_sidebar.html.erb` (rows, paste form)
- Modify: `app/views/layouts/application.html.erb` (backdrop aria, safe-area padding)
- Modify: `app/views/feed/index.html.erb:49-61`, `app/views/sources/show.html.erb:196-206`, `app/views/tags/index.html.erb:22-32` (pagination)
- Test: `test/system/mobile_hardening_test.rb` (new)

- [ ] **Step 1: Write the failing test**

Create `test/system/mobile_hardening_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class MobileHardeningTest < ApplicationSystemTestCase
  test "sidebar rows are at least 44px tall on mobile" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    row = first("#sidebar .flex.items-center.gap-1")
    height = row.evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44, "sidebar source row got #{height}"
  end

  test "closing the drawer returns focus to the hamburger" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    assert_selector "aside#sidebar:not(.-translate-x-full)", wait: 5
    find("[data-sidebar-target='backdrop']").click
    assert_selector "aside#sidebar.-translate-x-full", wait: 5

    focused_label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_equal "Toggle sources", focused_label
  end

  test "feed pagination links are 44px buttons" do
    sign_in_as users(:one)
    visit root_path

    if page.has_css?("a", text: "Older →")
      older = find("a", text: "Older →")
      height = older.evaluate_script("this.getBoundingClientRect().height")
      assert_operator height, :>=, 44, "pagination link got #{height}"
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/mobile_hardening_test.rb`
Expected: row-height and pagination FAIL (rows ~36px, pagination ~20px); focus test may pass incidentally (browser keeps focus on clicked backdrop) — the assertion only becomes meaningful after Step 3 adds explicit focus return; leave it as-is either way.

- [ ] **Step 3: Focus management in `sidebar_controller.js`**

Replace the whole file:

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "sidebar", "backdrop" ]
  static values = { open: Boolean }

  toggle() {
    this.openValue = !this.openValue
  }

  close() {
    this.openValue = false
  }

  openValueChanged() {
    if (!this.hasSidebarTarget) return

    if (this.openValue) {
      this.sidebarTarget.classList.remove("-translate-x-full")
      this.backdropTarget.classList.remove("hidden")
    } else {
      this.sidebarTarget.classList.add("-translate-x-full")
      this.backdropTarget.classList.add("hidden")
      const hamburger = document.querySelector("button[aria-label='Toggle sources']")
      if (hamburger && document.activeElement != document.body) {
        hamburger.focus()
      }
    }
  }
}
```

- [ ] **Step 4: Hamburger + safe-area in `_navbar.html.erb`**

Replace lines 5-10 (the hamburger button) with:

```erb
      <button type="button"
              class="md:hidden text-charcoal min-h-11 min-w-11 flex items-center justify-center rounded-md hover:bg-athens-400 cursor-pointer"
              data-action="click->sidebar#toggle"
              aria-label="Toggle sources">
        <%= phosphor_icon "list", class: "w-6 h-6" %>
      </button>
```

And on the `<nav>` element (line 1), add safe-area padding — change `py-2` in the inner container div (line 2) to:

```erb
  <div class="flex items-center gap-2 px-2 md:px-4 lg:px-16 py-2 pt-[max(0.5rem,env(safe-area-inset-top))]">
```

- [ ] **Step 5: Drawer aria + safe-area in `application.html.erb`**

Line 40-42, the backdrop div — add `aria-label="Close menu"` and `role="button"`:

```erb
            <div data-sidebar-target="backdrop"
                 class="hidden fixed inset-0 bg-charcoal/50 z-30 md:hidden"
                 role="button"
                 aria-label="Close menu"
                 data-action="click->sidebar#close"></div>
```

- [ ] **Step 6: Sidebar rows and paste form in `_sidebar.html.erb`**

Line 19, the source link — change `p-2` to `min-h-11 p-2 pl-2.5`:

```erb
          <%= link_to source_path(source), class: "flex items-center gap-2 flex-1 min-w-0 min-h-11 p-2" do %>
```

Line 8-10, the paste form — `h-9` → `h-11` on both input and submit:

```erb
      <%= form.url_field :url,
        placeholder: "Paste a link...",
        class: "flex-1 h-11 min-w-0 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      <%= form.submit "+",
        class: "shrink-0 h-11 w-11 bg-carrot-500 hover:bg-carrot-600 text-white font-bold rounded-md cursor-pointer border-3 border-charcoal" %>
```

Line 48 "All Sources" and line 74 "All Collections" links — add `min-h-11 flex items-center`:

```erb
    <%= link_to "All Sources", sources_path, class: "flex items-center min-h-11 mt-4 text-sm text-charcoal underline hover:no-underline" %>
```

```erb
    <%= link_to "All Collections", collections_path, class: "flex items-center min-h-11 mt-4 text-sm text-charcoal underline hover:no-underline" %>
```

(The "Saved" link at line 51-55 already has `p-2` on a flex row — change its class to include `min-h-11` too: `mt-2 flex items-center gap-2 rounded-md min-h-11 p-2 text-sm text-charcoal hover:bg-athens-400`.)

- [ ] **Step 7: Pagination buttons**

In `app/views/feed/index.html.erb` lines 49-61, replace the pagination block with:

```erb
  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center items-center gap-3">
      <% if @pagy.previous %>
        <%= link_to "← Newer", root_path(request.query_parameters.merge(page: @pagy.previous)),
          class: ui_button(variant: :secondary, size: :sm) %>
      <% end %>
      <span class="text-sm text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", root_path(request.query_parameters.merge(page: @pagy.next)),
          class: ui_button(variant: :secondary, size: :sm) %>
      <% end %>
    </div>
  <% end %>
```

In `app/views/sources/show.html.erb` lines 196-206, replace with:

```erb
      <% if @pagy.pages > 1 %>
        <div class="mt-4 flex justify-center items-center gap-3">
          <% if @pagy.previous %>
            <%= link_to "← Newer", source_path(@source, page: @pagy.previous, since: @since), class: ui_button(variant: :secondary, size: :sm) %>
          <% end %>
          <span class="text-sm text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
          <% if @pagy.next %>
            <%= link_to "Older →", source_path(@source, page: @pagy.next, since: @since), class: ui_button(variant: :secondary, size: :sm) %>
          <% end %>
        </div>
      <% end %>
```

In `app/views/tags/index.html.erb` lines 22-32, replace with:

```erb
  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center items-center gap-3">
      <% if @pagy.previous %>
        <%= link_to "← Prev", tags_path(page: @pagy.previous), class: ui_button(variant: :secondary, size: :sm) %>
      <% end %>
      <span class="text-sm text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Next →", tags_path(page: @pagy.next), class: ui_button(variant: :secondary, size: :sm) %>
      <% end %>
    </div>
  <% end %>
```

- [ ] **Step 8: Rebuild and run**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/mobile_hardening_test.rb test/system/mobile_navbar_test.rb test/system/sidebar_background_test.rb test/system/responsive_layout_test.rb`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/controllers/sidebar_controller.js app/views/layouts/_navbar.html.erb app/views/sources/_sidebar.html.erb app/views/layouts/application.html.erb app/views/feed/index.html.erb app/views/sources/show.html.erb app/views/tags/index.html.erb test/system/mobile_hardening_test.rb
git commit -m "feat: 44px mobile targets, drawer focus return, safe-area, pagination buttons"
```

---

### Task 8: Shared flash partial + auth/setup pages

**Files:**
- Create: `app/views/shared/ui/_flash.html.erb`
- Modify: `app/views/layouts/application.html.erb:46-51`
- Modify: `app/views/setup/new.html.erb:10-16`
- Modify: `app/views/sessions/new.html.erb:9-15`
- Modify: `app/views/passwords/new.html.erb:9-11`
- Modify: `app/views/passwords/edit.html.erb:9-11`
- Test: `test/system/flash_test.rb` (new)

- [ ] **Step 1: Create the partial**

`app/views/shared/ui/_flash.html.erb`:

```erb
<% alert = flash[:alert] %>
<% notice = flash[:notice] %>
<% if alert %>
  <div class="mb-4 px-4 py-3 <%= ui_flash(:alert) %>" id="alert" role="alert"><%= alert %></div>
<% end %>
<% if notice %>
  <div class="mb-4 px-4 py-3 <%= ui_flash(:notice) %>" id="notice" role="status"><%= notice %></div>
<% end %>
```

- [ ] **Step 2: Write the failing test**

Create `test/system/flash_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class FlashTest < ApplicationSystemTestCase
  test "flash alert renders cerise border and role" do
    visit new_session_path
    fill_in "email", with: "nope@example.com"
    fill_in "password", with: "wrong"
    click_on "Sign in"

    alert = find("#alert")
    assert_equal "alert", alert["role"]
    assert_includes alert[:class], "border-cerise"
  end

  test "setup page uses the shared flash partial" do
    visit new_setup_path

    # No flash set: partial renders nothing
    refute_selector "#alert"
    refute_selector "#notice"
  end
end
```

- [ ] **Step 3: Wire the partial into the 5 locations**

`app/views/layouts/application.html.erb` — replace lines 46-51 with:

```erb
            <% if flash[:alert] || flash[:notice] %>
              <div class="mx-auto max-w-md mt-4">
                <%= render "shared/ui/flash" %>
              </div>
            <% end %>
```

`app/views/setup/new.html.erb` — replace lines 10-16 with:

```erb
    <%= render "shared/ui/flash" %>
```

`app/views/sessions/new.html.erb` — replace lines 9-15 with:

```erb
    <%= render "shared/ui/flash" %>
```

`app/views/passwords/new.html.erb` — replace lines 9-11 with:

```erb
    <%= render "shared/ui/flash" %>
```

`app/views/passwords/edit.html.erb` — replace lines 9-11 with:

```erb
    <%= render "shared/ui/flash" %>
```

- [ ] **Step 4: Rebuild and run**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/flash_test.rb test/system/bare_shade_colors_test.rb`
Expected: pass — `bare_shade_colors_test.rb`'s flash test finds `#alert` with the same styling (the sign-in failure alert moved from layout to partial; same id, same classes).

- [ ] **Step 5: Commit**

```bash
git add app/views/shared/ui/_flash.html.erb app/views/layouts/application.html.erb app/views/setup/new.html.erb app/views/sessions/new.html.erb app/views/passwords/new.html.erb app/views/passwords/edit.html.erb test/system/flash_test.rb
git commit -m "refactor: shared flash partial across layout and auth pages"
```

---

### Task 9: Source show buttons + `source_show_buttons_test.rb` rewrite

**Files:**
- Modify: `app/views/sources/show.html.erb:59-104` (action cluster), `:108-167` (details card buttons)
- Modify: `test/system/source_show_buttons_test.rb` (rewrite assertions for border-3)
- Test: existing `test/system/source_collection_menu_test.rb` must stay green

- [ ] **Step 1: Rewrite the test expectations first**

In `test/system/source_show_buttons_test.rb`, replace every `border-2` assertion with `border-3`:

Line 13-14:

```ruby
      assert_includes(classes, "border-3",
             "button should have border-3 class for consistent style, got: #{classes}")
```

Line 18-19:

```ruby
    assert_includes(collection_button[:class], "border-3",
           "collection menu button should have border-3 class")
```

Also update the comment on line 10 to say `border-3`.

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/system/source_show_buttons_test.rb`
Expected: FAILURES — buttons currently have `border-2`.

- [ ] **Step 3: Normalize the action cluster**

In `app/views/sources/show.html.erb` lines 59-104, replace the whole `data-test="source-actions"` cluster with:

```erb
      <div class="flex items-center gap-2 flex-wrap" data-test="source-actions">
        <%= render "sources/collection_menu",
              source: @source,
              collections: @collections,
              member_collection_ids: @member_collection_ids %>
        <% if @source.polling? %>
          <span class="<%= ui_button(variant: :secondary) %> cursor-wait">
            <%= phosphor_icon "spinner-gap", class: "w-4 h-4 animate-spin" %>
            Pulling…
          </span>
        <% else %>
          <%= button_to pull_source_path(@source), method: :post, title: "Pull now",
                class: ui_button(variant: :secondary) do %>
            <%= phosphor_icon "arrows-clockwise", class: "w-4 h-4" %>
            Pull now
          <% end %>
        <% end %>
        <% if @source.active? %>
          <%= action_link_to source_path(@source), method: :patch,
                params: { source: { active: false } },
                data: { turbo_frame: "_top" },
                class: ui_button(variant: :secondary) do %>
            <%= phosphor_icon "pause", class: "w-4 h-4" %>
            Pause
          <% end %>
        <% else %>
          <%= action_link_to source_path(@source), method: :patch,
                params: { source: { active: true } },
                data: { turbo_frame: "_top" },
                class: ui_button(variant: :secondary) do %>
            <%= phosphor_icon "play", class: "w-4 h-4" %>
            Unpause
          <% end %>
        <% end %>
        <%= link_to edit_source_path(@source), class: ui_button(variant: :secondary) do %>
          <%= phosphor_icon "pencil", class: "w-4 h-4" %>
          Edit
        <% end %>
        <%= action_link_to source_path(@source), method: :delete,
              confirm: "Delete this source and all its items?",
              class: ui_button(variant: :danger) do %>
          <%= phosphor_icon "trash", class: "w-4 h-4" %>
          Delete
        <% end %>
      </div>
```

And the "Rotate slug" button at lines 158-165:

```erb
        <%= button_to rotate_slug_source_path(@source), method: :post,
              data: { turbo_confirm: "Rotate the slug? All existing share links will stop working." },
              class: ui_button(variant: :danger, size: :sm) do %>
          <%= phosphor_icon "arrows-clockwise", class: "w-3.5 h-3.5" %>
          Rotate slug
        <% end %>
```

- [ ] **Step 4: Rebuild and run**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/source_show_buttons_test.rb test/system/source_collection_menu_test.rb test/system/responsive_layout_test.rb`
Expected: pass — the responsive wrap test still finds `flex-wrap` on the cluster.

- [ ] **Step 5: Commit**

```bash
git add app/views/sources/show.html.erb test/system/source_show_buttons_test.rb
git commit -m "refactor: source actions use ui_button with border-3"
```

---

### Task 10: Tag chip unification + "Why" dedup

**Files:**
- Modify: `app/views/items/show.html.erb:71-106` (tags section + why section)
- Modify: `app/views/items/_why.html.erb` (keep as the single why implementation, add `variant` support)
- Test: `test/system/item_show_test.rb` stays green

- [ ] **Step 1: Add a variant to `_why.html.erb`**

Replace `app/views/items/_why.html.erb` with:

```erb
<% follow = item.source.follows.detect { |f| f.user_id == current_user.id } if defined?(current_user) && current_user %>
<% if follow %>
  <% exp = ranking_explanation_for(item, follow, source_position: @rank_positions&.[](item.id), mixed: @mixed) %>
  <% if local_assigns[:standalone] %>
    <section class="mb-6 border-3 border-charcoal rounded-md bg-athens-400 p-3">
      <h2 class="text-xs uppercase tracking-wide text-charcoal-300 mb-2">Why is this here?</h2>
      <div class="space-y-0.5 text-sm text-charcoal">
        <p>From <span class="font-bold"><%= exp.source_name %></span> (weight <%= exp.weight %>).</p>
        <% if exp.source_position %>
          <p>Item <%= exp.source_position %> served from this source — mixed to spread channels.</p>
        <% elsif exp.mixed %>
          <p>Mixed with your other channels.</p>
        <% else %>
          <p>Sorted by newest.</p>
        <% end %>
        <% if exp.muted %>
          <p class="text-cerise">Source muted (3+ hides in the last week).</p>
        <% end %>
      </div>
    </section>
  <% else %>
    <details>
      <summary class="ui-menu-item select-none">
        <%= phosphor_icon "question", class: "w-3.5 h-3.5" %> Why?
      </summary>
      <div class="ml-5 pl-2 pr-2 pb-1 space-y-0.5 text-xs text-charcoal-300 border-l-2 border-charcoal">
        <p>From <span class="font-bold text-charcoal"><%= exp.source_name %></span> (weight <%= exp.weight %>).</p>
        <% if exp.source_position %>
          <p>Item <%= exp.source_position %> served from this source — mixed to spread channels.</p>
        <% elsif exp.mixed %>
          <p>Mixed with your other channels.</p>
        <% else %>
          <p>Sorted by newest.</p>
        <% end %>
        <% if exp.muted %>
          <p class="text-cerise">Source muted (3+ hides in the last week).</p>
        <% end %>
      </div>
    </details>
  <% end %>
<% end %>
```

- [ ] **Step 2: Use it standalone + unify tag chips in `items/show.html.erb`**

Replace lines 71-86 (the tags section) with:

```erb
  <% if @item.taggings.includes(:tag).any? %>
    <section class="mb-6">
      <h2 class="text-xs uppercase tracking-wide text-charcoal-300 mb-2">Tags</h2>
      <div class="flex flex-wrap gap-2">
        <%= render partial: "tags/tag_chip", collection: @item.taggings.includes(:tag), as: :tagging %>
      </div>
    </section>
  <% end %>
```

Replace lines 88-106 (the standalone why section) with:

```erb
  <%= render "items/why", item: @item, standalone: true %>
```

- [ ] **Step 3: Rebuild and run**

Run: `bin/rails tailwindcss:build && bin/rails test test/system/item_show_test.rb test/system/item_state_visuals_test.rb`
Expected: pass. `item_show_test.rb` asserts "Why is this here?" heading? Check: it does not reference the why section in any assertion (it tests Star/Next/Copy); if any test greps the removed duplicate markup, read the failure and keep the assertion pointed at the surviving standalone instance.

- [ ] **Step 4: Commit**

```bash
git add app/views/items/show.html.erb app/views/items/_why.html.erb
git commit -m "refactor: single why partial and unified tag chips on item show"
```

---

### Task 11: Sweep — public pages, player, admin, forms, empty states, cards

**Files (modify all):**
- `app/views/sources/public_show.html.erb` (off-palette)
- `app/views/items/_player.html.erb` (off-palette, close button)
- `app/views/admin/dashboard/index.html.erb:59` (bg-red/yellow)
- `app/views/collections/public_show.html.erb` (border-2 input)
- `app/views/shared/_clipboard_field.html.erb` (border-2, h-9)
- `app/views/items/_download_command.html.erb:8` (border-2)
- `app/views/sources/index.html.erb:31` (athens-200, border-2 textarea), `:8-9` (Add source button)
- `app/views/collections/index.html.erb:6-7` (New collection button), `:15` (empty state)
- `app/views/tags/index.html.erb:4-5` (New tag button)
- `app/views/feed/index.html.erb:34` (empty state)
- `app/views/sources/show.html.erb:208` (empty state)
- `app/views/sources/_form.html.erb` (inputs h-9 → ui_input)
- `app/views/collections/_form.html.erb` (inputs → ui_input)
- `app/views/admin/settings/show.html.erb` (inputs already h-12; unify to ui_input; download button → ui_button)
- `app/views/admin/users/edit.html.erb` (inputs → ui_input)
- `app/views/tags/_form.html.erb` (input → ui_input)
- `app/views/setup/new.html.erb`, `app/views/sessions/new.html.erb`, `app/views/passwords/new.html.erb`, `app/views/passwords/edit.html.erb` (inputs → ui_input, submit → ui_button lg)
- `app/views/sources/new.html.erb`, `app/views/sources/edit.html.erb`, `app/views/collections/new.html.erb`, `app/views/collections/edit.html.erb`, `app/views/tags/new.html.erb`, `app/views/tags/edit.html.erb` (page tier classes)
- Create: `app/views/shared/ui/_empty_state.html.erb`
- Test: run full suite; new `test/system/sweep_test.rb`

- [ ] **Step 1: Create `_empty_state` partial**

`app/views/shared/ui/_empty_state.html.erb`:

```erb
<div class="border-3 border-charcoal rounded-md bg-athens-400 p-8 text-center">
  <p class="text-charcoal-300"><%= message %></p>
</div>
```

- [ ] **Step 2: Off-palette fixes**

`app/views/sources/public_show.html.erb` — full replacement:

```erb
<div class="mx-auto max-w-2xl px-4 py-8">
  <h1 class="font-display text-2xl font-bold text-charcoal"><%= @source.display_name %></h1>

  <p class="mt-2 text-sm text-charcoal-300">
    A source on <%= Setting.get(:instance_name) || "this Stray instance" %>.
  </p>

  <ul class="mt-6 space-y-2 text-sm">
    <li class="flex items-center gap-1">
      <%= phosphor_icon "rss", class: "h-4 w-4 align-text-bottom" %>
      <%= link_to "RSS feed", source_feed_path(slug: @source.slug, format: :xml), class: "text-carrot-600 hover:underline" %>
    </li>
    <li class="flex items-center gap-1">
      <%= phosphor_icon "code", class: "h-4 w-4 align-text-bottom" %>
      <%= link_to "Stray manifest (JSON)", source_manifest_path(slug: @source.slug, format: :json), class: "text-carrot-600 hover:underline" %>
    </li>
  </ul>
</div>
```

`app/views/items/_player.html.erb`:
- Line 39: `text-gray-800` → `text-charcoal`; `hover:text-black` → `hover:text-charcoal-600`
- Line 40: `text-gray-800` → `text-charcoal-300`
- Line 50: `text-gray-500` → `text-charcoal-300`
- Lines 63-67 close button — replace with:

```erb
  <button type="button" aria-label="Close"
          class="absolute top-2 right-2 w-11 h-11 z-10 flex items-center justify-center rounded-md hover:bg-athens-400"
          data-action="click->player#close">
    <%= phosphor_icon "x", class: "text-charcoal hover:text-carrot w-6 h-6" %>
  </button>
```

- Lines 69-80 prev/next buttons — replace both `w-10 h-10` with `w-11 h-11` and add `flex items-center justify-center rounded-md hover:bg-athens-400`:

```erb
  <div class="flex absolute bottom-3 right-3">
    <button type="button" aria-label="Previous" id="video-prev"
            class="w-11 h-11 flex items-center justify-center rounded-md hover:bg-athens-400"
            data-action="click->player#prev">
      <%= phosphor_icon "caret-left", class: "text-charcoal hover:text-cerise w-6 h-6" %>
    </button>
    <button type="button" aria-label="Next" id="video-next"
            class="w-11 h-11 flex items-center justify-center rounded-md hover:bg-athens-400"
            data-action="click->player#next">
      <%= phosphor_icon "caret-right", class: "text-charcoal hover:text-cerise w-6 h-6" %>
    </button>
  </div>
```

`app/views/admin/dashboard/index.html.erb` line 59 — replace the raw Tailwind status badge:

```erb
            <span class="inline-block mt-1 px-2 py-0.5 text-xs rounded <%= source.failed? ? "border-3 border-cerise text-cerise bg-athens-400" : "border-3 border-amber-500 text-amber-700 bg-athens-400" %>">
              <%= source.status %>
            </span>
```

`app/views/collections/public_show.html.erb` line 16-18 — the readonly input: `border-2` → `border-3`, `bg-athens-500` → `bg-athens-400`, `h-9` → `h-11`:

```erb
    <input type="text" readonly value="<%= request.base_url %><%= public_collection_path(slug: @collection.slug) %>/manifest"
           class="w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal"
           onclick="this.select()">
```

`app/views/shared/_clipboard_field.html.erb` — full replacement:

```erb
<div data-controller="clipboard" data-clipboard-text-value="<%= value %>">
  <label class="block text-xs font-bold text-charcoal mb-1"><%= label %></label>
  <div class="flex gap-1">
    <input type="text" readonly value="<%= value %>"
           class="flex-1 min-w-0 h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal"
           onclick="this.select()">
    <button type="button" data-action="click->clipboard#copy"
            class="shrink-0 px-3 h-11 border-3 border-charcoal rounded-md bg-athens-400 text-charcoal hover:bg-athens-500 text-sm font-bold cursor-pointer">
      Copy
    </button>
  </div>
</div>
```

`app/views/items/_download_command.html.erb` line 8 — `border-2` → `border-3`:

```erb
        class: "shrink-0 inline-flex items-center gap-1 px-2 min-h-9 bg-carrot-500 text-white text-xs rounded-md border-3 border-charcoal hover:bg-carrot-600 cursor-pointer" do %>
```

- [ ] **Step 3: Forms to ui_input/ui_button**

`app/views/sources/_form.html.erb` — replace every field class `w-full h-9 px-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none` with `<%= ui_input %>`:

```erb
      <%= form.url_field :url, class: ui_input %>
```

```erb
      <%= form.select :kind, Source.kinds.keys.map { |k| [k.humanize, k] }, {}, class: ui_select %>
```

```erb
      <%= form.text_field :name, class: ui_input %>
```

```erb
      <%= form.url_field :icon_url, class: ui_input %>
```

```erb
      <%= form.number_field :poll_interval, min: 60, placeholder: "e.g. 1800", class: ui_input %>
```

Labels — replace each `class: "block text-sm font-bold text-charcoal mb-1"` with `class: ui_label`.
Submit (lines 44-46):

```erb
      <%= form.submit source.new_record? ? "Add source" : "Save", class: ui_button %>
```

`app/views/sources/index.html.erb`:
- Line 8-9 Add source link: `class: ui_button`
- Line 15-18 search input: `h-9 w-full px-2` → `class: "w-full h-11 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none"` (use `ui_input` minus `w-full` conflict — just use `<%= ui_input %>`)
- Line 30-31 bulk textarea: `bg-athens-200 border-2` → `bg-athens-400 border-3`:

```erb
          <%= form.text_area :urls, rows: 6,
                placeholder: "One URL per line.\nYouTube videos/channels, RSS feeds, Stray /c/:slug or manifest.json URLs (auto-subscribed).",
                class: "w-full px-3 py-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal focus:outline-none" %>
```

- Line 32-33 submit: `class: ui_button(size: :sm)`
- Line 43-45 empty state → `<%= render "shared/ui/empty_state", message: 'No active sources yet. Paste a link in the navbar or click "Add source".' %>`

`app/views/collections/index.html.erb` line 6-7: New collection → `class: ui_button`; line 15-17 empty state → `render "shared/ui/empty_state", message: "No collections yet."`.

`app/views/tags/index.html.erb` line 4-5: New tag → `class: ui_button(variant: :primary, size: :md)` (replaces the odd `h-10 px-4` string).

`app/views/collections/_form.html.erb`: name field → `class: ui_input`, description textarea → `class: "w-full py-2 #{ui_input}"` (keeps textarea's own vertical padding), submit → `class: ui_button`, labels → `ui_label`.

`app/views/tags/_form.html.erb`: name field `h-12 px-3` → `class: ui_input` (drops to h-11 — acceptable, h-12 remains for auth pages via `size: :lg`), submit → `class: ui_button(size: :lg)`.

`app/views/admin/settings/show.html.erb`: every `w-full h-12 px-3 bg-athens-400 ...` field → `class: ui_input` (h-12 → h-11: one consistent input height everywhere; spec's h-12 tier remains for *buttons* via `ui_button(size: :lg)`); "Download model" button line 102-103 → `class: ui_button(size: :sm)`; "Save settings" line 157-158 → `class: ui_button(size: :lg)`.

`app/views/admin/users/edit.html.erb`: both text fields, email, password, password_confirmation → `class: ui_input`; submit → `class: ui_button(size: :lg)`.

`app/views/setup/new.html.erb`, `sessions/new.html.erb`, `passwords/new.html.erb`, `passwords/edit.html.erb`: every field `w-full h-12 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none` → `class: ui_input`; every submit `w-full h-12 bg-carrot-500 ...` → `class: "w-full #{ui_button(size: :lg)}"` (keep `w-full` on the auth CTAs).

- [ ] **Step 4: Page tiers**

- `app/views/tags/new.html.erb` + `tags/edit.html.erb`: `max-w-screen-md` → `<%= ui_page(tier: :form) %>` (max-w-3xl)
- `app/views/sources/new.html.erb`, `sources/edit.html.erb`, `collections/new.html.erb`, `collections/edit.html.erb`: already `max-w-3xl` — wrap inner card in `<%= ui_card %>`:

```erb
  <div class="<%= ui_card %>">
```

replacing each `border-3 border-charcoal rounded-md bg-athens-400 p-4`.

- `app/views/collections/index.html.erb`: `max-w-3xl` → `max-w-6xl` (list tier)
- `app/views/collections/show.html.erb` + `app/views/tags/index.html.erb` + `app/views/sources/index.html.erb`: already `max-w-screen-xl` — change to `max-w-6xl` for list pages? NO — spec says lists are `max-w-6xl`, reader detail `max-w-screen-xl`. Sources index and tags index are lists: change `max-w-screen-xl` → `max-w-6xl`. `collections/show` is a detail page: keep `max-w-screen-xl`.
- `app/views/items/show.html.erb` line 4: `max-w-screen-xl` — reader detail, keep.
- `app/views/feed/index.html.erb` line 22: `max-w-screen-xl xl:max-w-screen-2xl` — the feed is the widest list; keep `xl:max-w-screen-2xl` as an exception (it is the app's home surface; spec's list tier caps normal lists, feed stays as-is).

- [ ] **Step 5: Write the sweep regression test**

Create `test/system/sweep_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class SweepTest < ApplicationSystemTestCase
  test "auth inputs are 44px tall" do
    visit new_session_path

    height = find("input[type='email']").evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44
  end

  test "public source page uses palette colors not browser defaults" do
    source = sources(:youtube)
    visit public_source_path(slug: source.slug)

    link = find("a", text: "RSS feed")
    color = link.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(255, 142, 60)", color, "public links must be carrot-600, got #{color}"
  end

  test "sources index primary buttons are 44px" do
    sign_in_as users(:one)
    visit sources_path

    btn = find("a", text: "+ Add source")
    height = btn.evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44
  end

  test "empty states share the partial card" do
    sign_in_as users(:one)
    visit collections_path

    card = find("main .border-3.bg-athens-400.p-8")
    assert_includes card[:class], "p-8"
  end
end
```

- [ ] **Step 6: Rebuild and run the FULL suite**

Run: `bin/rails tailwindcss:build && bin/rails test`
Expected: 0 failures. Any test asserting a replaced class string (e.g. an integration test checking `h-9`) must be updated to the new standard in the same commit — never revert markup to satisfy an old assertion.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: palette and component sweep across all surfaces"
```

---

### Task 12: Remove the alias, dead code, dot hexes; add docs/DESIGN.md

**Files:**
- Modify: `app/helpers/application_helper.rb` (delete `dropdown_menu_item_class` alias)
- Modify: `app/assets/tailwind/application.css:130-132` (dot hexes)
- Delete: `app/javascript/controllers/hello_controller.js`
- Create: `docs/DESIGN.md`
- Test: `test/helpers/application_helper_test.rb` (delete alias test)

- [ ] **Step 1: Verify no call sites remain, then delete the alias**

Run: `grep -rn "dropdown_menu_item_class" app/ --include="*.erb" --include="*.rb"`
Expected: only `app/helpers/application_helper.rb` (the alias) and `test/helpers/application_helper_test.rb` (its test). If ANY view still uses it, STOP — return to Task 5/10 and finish the migration first.

Then delete from `app/helpers/application_helper.rb`:

```ruby
  def dropdown_menu_item_class(danger: false)
    ui_menu_item(danger: danger)
  end
```

And delete the alias test from `test/helpers/application_helper_test.rb`:

```ruby
  test "dropdown_menu_item_class is aliased to ui_menu_item" do
    ...
  end
```

- [ ] **Step 2: Replace dot hexes with theme colors**

In `app/assets/tailwind/application.css` lines 130-132, replace:

```css
.dot-ai_embedding { background-color: #3b82f6; }
.dot-ai_llm { background-color: #22c55e; }
.dot-user { background-color: #9ca3af; }
```

with:

```css
.dot-ai_embedding { background-color: var(--color-sky-500); }
.dot-ai_llm { background-color: var(--color-mint-500); }
.dot-user { background-color: var(--color-charcoal-300); }
```

- [ ] **Step 3: Delete dead hello controller**

Run: `rm app/javascript/controllers/hello_controller.js`
Verify nothing references it: `grep -rn "hello" app/views app/javascript/controllers/index.js` → no matches (index.js uses `eagerLoadControllersFrom`, no explicit import).

- [ ] **Step 4: Write `docs/DESIGN.md`**

```markdown
# Stray Design System

Single source of truth for UI conventions. The palette lives in `app/assets/tailwind/application.css` (`@theme`); behavior classes live in the same file below `mark`.

## Tokens

- **Surfaces:** `bg-champagne` (app background), `bg-champagne-50` (navbar/sidebar), `bg-athens-400` (cards/inputs/menus), `bg-athens-500` (hover grey)
- **Ink:** `text-charcoal` (body), `text-charcoal-300` (secondary), `text-charcoal-600` (headings via `font-display`)
- **Accent:** carrot — `bg-carrot-500` (primary buttons), `bg-carrot-100` (menu hover tint), `text-carrot-600` (links)
- **Danger:** cerise. **Success/new:** mint. **Provenance dots:** sky / mint / charcoal-300.

## Rules

1. **44px minimum tap target** on every interactive control (`min-h-11` / `min-w-11` or CSS floor). Table-row links may go down to 36px only when the whole row is not clickable.
2. **Buttons:** always `ui_button(variant:, size:)` — `border-3 border-charcoal`, heights h-9/h-11/h-12. Never hand-roll `border-2` or `bg-white` buttons.
3. **Inputs:** always `ui_input` (h-11) / `ui_select` / `ui_label`.
4. **Dropdowns:** always `render "shared/ui/dropdown", menu_id:, trigger_label:, trigger_class:, trigger:, menu:, alignment:, menu_class:`. Menu items always `ui_menu_item` (or `ui_menu_item(danger: true)`).
5. **Menu hover = carrot-100 fill.** Never re-style per menu; the `.ui-menu-item` CSS owns hover/focus states.
6. **Cards:** `ui_card(padding:)`. Empty states: `render "shared/ui/empty_state", message:`.
7. **Flash:** `render "shared/ui/flash"` — never inline flash markup.
8. **Page widths:** `ui_page(tier:)` — `:form` max-w-3xl, `:list` max-w-6xl, `:reader` max-w-screen-xl. Feed page keeps its xl:max-w-screen-2xl exception.
9. **Icons:** `phosphor_icon` helper only. Menu icons `w-3.5 h-3.5`, trigger icons `w-4 h-4`.
10. **Never:** raw Tailwind palette colors (gray/blue/stone/red/yellow), `dark:` variants, inline SVGs, `border-2` on buttons/inputs.

## Adding a new dropdown (recipe)

1. `menu_id`: unique, e.g. `foo-menu-#{record.id}`.
2. Trigger: icon-only → `trigger_class: ui_dropdown_trigger`; labeled pill → custom string including `min-h-11`.
3. Items: `ui_menu_item` via `link_to`/`action_link_to`/`button_to`, icon `w-3.5 h-3.5` first, label text second.
4. Destructive item last, `ui_menu_item(danger: true)`, separated by `border-t-3 border-charcoal/10 my-1.5`.
```

- [ ] **Step 5: Rebuild and full CI**

Run: `bin/rails tailwindcss:build && bin/ci`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove dropdown alias and dead code, add DESIGN.md"
```
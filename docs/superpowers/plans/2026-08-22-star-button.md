# Star Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible star toggle to the inline player and item details page, plus a display-only star badge on saved-item thumbnails, driven by a shared partial that the existing PATCH flow updates via Turbo Stream.

**Architecture:** A new `_star_button` partial renders an `action_link_to` to the existing `PATCH /items/:id` endpoint with `state: saved`/`unseen`. It wraps the link in a stable `item_star_<id>` element so `update.turbo_stream.erb` can `turbo_stream.replace` it on toggle. Two variants: default (icon-only inline button) and `:menu` (block dropdown item with label). The thumbnail badge is plain server-rendered markup in `_item.html.erb`, refreshed by the existing full-card `turbo_stream.replace dom_id(item)`.

**Tech Stack:** Rails 8, Hotwire (Turbo Stream), Minitest, phosphor_icon helper, action_link_to helper.

---

### Task 1: Shared star button partial

**Files:**
- Create: `app/views/items/_star_button.html.erb`

- [ ] **Step 1: Create the partial with both variants**

```erb
<%
  variant = local_assigns.fetch(:variant, :button)
  star_classes = variant == :menu ?
    "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500" :
    "text-charcoal-300 hover:text-carrot-500 hover:bg-athens-500 rounded-md bg-transparent border-none cursor-pointer p-2 min-w-9 min-h-9 inline-flex items-center justify-center focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500 focus-visible:outline-offset-1"
  wrapper_tag = variant == :menu ? :div : :span
  wrapper_class = variant == :menu ? "block" : "inline-flex"
  icon_size = variant == :menu ? "w-3.5 h-3.5" : "w-4 h-4"
%>
<%= content_tag wrapper_tag, id: "item_star_#{item.id}", class: wrapper_class do %>
  <%= action_link_to item_path(item), method: :patch,
        params: { state: item.saved? ? "unseen" : "saved" },
        data: { turbo_stream: true },
        aria: { pressed: item.saved?, label: item.saved? ? "Unstar" : "Star" },
        title: item.saved? ? "Unstar" : "Star",
        class: star_classes do %>
    <%= phosphor_icon "star", style: item.saved? ? :fill : :regular, class: icon_size %>
    <% if variant == :menu %>
      <%= item.saved? ? "Unstar" : "Star" %>
    <% end %>
  <% end %>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/items/_star_button.html.erb
git commit -m "feat: add shared _star_button partial with button and menu variants"
```

---

### Task 2: Replace inline star entry in actions menu with the partial

**Files:**
- Modify: `app/views/items/_actions_menu.html.erb:24-29`

- [ ] **Step 1: Replace the inline action_link_to star block with the partial render**

Replace lines 24-29 (the `action_link_to item_path(item), method: :patch, params: { state: ... }` block for Save/Unsave) with:

```erb
<%= render "items/star_button", item: item, variant: :menu %>
```

The surrounding markup (the menu `<div>` and the following `<% if item.unseen? %>` "Mark as seen" block) stays untouched.

- [ ] **Step 2: Run the existing controller test for saving**

Run: `bin/rails test test/controllers/items_controller_test.rb -n test_saving_an_item_creates_a_starred_interaction_and_nudges_weight_up`
Expected: PASS (controller behavior unchanged)

- [ ] **Step 3: Run the existing system test for menu labels**

Run: `bin/rails test:system test/system/item_state_visuals_test.rb`
Expected: PASS (the "Mark as seen" and "Hide from feed" assertions still hold; the menu now renders "Star"/"Unstar" instead of "Save"/"Unsave" but no existing test asserts those exact labels)

- [ ] **Step 4: Commit**

```bash
git add app/views/items/_actions_menu.html.erb
git commit -m "refactor: actions menu uses shared _star_button partial"
```

---

### Task 3: Star button on the inline player

**Files:**
- Modify: `app/views/items/_player.html.erb:18-24`

- [ ] **Step 1: Write the failing system test**

Append to `test/system/item_show_test.rb` (inside the `ItemShowTest` class, before the final `end`):

```ruby
  test "inline player shows a star toggle button next to the title" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit root_path
    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    within "#item_star_#{item.id}" do
      assert_selector "a[aria-label='Star']"
      assert_selector "a[aria-pressed='false']"
    end
  end

  test "clicking the player star toggle saves the item and flips to filled" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit root_path
    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    within "#item_star_#{item.id}" do
      find("a[aria-label='Star']").click
      assert_selector "a[aria-label='Unstar']", wait: 3
      assert_selector "a[aria-pressed='true']"
    end
    assert item.reload.saved?
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test:system test/system/item_show_test.rb -n "/star_toggle/"`
Expected: FAIL — no `#item_star_` element on the player page

- [ ] **Step 3: Add the star button to the player title row**

In `app/views/items/_player.html.erb`, replace lines 18-24:

```erb
    <div class="flex items-start gap-2 mb-1">
      <a class="block text-lg font-semibold hover:underline md:text-xl flex-1 min-w-0"
         href="<%= item.url %>" target="_blank" rel="noopener">
        <%= item.title %>
      </a>
      <%= render "items/actions_menu", item: item %>
    </div>
```

with:

```erb
    <div class="flex items-start gap-2 mb-1">
      <a class="block text-lg font-semibold hover:underline md:text-xl flex-1 min-w-0"
         href="<%= item.url %>" target="_blank" rel="noopener">
        <%= item.title %>
      </a>
      <%= render "items/star_button", item: item %>
      <%= render "items/actions_menu", item: item %>
    </div>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test:system test/system/item_show_test.rb -n "/star_toggle/"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/views/items/_player.html.erb test/system/item_show_test.rb
git commit -m "feat: star toggle button on the inline player"
```

---

### Task 4: Star button on the details page

**Files:**
- Modify: `app/views/items/show.html.erb:17-21`

- [ ] **Step 1: Write the failing system test**

Append to `test/system/item_show_test.rb` (before the final `end`):

```ruby
  test "details page shows a star toggle in the meta row for an unsaved item" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit item_path(item)

    within "#item_star_#{item.id}" do
      assert_selector "a[aria-label='Star']"
      assert_selector "a[aria-pressed='false']"
    end
  end

  test "clicking the details page star toggle saves the item and reflects after reload" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit item_path(item)

    within "#item_star_#{item.id}" do
      find("a[aria-label='Star']").click
      assert_selector "a[aria-label='Unstar']", wait: 3
    end
    assert item.reload.saved?

    visit item_path(item)
    within "#item_star_#{item.id}" do
      assert_selector "a[aria-label='Unstar']"
      assert_selector "a[aria-pressed='true']"
    end
  end

  test "details page star toggle reflects saved state on initial load" do
    sign_in_as(users(:one))
    item = items(:video_saved)
    assert item.saved?

    visit item_path(item)

    within "#item_star_#{item.id}" do
      assert_selector "a[aria-label='Unstar']"
      assert_selector "a[aria-pressed='true']"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test:system test/system/item_show_test.rb -n "/details_page/"`
Expected: FAIL — no `#item_star_` on the details page

- [ ] **Step 3: Add the star button to the details page meta row**

In `app/views/items/show.html.erb`, the meta row (lines 17-21) currently:

```erb
      <%= link_to @item.url, target: "_blank", rel: "noopener",
            class: "inline-flex items-center gap-1 text-carrot-600 hover:underline" do %>
        Open at source <%= phosphor_icon "arrow-up-right", class: "w-3 h-3" %>
      <% end %>
      <%= render "items/actions_menu", item: @item %>
```

Replace with:

```erb
      <%= link_to @item.url, target: "_blank", rel: "noopener",
            class: "inline-flex items-center gap-1 text-carrot-600 hover:underline" do %>
        Open at source <%= phosphor_icon "arrow-up-right", class: "w-3 h-3" %>
      <% end %>
      <%= render "items/star_button", item: @item %>
      <%= render "items/actions_menu", item: @item %>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test:system test/system/item_show_test.rb -n "/details_page/"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/views/items/show.html.erb test/system/item_show_test.rb
git commit -m "feat: star toggle button on the item details page"
```

---

### Task 5: Thumbnail star badge for saved items

**Files:**
- Modify: `app/views/items/_item.html.erb:25-27`

- [ ] **Step 1: Write the failing system test**

Append to `test/system/item_state_visuals_test.rb` (before the final `end`):

```ruby
  test "saved item shows a filled star badge in the top-left of the thumbnail" do
    sign_in_as(users(:one))
    item = items(:video_saved)
    assert item.saved?

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      assert_selector "span[title='Starred'].absolute.top-2.left-2", count: 1
    end
  end

  test "unsaved item does not show a star badge on the thumbnail" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert_not item.saved?

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      assert_no_selector "span[title='Starred']"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test:system test/system/item_state_visuals_test.rb -n "/star_badge/"`
Expected: FAIL — no `[title='Starred']` element on the thumbnail

- [ ] **Step 3: Add the star badge to the thumbnail**

In `app/views/items/_item.html.erb`, the unseen dot block (lines 25-27) currently:

```erb
      <% if item.unseen? %>
        <span class="absolute top-2 right-2 w-2.5 h-2.5 rounded-full bg-mint ring-2 ring-charcoal/50"></span>
      <% end %>
```

Replace with:

```erb
      <% if item.saved? %>
        <span class="absolute top-2 left-2 text-carrot-500 drop-shadow-sm" title="Starred">
          <%= phosphor_icon "star", style: :fill, class: "w-4 h-4" %>
        </span>
      <% end %>
      <% if item.unseen? %>
        <span class="absolute top-2 right-2 w-2.5 h-2.5 rounded-full bg-mint ring-2 ring-charcoal/50"></span>
      <% end %>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test:system test/system/item_state_visuals_test.rb -n "/star_badge/"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/views/items/_item.html.erb test/system/item_state_visuals_test.rb
git commit -m "feat: star badge on thumbnails for saved items"
```

---

### Task 6: Turbo Stream replaces the star button on toggle

**Files:**
- Modify: `app/views/items/update.turbo_stream.erb`

- [ ] **Step 1: Write the failing controller test**

Append to `test/controllers/items_controller_test.rb` (before the final `end`):

```ruby
  test "saved-state turbo stream response replaces the item_star element" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(turbo-stream action="replace" target="item_star_#{item.id}")
  end

  test "hidden-state turbo stream response does not replace item_star" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "hidden" }, as: :turbo_stream

    assert_response :success
    assert_not_includes response.body, %(target="item_star_#{item.id}")
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/controllers/items_controller_test.rb -n "/item_star/"`
Expected: FAIL — response does not yet include the `item_star_` replace stream

- [ ] **Step 3: Extend the turbo stream template**

Replace `app/views/items/update.turbo_stream.erb` entirely with:

```erb
<% if state == "hidden" %>
  <%= turbo_stream.remove dom_id(item) %>
<% else %>
  <%= turbo_stream.replace dom_id(item) do %>
    <%= render "items/item", item: item %>
  <% end %>
  <%= turbo_stream.replace "item_star_#{item.id}" do %>
    <%= render "items/star_button", item: item %>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run the controller tests to verify they pass**

Run: `bin/rails test test/controllers/items_controller_test.rb -n "/item_star/"`
Expected: PASS

- [ ] **Step 5: Run the full items controller test suite to confirm no regressions**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add app/views/items/update.turbo_stream.erb test/controllers/items_controller_test.rb
git commit -m "feat: turbo stream replaces item_star element on state toggle"
```

---

### Task 7: Full regression pass and lint

**Files:** none modified

- [ ] **Step 1: Run the full items test suite**

Run: `bin/rails test test/controllers/items_controller_test.rb && bin/rails test:system test/system/item_show_test.rb test/system/item_state_visuals_test.rb test/system/feed_flow_test.rb`
Expected: all PASS

- [ ] **Step 2: Run RuboCop on changed files**

Run: `bin/rubocop app/views/items/_star_button.html.erb app/views/items/_player.html.erb app/views/items/show.html.erb app/views/items/_item.html.erb app/views/items/_actions_menu.html.erb app/views/items/update.turbo_stream.erb test/system/item_show_test.rb test/system/item_state_visuals_test.rb test/controllers/items_controller_test.rb`
Expected: no offenses (ERB cops are minimal in this repo; if any style cops fire, fix and re-run)

- [ ] **Step 3: Commit any lint fixes (if needed)**

```bash
git add -A
git commit -m "style: rubocop fixes for star button"
```

(Skip this step if RuboCop reports no offenses.)

- [ ] **Step 4: Manual smoke check**

Run: `bin/dev`
Then in a browser: log in, open the feed, click a video to open the player, click the star icon next to the title, confirm:
1. The icon flips to filled (carrot).
2. Closing and reopening the player shows the filled star.
3. The thumbnail on the feed now shows a small filled star in the top-left.
4. Open the details page — the meta row star is filled.
5. Click it again — it returns to outline, and the thumbnail badge disappears after the card re-renders.
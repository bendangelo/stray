# Video Grid Feed with Inline Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the feed from a single-column list into a responsive 12-col video grid (2/3/4 cards per row) with inline video watching via a fetch-injected player fragment and CSS grid row repositioning, porting stray_video's proven Stimulus player controller pattern.

**Architecture:** The feed view changes from `max-w-3xl` single-column to `max-w-screen-xl` 12-col CSS grid. Each item card carries `data-player-target="video"` and `data-url` pointing to a new `ItemsController#player` endpoint that returns a layout-less HTML fragment (iframe embed + metadata + close/prev/next). A `player_controller.js` Stimulus controller manages: clicking a card fetches the fragment, injects it into a hidden full-width `playerBox` slot, repositions the slot via `gridRow` to appear below the clicked card's row, and supports prev/next navigation. Save/hide interactions remain unchanged (Turbo Stream). The source show page also gets the grid layout.

**Tech Stack:** Rails 8.1, Hotwire (Turbo + Stimulus via importmap), Tailwind CSS v4 (CSS-first config), `full_search` gem (FTS5), Pagy (pagination). No new gems.

**Spec:** `docs/superpowers/specs/2026-08-14-video-grid-inline-player-design.md`

---

## File Map

### Create
- `app/javascript/controllers/player_controller.js` — Stimulus controller (fetch + gridRow + prev/next)
- `app/views/items/_player.html.erb` — inline player fragment (iframe + metadata + close/prev/next)
- `test/helpers/application_helper_test.rb` — test `embed_url`, `pretty_duration`

### Modify
- `app/helpers/application_helper.rb` — add `embed_url`, `pretty_duration`, `missing_thumb`
- `config/routes.rb` — add `member { get :player }` to items
- `app/controllers/items_controller.rb` — add `player` action
- `app/views/feed/index.html.erb` — single-column → 12-col grid with player slot
- `app/views/items/_item.html.erb` — horizontal card → grid video card
- `app/views/sources/show.html.erb` — single-column → grid for items
- `test/controllers/items_controller_test.rb` — add player action tests
- `test/system/feed_flow_test.rb` — update for new card structure + test inline player

---

## Task 1: Add helper methods — `embed_url`, `pretty_duration`, `missing_thumb`

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Create: `test/helpers/application_helper_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/helpers/application_helper_test.rb`:

```ruby
require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "pretty_duration handles seconds under a minute" do
    assert_equal "0:45", pretty_duration(45)
  end

  test "pretty_duration handles minutes" do
    assert_equal "3:05", pretty_duration(185)
  end

  test "pretty_duration handles hours" do
    assert_equal "1:30:00", pretty_duration(5400)
  end

  test "pretty_duration returns empty string for nil" do
    assert_equal "", pretty_duration(nil)
  end

  test "pretty_duration returns empty string for zero" do
    assert_equal "", pretty_duration(0)
  end

  test "embed_url constructs YouTube embed URL" do
    source = sources(:youtube)
    item = items(:video_one)
    url = embed_url(item)
    assert_equal "https://www.youtube.com/embed/#{item.external_id}", url
  end

  test "embed_url returns nil for unknown source kind" do
    source = sources(:bitchute)
    item = items(:video_saved)
    # Bitchute should return an embed URL
    url = embed_url(item)
    assert_equal "https://www.bitchute.com/embed/#{item.external_id}", url
  end

  test "missing_thumb returns a data URI" do
    assert_match(/^data:image\/svg\+xml/, missing_thumb)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'pretty_duration'`

- [ ] **Step 3: Add helper methods**

Replace the entire `app/helpers/application_helper.rb` with:

```ruby
module ApplicationHelper
  def time_ago(time)
    return "" if time.nil?

    seconds = Time.current - time
    if seconds < 60
      "just now"
    elsif seconds < 3600
      "#{(seconds / 60).to_i}m ago"
    elsif seconds < 86400
      "#{(seconds / 3600).to_i}h ago"
    elsif seconds < 604800
      "#{(seconds / 86400).to_i}d ago"
    else
      time.strftime("%b %d, %Y")
    end
  end

  def pretty_duration(seconds)
    return "" if seconds.nil? || seconds <= 0

    if seconds >= 3600
      "%d:%02d:%02d" % [ seconds / 3600, (seconds / 60) % 60, seconds % 60 ]
    else
      "%d:%02d" % [ seconds / 60, seconds % 60 ]
    end
  end

  def embed_url(item)
    case item.source.kind
    when "youtube_channel"
      "https://www.youtube.com/embed/#{item.external_id}"
    when "video_channel"
      uri = begin
        URI.parse(item.url)
      rescue URI::InvalidURIError
        nil
      end
      if uri&.host&.include?("bitchute.com")
        "https://www.bitchute.com/embed/#{item.external_id}"
      else
        nil
      end
    else
      nil
    end
  end

  def missing_thumb
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='180' fill='%233E3E3E'%3E%3Crect width='320' height='180'/%3E%3C/svg%3E"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/helpers/application_helper_test.rb`
Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/application_helper.rb test/helpers/application_helper_test.rb
git commit -m "feat: add embed_url, pretty_duration, missing_thumb helpers"
```

---

## Task 2: Add player route and ItemsController#player action

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/items_controller.rb`
- Modify: `test/controllers/items_controller_test.rb`

- [ ] **Step 1: Write the failing test**

Add these tests to `test/controllers/items_controller_test.rb` (at the end, before the closing `end`):

```ruby
  test "player returns HTML fragment for valid item" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get player_item_path(item)

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "youtube.com/embed"
  end

  test "player returns 404 for other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    get player_item_path(item)

    assert_response :not_found
  end

  test "player returns 404 for missing item" do
    sign_in_as(users(:one))

    get player_item_path(id: 99999)

    assert_response :not_found
  end

  test "player requires authentication" do
    item = items(:video_one)

    get player_item_path(item)

    assert_redirected_to new_session_path
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'player_item_path'`

- [ ] **Step 3: Add route**

In `config/routes.rb`, replace the `resources :items` line:

```ruby
  resources :items, only: [ :update ] do
    member { get :player }
  end
```

- [ ] **Step 4: Add player action to ItemsController**

Replace the entire `app/controllers/items_controller.rb` with:

```ruby
class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze

  def player
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    render "items/player", locals: { item: }, layout: false
  end

  def update
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    state = params[:state]
    return head :bad_request unless ALLOWED_STATES.include?(state)

    item.update!(state: state)

    respond_to do |format|
      format.turbo_stream { render "items/update", locals: { item:, state: } }
      format.html { redirect_to root_path }
    end
  end
end
```

- [ ] **Step 5: Create a minimal player view (placeholder, full version in Task 4)**

Create `app/views/items/_player.html.erb`:

```erb
<div class="flex relative py-10 max-w-screen-lg mx-auto">
  <div class="flex-1 ml-3">
    <p class="text-lg font-semibold"><%= item.title %></p>
    <p class="text-sm text-gray-500"><%= embed_url(item) %></p>
  </div>
</div>
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: all 8 tests PASS (4 existing + 4 new).

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/items_controller.rb app/views/items/_player.html.erb test/controllers/items_controller_test.rb
git commit -m "feat: add ItemsController#player action and route for inline player"
```

---

## Task 3: Create player Stimulus controller

**Files:**
- Create: `app/javascript/controllers/player_controller.js`

- [ ] **Step 1: Write the player controller**

Create `app/javascript/controllers/player_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "playerBox", "video" ]

  connect() {
    this.detailPaneOpen = false
    this.currentVideo = -1
  }

  toggle(event) {
    const videoId = this.videoTargets.findIndex((el) => {
      const aTag = el.querySelector("a")
      return aTag == event.currentTarget
    })

    if (videoId == this.currentVideo) {
      this.closeDetailPane()
    } else {
      this.openDetailPane(videoId)
    }

    this.updateView()
  }

  close(event) {
    this.closeDetailPane()
    this.updateView()
  }

  closeDetailPane() {
    this.detailPaneOpen = false
    this.currentVideo = -1
  }

  openDetailPane(videoId) {
    this.detailPaneOpen = true
    this.currentVideo = videoId
  }

  prev(event) {
    if (this.currentVideo > 0) {
      this.currentVideo--
    }
    this.moveFocus(event.target, "prev")
    this.updateView()
  }

  next(event) {
    if (this.currentVideo < this.videoTargets.length - 1) {
      this.currentVideo++
    }
    this.moveFocus(event.target, "next")
    this.updateView()
  }

  moveFocus(target, action) {
    const buttons = document.querySelectorAll("[data-action*='player#prev'], [data-action*='player#next']")
    if (buttons.length > 0) {
      buttons[0].focus()
    }
  }

  updateView() {
    const playerBox = this.playerBoxTarget
    const videoTarget = this.videoTargets[this.currentVideo]

    if (this.detailPaneOpen && videoTarget) {
      const videoUrl = videoTarget.getAttribute("data-url")
      this.fetchPlayer(videoUrl).then(() => {
        const prevButton = document.getElementById("video-prev")
        if (prevButton) {
          prevButton.disabled = this.currentVideo === 0
          prevButton.classList.toggle("hidden", prevButton.disabled)
        }
        const nextButton = document.getElementById("video-next")
        if (nextButton) {
          nextButton.disabled = this.currentVideo === this.videoTargets.length - 1
          nextButton.classList.toggle("hidden", nextButton.disabled)
        }
      })
      playerBox.classList.remove("hidden")
    } else {
      playerBox.classList.add("hidden")
    }

    if (this.detailPaneOpen && videoTarget) {
      const minWidths = [ 640, 768, 1024 ]
      const matchedWidths = minWidths.filter((width) => {
        return window.matchMedia(`(min-width: ${width}px)`).matches
      })
      const videosPerRow = 2 + matchedWidths.length
      const moveToRow = 1 + Math.ceil((this.currentVideo + 1) / videosPerRow)
      playerBox.style.gridRow = moveToRow

      videoTarget.scrollIntoView({ block: "center", behavior: "smooth" })
    }

    this.videoTargets.forEach((btn, i) => {
      const img = btn.querySelector("img")
      if (img) {
        const activeClass = "border-2"
        img.classList.toggle(activeClass, i === this.currentVideo && this.detailPaneOpen)
      }
    })
  }

  fetchPlayer(url) {
    return fetch(url)
      .then((response) => {
        if (!response.ok) throw new Error(response.statusText)
        return response.text()
      })
      .then((html) => {
        this.playerBoxTarget.innerHTML = html
      })
      .catch((error) => {
        this.playerBoxTarget.innerHTML = "<p class='p-8 text-center text-cerise'>Error loading video</p>"
      })
  }
}
```

- [ ] **Step 2: Verify it loads without errors**

Run: `bin/rails runner "puts 'OK'"`
Expected: `OK` (the JS file isn't loaded by Rails runner, but confirms no Ruby syntax issues exist alongside).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/player_controller.js
git commit -m "feat: add player Stimulus controller for inline video watching"
```

---

## Task 4: Create full player fragment view

**Files:**
- Modify: `app/views/items/_player.html.erb`

- [ ] **Step 1: Replace the placeholder player view with the full version**

Replace `app/views/items/_player.html.erb` with:

```erb
<div class="flex relative py-10 max-w-screen-lg mx-auto">
  <% if embed_url(item) %>
    <iframe width="400" height="230"
            src="<%= embed_url(item) %>"
            title="<%= item.title %>"
            frameborder="0"
            class="rounded-md border-3 border-charcoal"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
    </iframe>
  <% elsif item.thumbnail_url.present? %>
    <img class="object-cover lg:mx-6 lg:w-1/2 h-72 lg:h-96 rounded-md border-3 border-charcoal"
         src="<%= item.thumbnail_url %>" alt="<%= item.title %>">
  <% end %>

  <div class="flex-1 ml-3 mr-9">
    <a class="block text-lg font-semibold hover:underline md:text-xl mb-1"
       href="<%= item.url %>" target="_blank" rel="noopener">
      <%= item.title %>
    </a>

    <% if item.source.name.present? %>
      <div class="flex mb-3">
        <div>
          <%= link_to item.source.name, source_path(item.source),
            class: "text-gray-800 text-sm hover:text-black hover:underline" %>
          <p class="text-gray-800 text-xs mt-1">
            <%= time_ago(item.published_at) %>
            <% if item.duration.present? %>
              · <%= pretty_duration(item.duration) %>
            <% end %>
          </p>
        </div>
      </div>
    <% end %>

    <% if item.content_text.present? %>
      <p class="text-sm text-gray-500 md:text-sm whitespace-pre-line">
        <%= truncate(item.content_text, length: 500) %>
      </p>
    <% end %>

    <div class="flex gap-1 mt-3">
      <% if item.saved? %>
        <%= button_to item_path(item), method: :patch, params: { state: "unseen" },
          form: { data: { turbo_stream: true } },
          class: "text-amber-500 hover:text-amber-600 cursor-pointer bg-transparent border-none text-xs" do %>
          ★ Saved
        <% end %>
      <% else %>
        <%= button_to item_path(item), method: :patch, params: { state: "saved" },
          form: { data: { turbo_stream: true } },
          class: "text-charcoal-300 hover:text-amber-500 cursor-pointer bg-transparent border-none text-xs" do %>
          ☆ Save
        <% end %>
      <% end %>

      <%= button_to item_path(item), method: :patch, params: { state: "hidden" },
        form: { data: { turbo_stream: true } },
        class: "text-charcoal-300 hover:text-cerise cursor-pointer bg-transparent border-none text-xs" do %>
        ✕ Hide
      <% end %>
    </div>
  </div>

  <button type="button" aria-label="Close"
          class="absolute top-10 right-0 w-6 h-6"
          data-action="click->player#close">
    <svg class="text-charcoal hover:text-carrot w-full h-full" width="20" height="20" viewBox="0 0 20 20">
      <line x1="2" y1="2" x2="18" y2="18" stroke="currentColor" stroke-width="2"/>
      <line x1="2" y1="18" x2="18" y2="2" stroke="currentColor" stroke-width="2"/>
    </svg>
  </button>

  <div class="flex absolute bottom-3 -right-3">
    <button type="button" aria-label="Previous" id="video-prev"
            class="w-10 h-10"
            data-action="click->player#prev">
      <svg class="text-charcoal hover:text-cerise w-full h-full" width="20" height="20" viewBox="0 0 20 20">
        <polyline points="11,7 8,10 11,13" fill="none" stroke="currentColor" stroke-width="2"/>
      </svg>
    </button>
    <button type="button" aria-label="Next" id="video-next"
            class="w-10 h-10"
            data-action="click->player#next">
      <svg class="text-charcoal hover:text-cerise w-full h-full" width="20" height="20" viewBox="0 0 20 20">
        <polyline points="9,7 12,10 9,13" fill="none" stroke="currentColor" stroke-width="2"/>
      </svg>
    </button>
  </div>
</div>
```

- [ ] **Step 2: Run player controller tests**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: all 8 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/views/items/_player.html.erb
git commit -m "feat: add full inline player fragment with embed, metadata, and nav"
```

---

## Task 5: Rewrite item card partial for video grid

**Files:**
- Modify: `app/views/items/_item.html.erb`

- [ ] **Step 1: Replace the item card partial**

Replace the entire `app/views/items/_item.html.erb` with:

```erb
<div id="<%= dom_id(item) %>"
     class="col-span-6 sm:col-span-4 md:col-span-3"
     data-player-target="video"
     data-url="<%= player_item_path(item) %>">
  <div class="flex flex-col">
    <div class="relative overflow-hidden">
      <a href="#" data-action="click->player#toggle:prevent">
        <img class="group-hover:border-2 border-carrot-400 object-cover w-full h-40 rounded-md border-3 border-charcoal"
             src="<%= item.thumbnail_url || missing_thumb %>"
             alt="<%= item.title %>">
      </a>
      <% if item.duration.present? %>
        <p class="absolute right-2 bottom-2 bg-gray-900 text-gray-100 text-xs px-1 py rounded">
          <%= pretty_duration(item.duration) %>
        </p>
      <% end %>
    </div>

    <div class="flex mt-1 flex-col">
      <a href="<%= item.url %>" target="_blank" rel="noopener"
         class="hover:underline break-all text-charcoal text-sm font-semibold line-clamp-2">
        <%= item.title %>
      </a>

      <div class="flex items-center gap-2 mt-1 text-xs text-charcoal-300">
        <% if item.source.name.present? %>
          <%= link_to item.source.name, source_path(item.source), class: "hover:text-carrot-600 underline" %>
          <span>·</span>
        <% end %>
        <span><%= time_ago(item.published_at) %></span>
      </div>

      <div class="flex gap-1 mt-1">
        <% if item.saved? %>
          <%= button_to item_path(item), method: :patch, params: { state: "unseen" },
            form: { data: { turbo_stream: true } },
            class: "text-amber-500 hover:text-amber-600 cursor-pointer bg-transparent border-none text-xs" do %>
            ★ Saved
          <% end %>
        <% else %>
          <%= button_to item_path(item), method: :patch, params: { state: "saved" },
            form: { data: { turbo_stream: true } },
            class: "text-charcoal-300 hover:text-amber-500 cursor-pointer bg-transparent border-none text-xs" do %>
            ☆ Save
          <% end %>
        <% end %>

        <%= button_to item_path(item), method: :patch, params: { state: "hidden" },
          form: { data: { turbo_stream: true } },
          class: "text-charcoal-300 hover:text-cerise cursor-pointer bg-transparent border-none text-xs" do %>
          ✕ Hide
        <% end %>
      </div>
    </div>
  </div>
</div>
```

Key differences from the old card:
- `col-span-6 sm:col-span-4 md:col-span-3` for responsive grid
- `data-player-target="video"` + `data-url` for the player controller
- Thumbnail is dominant (`object-cover w-full h-40`), with `border-3 border-charcoal`
- Thumbnail `<a>` has `data-action="click->player#toggle:prevent"` (clicking opens player, no navigation)
- Duration badge overlaid on thumbnail (bottom-right)
- Title uses `line-clamp-2` to limit to 2 lines
- Save/hide are text links (`★ Saved` / `☆ Save` / `✕ Hide`), not icon SVGs

- [ ] **Step 2: Run existing item controller tests**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: all 8 tests PASS (save/hide still works via Turbo Stream — the `dom_id(item)` id is preserved on the outer div).

- [ ] **Step 3: Commit**

```bash
git add app/views/items/_item.html.erb
git commit -m "feat: rewrite item card as grid-friendly video card with player target"
```

---

## Task 6: Rewrite feed index view as video grid

**Files:**
- Modify: `app/views/feed/index.html.erb`

- [ ] **Step 1: Replace the feed index view**

Replace the entire `app/views/feed/index.html.erb` with:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
  <div class="mb-4">
    <h1 class="font-display text-2xl font-bold text-charcoal">Your Feed</h1>
  </div>

  <%= render "search" %>

  <% if @items.any? %>
    <div class="grid grid-cols-12 gap-y-4 max-w-screen-xl mx-auto mb-4 gap-x-2"
         data-controller="player">
      <div class="col-span-12 hidden border-y-3 border-charcoal"
           data-player-target="playerBox">
        <p class="p-4 text-center text-charcoal-300">Loading...</p>
      </div>

      <%= render partial: "items/item", collection: @items, as: :item %>
    </div>
  <% else %>
    <div class="border-3 border-charcoal rounded-md bg-athens-400 p-8 text-center">
      <p class="text-charcoal-300">
        <% if @q.present? %>
          No results for "<%= @q %>"
        <% else %>
          Your feed is empty. Add a link above to start following sources.
        <% end %>
      </p>
    </div>
  <% end %>

  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center gap-2 text-sm">
      <% if @pagy.previous %>
        <%= link_to "← Newer", root_path(page: @pagy.previous, q: @q),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
      <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", root_path(page: @pagy.next, q: @q),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
</main>
```

Key changes:
- `max-w-3xl` → `max-w-screen-xl` (wider for grid)
- Removed `turbo_frame_tag "feed_search"` wrapper — search form does a full page GET which is fine
- Single column → `grid grid-cols-12` with hidden `playerBox` + collection render
- Removed `data-controller="pagination"` (dead reference, no controller existed)
- Cards rendered as collection (`render partial:, collection:, as: :item`) — more efficient

- [ ] **Step 2: Run feed controller tests**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: all 5 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/views/feed/index.html.erb
git commit -m "feat: transform feed to 12-col video grid with inline player slot"
```

---

## Task 7: Update sources show view to use video grid

**Files:**
- Modify: `app/views/sources/show.html.erb`

- [ ] **Step 1: Replace the items section with a grid**

In `app/views/sources/show.html.erb`, replace the items section (lines 28-44):

```erb
  <div id="source_items">
    <% @items.each do |item| %>
      <%= render "items/item", item: item %>
    <% end %>
  </div>

  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center gap-2 text-sm">
      <% if @pagy.previous %>
        <%= link_to "← Newer", source_path(@source, page: @pagy.previous), class: "text-charcoal underline hover:no-underline" %>
      <% end %>
      <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", source_path(@source, page: @pagy.next), class: "text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
```

With:

```erb
  <% if @items.any? %>
    <div class="grid grid-cols-12 gap-y-4 max-w-screen-xl mx-auto mb-4 gap-x-2"
         data-controller="player">
      <div class="col-span-12 hidden border-y-3 border-charcoal"
           data-player-target="playerBox">
        <p class="p-4 text-center text-charcoal-300">Loading...</p>
      </div>

      <%= render partial: "items/item", collection: @items, as: :item %>
    </div>

    <% if @pagy.pages > 1 %>
      <div class="mt-4 flex justify-center gap-2 text-sm">
        <% if @pagy.previous %>
          <%= link_to "← Newer", source_path(@source, page: @pagy.previous), class: "text-charcoal underline hover:no-underline" %>
        <% end %>
        <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
        <% if @pagy.next %>
          <%= link_to "Older →", source_path(@source, page: @pagy.next), class: "text-charcoal underline hover:no-underline" %>
        <% end %>
      </div>
    <% end %>
  <% else %>
    <div class="border-3 border-charcoal rounded-md bg-athens-400 p-8 text-center">
      <p class="text-charcoal-300">No items from this source yet.</p>
    </div>
  <% end %>
```

Also change `max-w-3xl` to `max-w-screen-xl` on line 1:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
```

- [ ] **Step 2: Run sources controller tests**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: all 7 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/views/sources/show.html.erb
git commit -m "feat: update source show page to video grid layout"
```

---

## Task 8: Update system tests for new card structure

**Files:**
- Modify: `test/system/feed_flow_test.rb`

- [ ] **Step 1: Update system tests for new card structure**

Replace the entire `test/system/feed_flow_test.rb` with:

```ruby
require "test_helper"
require "application_system_test_case"

class FeedFlowTest < ApplicationSystemTestCase
  test "view feed shows video grid" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "Your Feed"
    assert_text "First Video"
    assert_text "Second Video"
    assert_selector ".grid.grid-cols-12"
    assert_selector "[data-player-target='video']", count: 3
  end

  test "hide an item removes it from grid" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "Second Video"
    within "##{dom_id(items(:video_two))}" do
      click_on "✕ Hide"
    end

    assert_no_text "Second Video"
    assert_text "First Video"
  end

  test "save an item shows saved state" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      click_on "☆ Save"
    end

    within "##{dom_id(items(:video_one))}" do
      assert_text "★ Saved"
    end
  end

  test "search filters items" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Ruby"
    click_button "Search"

    assert_text "First Video"
    assert_no_text "Second Video"
  end

  test "view sources list" do
    sign_in_as(users(:one))
    visit sources_path

    assert_text "Sources"
    assert_text "Test Channel"
    assert_text "BC Channel"
  end

  test "view source detail page shows grid" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit source_path(source)

    assert_text "Test Channel"
    assert_text "First Video"
    assert_selector ".grid.grid-cols-12"
  end

  test "clicking thumbnail opens inline player" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"
    assert_selector "iframe"
  end

  test "closing inline player hides it" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    find("[data-action*='player#close']").click
    assert_selector "[data-player-target='playerBox'].hidden"
  end
end
```

- [ ] **Step 2: Run system tests**

Run: `bin/rails test:system test/system/feed_flow_test.rb`
Expected: 8 tests PASS (requires Chrome/Chromium).

If system tests fail because of missing Chrome, note it but keep the tests — they'll pass in CI.

- [ ] **Step 3: Commit**

```bash
git add test/system/feed_flow_test.rb
git commit -m "test: update system tests for video grid and inline player"
```

---

## Task 9: Final verification — full test suite + lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: all tests PASS (existing + new).

- [ ] **Step 2: Run system tests**

Run: `bin/rails test:system`
Expected: all system tests PASS.

- [ ] **Step 3: Run RuboCop**

Run: `bin/rubocop`
Expected: no offenses. Fix any and re-run.

- [ ] **Step 4: Manual verification**

Run: `bin/dev`

1. Log in → see the video grid (2/3/4 cards per row depending on viewport)
2. Each card shows thumbnail, title, source, time, save/hide buttons
3. Click a thumbnail → inline player appears below the row with embedded iframe
4. Player shows video embed, title, source, description, save/hide, close, prev/next arrows
5. Click prev/next → player moves to adjacent video, repositions
6. Click close (X) → player hides
7. Click "Save" on a card → card re-renders with "★ Saved" text
8. Click "Hide" on a card → card disappears from grid
9. Search for a term → grid filters to matching items
10. Visit "Sources" → list of followed sources
11. Click a source → source detail page with video grid
12. Player works on source detail page too

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint and verification fixes for video grid"
```

If no fixes needed, skip.

---

## Summary

After completing all 9 tasks:

| Deliverable | Location |
|---|---|
| `embed_url`, `pretty_duration`, `missing_thumb` helpers | `app/helpers/application_helper.rb` |
| Player route | `config/routes.rb` |
| `ItemsController#player` action | `app/controllers/items_controller.rb` |
| Player Stimulus controller | `app/javascript/controllers/player_controller.js` |
| Inline player fragment | `app/views/items/_player.html.erb` |
| Video grid card partial | `app/views/items/_item.html.erb` |
| Feed index as 12-col grid | `app/views/feed/index.html.erb` |
| Source show as grid | `app/views/sources/show.html.erb` |
| Helper tests | `test/helpers/application_helper_test.rb` |
| Controller tests (player action) | `test/controllers/items_controller_test.rb` |
| System tests (grid + player) | `test/system/feed_flow_test.rb` |

The feed is now a responsive video grid with inline watching — same UX as stray_video, adapted for Stray's personal feed context. Save/hide interactions still work via Turbo Stream within the grid.
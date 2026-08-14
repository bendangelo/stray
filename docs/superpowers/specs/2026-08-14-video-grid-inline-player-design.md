# Design: Video Grid Feed with Inline Player

Date: 2026-08-14
Status: Approved

## Purpose

Transform the current single-column feed list into a responsive video grid with inline video watching, copying stray_video's proven UX pattern. Clicking a video thumbnail fetches an HTML fragment (iframe embed + metadata) and injects it into a hidden full-width "player slot" that gets repositioned to the row below the clicked card. No modal, no dedicated watch page, no page reload.

## Architecture

```
Feed page (FeedController#index)
  → 12-col CSS Grid (grid grid-cols-12 gap-y-4)
  → Hidden player slot (col-span-12, data-player-target="playerBox")
  → Video cards (col-span-6 sm:col-span-4 md:col-span-3 → 2/3/4 per row)
     → data-player-target="video" data-url="/items/:id/player"
     → Click thumbnail → player#toggle:prevent (no navigation)
     → Title → external link (target="_blank")
     → Save/hide buttons (Turbo Stream, unchanged)
  → Pagination below grid

Player Stimulus controller:
  → toggle(event) → find card index → openDetailPane(index) → updateView()
  → updateView() → fetch(data-url) → inject HTML into playerBox → set gridRow
  → prev/next → change index → fetch new fragment → reposition
  → close → hide playerBox → reset state
```

## Components

### Player Stimulus controller (`app/javascript/controllers/player_controller.js`)

Ported from stray_video's `player_controller.js`. Adapted for Stray's items.

- Targets: `playerBox` (hidden full-width slot), `video` (each card div)
- `toggle(event)` — clicking a card's thumbnail `<a>` toggles the player open/closed. Matches the clicked `<a>` against `videoTargets` to find the card index.
- `close(event)` — hides the player, resets `currentVideo` to -1.
- `prev(event)` / `next(event)` — decrement/increment `currentVideo`, re-fetch fragment, reposition. Hide/disable arrows at bounds.
- `updateView()`:
  - If open: read `data-url` from the active card's `data-url` attribute, `fetch()` it, inject HTML into `playerBoxTarget.innerHTML`, remove `hidden` class.
  - Calculate `videosPerRow` from active breakpoints (640/768/1024 → 2/3/4).
  - Set `playerBox.style.gridRow = 1 + Math.ceil((currentVideo + 1) / videosPerRow)` so the slot appears below the clicked card's row.
  - Smooth-scroll the active card into view (`scrollIntoView({ block: 'center', behavior: 'smooth' })`).
  - Toggle `border-2 border-carrot-400` on the active card's thumbnail.
- `fetch(url)` — standard `fetch().then(response.text())`, inject into `playerBoxTarget.innerHTML`.

### Item card partial (`app/views/items/_item.html.erb`)

Grid-friendly card. Replaces the current horizontal card.

```html
<div class="col-span-6 sm:col-span-4 md:col-span-3"
     data-player-target="video"
     data-url="<%= player_item_path(item) %>">
  <div class="flex flex-col">
    <!-- Thumbnail with overlay badges -->
    <div class="relative overflow-hidden">
      <a href="#" data-action="click->player#toggle:prevent">
        <img class="group-hover:border-2 border-carrot-400 object-cover w-full h-40 rounded-md
                    border-3 border-charcoal"
             src="<%= item.thumbnail_url || missing_thumb %>" alt="<%= item.title %>">
      </a>
      <% if item.duration.present? %>
        <p class="absolute right-2 bottom-2 bg-gray-900 text-gray-100 text-xs px-1 py rounded">
          <%= pretty_duration(item.duration) %>
        </p>
      <% end %>
      <!-- source badge bottom-left (optional) -->
    </div>

    <!-- Title + meta -->
    <div class="flex mt-1 flex-col">
      <a href="<%= item.url %>" target="_blank" rel="noopener"
         class="hover:underline break-all text-charcoal text-sm font-semibold">
        <%= truncate(item.title, length: 120) %>
      </a>
      <div class="flex items-center gap-2 mt-1 text-xs text-charcoal-300">
        <% if item.source.name.present? %>
          <%= link_to item.source.name, source_path(item.source), class: "hover:text-carrot-600 underline" %>
          <span>·</span>
        <% end %>
        <span><%= time_ago(item.published_at) %></span>
      </div>

      <!-- Save/hide buttons (subtle, below meta) -->
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

Key differences from current card:
- Card div carries `data-player-target="video"` and `data-url` for the player controller
- Thumbnail is dominant (`object-cover w-full h-40`) — fixed 160px height
- Duration badge overlaid on thumbnail (bottom-right)
- Clicking thumbnail triggers `player#toggle:prevent` (no navigation)
- Title links to external URL (opens source site in new tab)
- Save/hide buttons are text links (`★ Saved` / `☆ Save` / `✕ Hide`) below meta — subtle, not icon buttons
- Responsive grid: `col-span-6 sm:col-span-4 md:col-span-3`

### Player endpoint (`ItemsController#player`)

```ruby
def player
  item = Item.find_by(id: params[:id], user_id: current_user.id)
  return head :not_found unless item

  render "items/player", locals: { item: }, layout: false
end
```

- `GET /items/:id/player` — returns layout-less HTML fragment
- Scoped to `current_user.id` (same as other item actions)
- No authentication concern — inherits from ApplicationController

### Player fragment (`app/views/items/_player.html.erb`)

The inline watch experience. Returned by `ItemsController#player`, injected by the Stimulus controller.

```html
<div class="flex relative py-10 max-w-screen-lg mx-auto">
  <!-- Embed or thumbnail -->
  <% if embed_url(item) %>
    <iframe width="400" height="230"
            src="<%= embed_url(item) %>"
            title="<%= item.title %>"
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
    </iframe>
  <% else %>
    <img class="object-cover lg:mx-6 lg:w-1/2 h-72 lg:h-96"
         src="<%= item.thumbnail_url %>" alt="<%= item.title %>">
  <% end %>

  <!-- Metadata -->
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
          </p>
        </div>
      </div>
    <% end %>

    <% if item.content_text.present? %>
      <p class="text-sm text-gray-500 md:text-sm whitespace-pre-line">
        <%= truncate(item.content_text, length: 500) %>
      </p>
    <% end %>
  </div>

  <!-- Close button (top-right) -->
  <button type="button" aria-label="Close"
          class="absolute top-10 right-0 w-6 h-6"
          data-action="click->player#close">
    <svg class="text-charcoal hover:text-carrot w-full h-full" width="20" height="20" viewBox="0 0 20 20">
      <line x1="2" y1="2" x2="18" y2="18" stroke="currentColor" stroke-width="2"/>
      <line x1="2" y1="18" x2="18" y2="2" stroke="currentColor" stroke-width="2"/>
    </svg>
  </button>

  <!-- Prev/next arrows (bottom-right) -->
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

### Embed URL construction (`app/helpers/application_helper.rb`)

Add to the existing helper:

```ruby
def embed_url(item)
  case item.source.kind
  when "youtube_channel"
    video_id = item.external_id
    "https://www.youtube.com/embed/#{video_id}"
  when "video_channel"
    # For non-YouTube video sites, try to construct embed URL from known patterns
    # Bitchute: https://bitchute.com/embed/VIDEO_ID
    # Rumble: need rumble_embeds URL from extraction (future)
    # For now, return nil for unknown — the player shows thumbnail + external link
    uri = URI.parse(item.url) rescue nil
    if uri&.host&.include?("bitchute.com")
      video_id = item.external_id
      "https://www.bitchute.com/embed/#{video_id}"
    else
      nil
    end
  else
    nil
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

def missing_thumb
  # A placeholder image for items without thumbnails
  # Can be a data URI or a vendored image
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='180' fill='%233E3E3E'%3E%3Crect width='320' height='180'/%3E%3C/svg%3E"
end
```

### Feed index view (`app/views/feed/index.html.erb`)

Replaces the current single-column layout. The search bar and pagination stay; the item list becomes a grid.

```html
<main class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
  <div class="mb-4">
    <h1 class="font-display text-2xl font-bold text-charcoal">Your Feed</h1>
  </div>

  <%= render "search" %>

  <% if @items.any? %>
    <div class="grid grid-cols-12 gap-y-4 max-w-screen-xl mx-auto mb-4 gap-x-2"
         data-controller="player">
      <!-- Hidden player slot — full width, repositioned by JS -->
      <div class="col-span-12 hidden border-y-3 border-charcoal"
           data-player-target="playerBox">
        <p>Loading...</p>
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
- Single column → `grid grid-cols-12` with player slot + card collection
- Player slot is the first child (`col-span-12 hidden`)
- Cards rendered as collection (more efficient than `@items.each { render }`)
- Removed the `turbo_frame_tag "feed_search"` wrapper — the whole grid is the page content; search still works via GET form (full page reload on search, which is fine)
- Pagination stays below the grid

### Route addition

```ruby
resources :items, only: [:update] do
  member { get :player }
end
```

### ItemsController update

Add `player` action to the existing `ItemsController`:

```ruby
class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze

  def player
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    render "items/player", locals: { item: }, layout: false
  end

  def update
    # ... unchanged ...
  end
end
```

### Sources show page

The source show page (`sources/show.html.erb`) should also use the grid layout for its items — same `data-controller="player"` grid + player slot + `items/_item` cards. This gives a consistent video grid experience whether browsing the main feed or a single source's videos.

## What stays the same

- FeedController (Pagy, FTS5 search, user scoping) — no logic changes, just the view renders a grid
- LinksController (enqueue LinkIntakeJob)
- ItemsController#update (save/hide via Turbo Stream)
- SourcesController (index, show, weight reset)
- Navbar (inline add-link form + Turbo Stream source)
- All Phase 1-2 backend (extractors, jobs, polling, models)

## Save/hide interaction in the grid

The save/hide buttons still use `button_to ... form: { data: { turbo_stream: true } }`. The Turbo Stream response (`items/update.turbo_stream.erb`) replaces the card via `turbo_stream.replace dom_id(item)`. This works inside the grid — the replaced card stays in its grid cell. For hidden items, `turbo_stream.remove dom_id(item)` removes the card (the grid auto-collapses).

One issue: after `turbo_stream.replace`, the new card's `data-player-target="video"` attribute is present, but Stimulus won't auto-connect it (it was already connected at page load). The player controller's `videoTargets` array is a live NodeList — it should pick up the replaced element automatically. If not, the player controller's `connect` method may need to re-scan. This is a detail to verify during implementation.

## What's NOT in this phase

- No tagging/embedding (Phase 4)
- No semantic search (Phase 4)
- No source filter tabs (All/YouTube/Bitchute — future)
- No dropdown filters (Time/Duration/Order — future)
- No autocomplete on search (future)
- No keyboard shortcuts for player (Esc/ArrowLeft/ArrowRight — future enhancement)

## Testing

- **Controller test**: `ItemsController#player` returns the fragment, 404 for other user's items, 404 for missing items
- **Feed controller test**: verify the grid renders (check for `grid grid-cols-12`, `data-controller="player"`, `data-player-target="video"` on cards)
- **System test**: click a video thumbnail → player slot appears with iframe; close button hides it; prev/next navigate between videos
- **Helper test**: `embed_url` constructs correct URLs for YouTube and Bitchute; `pretty_duration` handles seconds/minutes/hours

## Files to create/modify

### Create
- `app/javascript/controllers/player_controller.js` — Stimulus controller (ported from stray_video)
- `app/views/items/_player.html.erb` — inline player fragment

### Modify
- `app/controllers/items_controller.rb` — add `player` action
- `app/views/feed/index.html.erb` — single-column → 12-col grid
- `app/views/items/_item.html.erb` — horizontal card → video grid card
- `app/views/sources/show.html.erb` — single-column → grid for items
- `app/helpers/application_helper.rb` — add `embed_url`, `pretty_duration`, `missing_thumb`
- `config/routes.rb` — add `member { get :player }` to items

### Tests
- `test/controllers/items_controller_test.rb` — add player action tests
- `test/helpers/application_helper_test.rb` — test `embed_url`, `pretty_duration`
- `test/system/feed_flow_test.rb` — update to test inline player
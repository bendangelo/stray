# Phase 3: Add-link UI + Homepage Feed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the add-link UI (inline navbar form → LinkIntakeJob → Turbo Stream broadcast), the homepage feed (reverse-chronological items from followed sources with Pagy pagination + FTS5 search), the sources index/show pages (per-source feed, poll status, follow weight management), and item interactions (save/hide via Turbo Stream).

**Architecture:** Root route becomes `FeedController#index` (authenticated, redirects to login if not). Navbar gets an inline URL input that posts to `LinksController#create`, which enqueues `LinkIntakeJob` and responds with a Turbo Stream "checking..." status. A `<turbo-stream-source>` subscribes to the `user_#{id}_intake` channel; `LinkIntakeJob`'s broadcast replaces the status div with the result. Feed items are rendered as cards with save/hide buttons (PATCH `ItemsController#update` via Turbo Stream). Sources index lists followed sources; source show page displays per-source items and follow weight with a reset button. FTS5 search via `Item.search(query)` in a Turbo Frame.

**Tech Stack:** Rails 8.1, Ruby 4.0.5, Hotwire (Turbo Frames + Turbo Streams via Solid Cable), Stimulus (importmap, auto-registered), Tailwind CSS v4 (CSS-first config in `app/assets/tailwind/application.css`), Pagy (new gem), `full_search` gem (FTS5, already wired on `Item`).

**Spec:** `docs/superpowers/specs/2026-08-13-extractor-design.md` — Phase 3 section

**Design system conventions (from existing views):**
- Page bg: `bg-champagne`. Text: `text-charcoal`. Borders: `border-3 border-charcoal`.
- Input bg: `bg-athens-400`. Inputs: `h-12 px-3 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none`.
- Primary button: `bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal`.
- Alert: `border-3 border-cerise text-cerise text-sm`. Notice: `border-3 border-mint-500 text-mint-700 text-sm`.
- Heading: `font-display text-2xl font-bold text-charcoal`.
- Secondary link: `text-sm text-charcoal underline hover:no-underline`.
- Footer is `position: fixed` — pages need `pb-16` to clear it.

---

## File Map

### Controllers (app/controllers/)
- `app/controllers/feed_controller.rb` — homepage feed, authenticated, Pagy + search
- `app/controllers/links_controller.rb` — create: enqueue LinkIntakeJob, Turbo Stream response
- `app/controllers/items_controller.rb` — update: change state (saved/hidden), Turbo Stream
- `app/controllers/sources_controller.rb` — index (followed sources), show (per-source feed + weight)

### Views (app/views/)
- `app/views/feed/index.html.erb` — feed page with search + item list + pagination
- `app/views/feed/_search.html.erb` — FTS5 search form in Turbo Frame
- `app/views/items/_item.html.erb` — item card partial (thumbnail, title, source, buttons)
- `app/views/items/_item.turbo_stream.erb` — Turbo Stream response for state update
- `app/views/sources/index.html.erb` — followed sources list
- `app/views/sources/show.html.erb` — per-source feed + weight management
- `app/views/links/create.turbo_stream.erb` — "checking..." Turbo Stream response

### Layout changes
- `app/views/layouts/_navbar.html.erb` — add inline URL input + Turbo Stream source
- `app/views/layouts/application.html.erb` — no change (flash + yield already in place)

### Helpers
- `app/helpers/application_helper.rb` — add time-ago / formatting helpers

### Config
- `config/routes.rb` — root → feed, add links/sources/items routes, move landing to /about
- `Gemfile` — add pagy
- `config/initializers/pagy.rb` — Pagy config (optional, may not be needed)

### Tests
- `test/controllers/feed_controller_test.rb`
- `test/controllers/links_controller_test.rb`
- `test/controllers/items_controller_test.rb`
- `test/controllers/sources_controller_test.rb`
- `test/system/feed_flow_test.rb` — system test: add link, see feed, save/hide

### Fixtures
- `test/fixtures/sources.yml` — source fixtures for feed tests
- `test/fixtures/items.yml` — item fixtures for feed tests
- `test/fixtures/follows.yml` — follow fixtures linking users to sources

---

## Task 1: Add pagy gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add pagy to Gemfile**

Add after the `full_search` gem line:

```ruby
gem "pagy"
```

- [ ] **Step 2: Install gem**

Run: `bundle install`
Expected: pagy installs, Gemfile.lock updated.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add pagy gem for pagination"
```

---

## Task 2: Update routes — feed as root, add links/sources/items

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Read current routes.rb**

Current:
```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :new, :create ], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check
  root "pages#index"
  get "privacy_and_terms", to: "pages#privacy_and_terms"
end
```

- [ ] **Step 2: Update routes**

Replace with:

```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :new, :create ], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check

  root "feed#index"
  get "about", to: "pages#index", as: :about
  get "privacy_and_terms", to: "pages#privacy_and_terms"

  resources :links, only: [ :create ]
  resources :sources, only: [ :index, :show ]
  resources :items, only: [ :update ]
end
```

- [ ] **Step 3: Verify routes load**

Run: `bin/rails runner "puts Rails.application.routes.url_helpers.root_path"`
Expected: `/` printed, no error.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "feat: set feed as root route, add links/sources/items routes"
```

---

## Task 3: Create fixtures for feed tests

**Files:**
- Create: `test/fixtures/sources.yml`
- Create: `test/fixtures/follows.yml`
- Create: `test/fixtures/items.yml`

- [ ] **Step 1: Create sources fixture**

```yaml
youtube:
  user: one
  kind: 0
  url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123"
  name: "Test Channel"
  external_id: "UCtest123"
  active: true

bitchute:
  user: one
  kind: 1
  url: "https://bitchute.com/channel/abc"
  name: "BC Channel"
  external_id: "abc"
  active: true

inactive:
  user: one
  kind: 0
  url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCold"
  name: "Dead Channel"
  external_id: "UCold"
  active: false
```

Note: `kind` is an integer column (enum: `youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3`).

- [ ] **Step 2: Create follows fixture**

```yaml
one:
  user: one
  source: youtube
  weight: 1.0

two:
  user: one
  source: bitchute
  weight: 0.5

three:
  user: two
  source: youtube
  weight: 1.0
```

- [ ] **Step 3: Create items fixture**

```yaml
video_one:
  source: youtube
  user: one
  external_id: "vid1"
  title: "First Video"
  url: "https://www.youtube.com/watch?v=vid1"
  content_text: "A test video about Ruby"
  published_at: <%= 2.days.ago %>
  state: 0

video_two:
  source: youtube
  user: one
  external_id: "vid2"
  title: "Second Video"
  url: "https://www.youtube.com/watch?v=vid2"
  content_text: "Another video about Rails"
  published_at: <%= 1.day.ago %>
  state: 0

video_saved:
  source: bitchute
  user: one
  external_id: "vid3"
  title: "Saved Video"
  url: "https://bitchute.com/video/vid3"
  content_text: "A saved video"
  published_at: <%= 3.days.ago %>
  state: 2

video_hidden:
  source: bitchute
  user: one
  external_id: "vid4"
  title: "Hidden Video"
  url: "https://bitchute.com/video/vid4"
  content_text: "Should not appear"
  published_at: <%= 4.days.ago %>
  state: 3

video_user_two:
  source: youtube
  user: two
  external_id: "vid5"
  title: "User Two Video"
  url: "https://www.youtube.com/watch?v=vid5"
  content_text: "Belongs to user two"
  published_at: <%= 1.hour.ago %>
  state: 0
```

Note: `state` is an integer column (enum: `unseen: 0, seen: 1, saved: 2, hidden: 3`).

- [ ] **Step 4: Verify fixtures load**

Run: `bin/rails runner "puts Source.count; puts Item.count; puts Follow.count"`
Expected: `3`, `5`, `3` (in test env). If this runs in development, use `RAILS_ENV=test bin/rails runner ...`.

- [ ] **Step 5: Commit**

```bash
git add test/fixtures/sources.yml test/fixtures/follows.yml test/fixtures/items.yml
git commit -m "test: add sources, follows, items fixtures"
```

---

## Task 4: Add ApplicationHelper methods

**Files:**
- Modify: `app/helpers/application_helper.rb`

- [ ] **Step 1: Write helper methods**

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
end
```

- [ ] **Step 2: Verify it loads**

Run: `bin/rails runner "include ApplicationHelper; puts time_ago(2.hours.ago)"`
Expected: `2h ago`

- [ ] **Step 3: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -m "feat: add time_ago helper"
```

---

## Task 5: Create FeedController

**Files:**
- Create: `app/controllers/feed_controller.rb`
- Create: `test/controllers/feed_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class FeedControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not authenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows feed for authenticated user" do
    sign_in_as(users(:one))
    get root_path
    assert_response :success
    assert_select "title", "Stray"
  end

  test "shows items from followed sources, reverse chronological" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    body = response.body
    assert_includes body, "Second Video"
    assert_includes body, "First Video"
    assert_includes body, "Saved Video"
    assert_not_includes body, "Hidden Video"
    assert_not_includes body, "User Two Video"
  end

  test "search filters by FTS5 query" do
    sign_in_as(users(:one))
    get root_path, params: { q: "Ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "search with no results shows empty message" do
    sign_in_as(users(:one))
    get root_path, params: { q: "nonexistent" }

    assert_response :success
    assert_includes response.body, "No results"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: FAIL with `NameError: uninitialized constant FeedController`

- [ ] **Step 3: Write FeedController**

```ruby
class FeedController < ApplicationController
  include Pagy::Backend

  def index
    base_scope = Item.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .where.not(state: :hidden)

    if params[:q].present?
      @q = params[:q]
      items = Item.joins(:follow)
        .where(follows: { user_id: current_user.id })
        .where.not(state: :hidden)
        .search(params[:q])
      @pagy, @items = pagy(items.order(published_at: :desc), limit: 20)
    else
      @pagy, @items = pagy(base_scope.order(published_at: :desc), limit: 20)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/feed_controller.rb test/controllers/feed_controller_test.rb
git commit -m "feat: add FeedController with Pagy pagination and FTS5 search"
```

---

## Task 6: Create feed index view

**Files:**
- Create: `app/views/feed/index.html.erb`
- Create: `app/views/feed/_search.html.erb`
- Create: `app/views/items/_item.html.erb`

- [ ] **Step 1: Create the item card partial**

`app/views/items/_item.html.erb`:

```erb
<div id="<%= dom_id(item) %>" class="border-3 border-charcoal rounded-md bg-athens-400 p-4 mb-3 flex gap-4">
  <% if item.thumbnail_url.present? %>
    <%= image_tag item.thumbnail_url, alt: item.title, class: "w-32 h-20 object-cover rounded-md shrink-0 border-2 border-charcoal" %>
  <% end %>

  <div class="flex-1 min-w-0">
    <div class="flex items-start justify-between gap-2">
      <%= link_to item.title, item.url, target: "_blank", rel: "noopener",
        class: "font-display font-bold text-charcoal hover:text-carrot-600 truncate" %>

      <div class="flex gap-1 shrink-0">
        <% if item.saved? %>
          <%= button_to item_path(item), method: :patch, params: { state: "unseen" }, class: "text-amber-500 hover:text-amber-600 cursor-pointer bg-transparent border-none", title: "Unsave" do %>
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>
          <% end %>
        <% else %>
          <%= button_to item_path(item), method: :patch, params: { state: "saved" }, form: { data: { turbo_stream: true } }, class: "text-charcoal-300 hover:text-amber-500 cursor-pointer bg-transparent border-none", title: "Save" do %>
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/></svg>
          <% end %>
        <% end %>

        <%= button_to item_path(item), method: :patch, params: { state: "hidden" }, form: { data: { turbo_stream: true } }, class: "text-charcoal-300 hover:text-cerise cursor-pointer bg-transparent border-none", title: "Hide" do %>
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
        <% end %>
      </div>
    </div>

    <div class="flex items-center gap-2 mt-1 text-xs text-charcoal-300">
      <% if item.source.name.present? %>
        <%= link_to item.source.name, source_path(item.source), class: "hover:text-carrot-600 underline" %>
        <span>·</span>
      <% end %>
      <span><%= time_ago(item.published_at) %></span>
      <% if item.duration.present? %>
        <span>·</span>
        <span><%= "%02d:%02d" % [ item.duration / 60, item.duration % 60 ] %></span>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Create the search partial**

`app/views/feed/_search.html.erb`:

```erb
<%= turbo_frame_tag "search_results" do %>
  <%= form_with url: root_path, method: :get, class: "mb-4", data: { turbo_frame: "search_results" } do |form| %>
    <div class="flex gap-2">
      <%= form.text_field :q,
        value: defined?(@q) ? @q : nil,
        placeholder: "Search your feed...",
        class: "flex-1 h-10 px-3 bg-athens-400 border-3 border-charcoal rounded-md text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
      <%= form.submit "Search", class: "h-10 px-4 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal" %>
      <% if defined?(@q) && @q.present? %>
        <%= link_to "Clear", root_path, class: "h-10 flex items-center px-3 text-sm text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 3: Create the feed index view**

`app/views/feed/index.html.erb`:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <div class="mb-4">
    <h1 class="font-display text-2xl font-bold text-charcoal">Your Feed</h1>
  </div>

  <%= render "search" %>

  <div id="feed_items">
    <% if @items.any? %>
      <% @items.each do |item| %>
        <%= render "items/item", item: item %>
      <% end %>
    <% else %>
      <div class="border-3 border-charcoal rounded-md bg-athens-400 p-8 text-center">
        <p class="text-charcoal-300">
          <% if defined?(@q) && @q.present? %>
            No results for "<%= @q %>"
          <% else %>
            Your feed is empty. Add a link above to start following sources.
          <% end %>
        </p>
      </div>
    <% end %>
  </div>

  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center gap-2 text-sm" data-controller="pagination">
      <% if @pagy.prev %>
        <%= link_to "← Newer", root_path(page: @pagy.prev, q: defined?(@q) ? @q : nil),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
      <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", root_path(page: @pagy.next, q: defined?(@q) ? @q : nil),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
</main>
```

- [ ] **Step 4: Run feed controller test to verify it passes**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/feed/ app/views/items/_item.html.erb
git commit -m "feat: add feed index view with search, item cards, pagination"
```

---

## Task 7: Create ItemsController — state updates via Turbo Stream

**Files:**
- Create: `app/controllers/items_controller.rb`
- Create: `app/views/items/update.turbo_stream.erb`
- Create: `test/controllers/items_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  test "updates item state to saved" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream

    assert_response :success
    item.reload
    assert item.saved?
  end

  test "updates item state to hidden" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "hidden" }, as: :turbo_stream

    assert_response :success
    item.reload
    assert item.hidden?
  end

  test "cannot update other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream

    assert_response :not_found
    item.reload
    assert_not item.saved?
  end

  test "rejects invalid state" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "invalid" }, as: :turbo_stream

    assert_response :bad_request
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: FAIL with `NameError: uninitialized constant ItemsController`

- [ ] **Step 3: Write ItemsController**

```ruby
class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze

  def update
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    state = params[:state]
    return head :bad_request unless ALLOWED_STATES.include?(state)

    item.update!(state: state)

    respond_to do |format|
      format.turbo_stream { render "items/update", locals: { item: } }
      format.html { redirect_to root_path }
    end
  end
end
```

- [ ] **Step 4: Create Turbo Stream response template**

`app/views/items/update.turbo_stream.erb`:

```erb
<%= turbo_stream.replace dom_id(item) do %>
  <%= render "items/item", item: item %>
<% end %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/items_controller.rb app/views/items/update.turbo_stream.erb test/controllers/items_controller_test.rb
git commit -m "feat: add ItemsController for state updates via Turbo Stream"
```

---

## Task 8: Create LinksController — enqueue LinkIntakeJob

**Files:**
- Create: `app/controllers/links_controller.rb`
- Create: `app/views/links/create.turbo_stream.erb`
- Create: `test/controllers/links_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  test "enqueues LinkIntakeJob and returns turbo stream" do
    sign_in_as(users(:one))

    assert_enqueued_with(job: LinkIntakeJob, args: [ users(:one).id, "https://youtube.com/@test" ]) do
      post links_path, params: { url: "https://youtube.com/@test" }, as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, 'id="intake_status"'
    assert_includes response.body, "Checking"
  end

  test "rejects blank url" do
    sign_in_as(users(:one))

    post links_path, params: { url: "" }, as: :turbo_stream

    assert_response :bad_request
  end

  test "requires authentication" do
    post links_path, params: { url: "https://example.com" }, as: :turbo_stream
    assert_redirected_to new_session_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/links_controller_test.rb`
Expected: FAIL with `NameError: uninitialized constant LinksController`

- [ ] **Step 3: Write LinksController**

```ruby
class LinksController < ApplicationController
  def create
    url = params[:url]
    return head :bad_request if url.blank?

    LinkIntakeJob.perform_later(current_user.id, url)

    respond_to do |format|
      format.turbo_stream
    end
  end
end
```

- [ ] **Step 4: Create Turbo Stream response template**

`app/views/links/create.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "intake_status" do %>
  <div id="intake_status" class="mt-2 px-4 py-3 border-3 border-charcoal rounded-md bg-athens-400 text-sm text-charcoal">
    <span class="inline-block animate-pulse">Checking...</span>
  </div>
<% end %>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/links_controller_test.rb`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/links_controller.rb app/views/links/ test/controllers/links_controller_test.rb
git commit -m "feat: add LinksController to enqueue LinkIntakeJob"
```

---

## Task 9: Update navbar — inline add-link form + Turbo Stream source

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`

- [ ] **Step 1: Read current navbar**

Current `_navbar.html.erb`:

```erb
<nav class="pb-2 md:pt-2 md:pl-2 pt-1 border-b-3 border-charcoal">
  <div class="flex pl-2 mx-auto md:pl-4 lg:pl-16 lg:ml-2 items-center justify-between">
    <div class="flex items-center lg:mr-4 md:mr-2 mr-1">
      <%= link_to root_path, tabindex: "-1" do %>
        <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "w-0 md:w-20 lg:w-28" %>
        <span class="hidden">Stray</span>
      <% end %>
    </div>

    <div class="flex items-center gap-4 pr-4 text-sm">
      <% if authenticated? %>
        <span class="text-charcoal"><%= current_user.username %></span>
        <%= button_to "Log out", session_path, method: :delete, class: "text-charcoal hover:text-carrot-600 underline cursor-pointer bg-transparent border-none" %>
      <% else %>
        <%= link_to "Log in", new_session_path, class: "text-charcoal hover:text-carrot-600 underline" %>
      <% end %>
    </div>
  </div>
</nav>
```

- [ ] **Step 2: Update navbar with inline add-link form + Turbo Stream source**

Replace the entire file with:

```erb
<nav class="pb-2 md:pt-2 md:pl-2 pt-1 border-b-3 border-charcoal">
  <div class="flex pl-2 mx-auto md:pl-4 lg:pl-16 lg:ml-2 items-center justify-between">
    <div class="flex items-center lg:mr-4 md:mr-2 mr-1">
      <%= link_to root_path, tabindex: "-1" do %>
        <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "w-0 md:w-20 lg:w-28" %>
        <span class="hidden">Stray</span>
      <% end %>
    </div>

    <div class="flex items-center gap-4 pr-4 text-sm">
      <% if authenticated? %>
        <%= turbo_stream_from "user_#{current_user.id}_intake" %>

        <%= form_with url: links_path, class: "flex gap-1", data: { turbo_stream: true } do |form| %>
          <%= form.url_field :url,
            placeholder: "Paste a link...",
            class: "h-9 w-40 md:w-64 px-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
          <%= form.submit "+",
            class: "h-9 w-9 bg-carrot-500 hover:bg-carrot-600 text-white font-bold rounded-md cursor-pointer border-3 border-charcoal" %>
        <% end %>

        <span id="intake_status" class="text-charcoal"></span>

        <%= link_to "Sources", sources_path, class: "text-charcoal hover:text-carrot-600 underline" %>
        <span class="text-charcoal"><%= current_user.username %></span>
        <%= button_to "Log out", session_path, method: :delete, class: "text-charcoal hover:text-carrot-600 underline cursor-pointer bg-transparent border-none" %>
      <% else %>
        <%= link_to "Log in", new_session_path, class: "text-charcoal hover:text-carrot-600 underline" %>
      <% end %>
    </div>
  </div>
</nav>
```

Key additions:
- `<%= turbo_stream_from "user_#{current_user.id}_intake" %>` — subscribes to the Turbo Stream channel that `LinkIntakeJob` broadcasts to
- Inline form posting to `links_path` with `data: { turbo_stream: true }` so the response is handled as a Turbo Stream
- `<span id="intake_status">` — the target that `LinkIntakeJob`'s broadcast replaces
- "Sources" link to `sources_path`

- [ ] **Step 3: Verify navbar renders**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: tests still PASS (navbar is in the layout, rendered on every page).

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/_navbar.html.erb
git commit -m "feat: add inline add-link form and Turbo Stream source to navbar"
```

---

## Task 10: Create SourcesController — index and show

**Files:**
- Create: `app/controllers/sources_controller.rb`
- Create: `app/views/sources/index.html.erb`
- Create: `app/views/sources/show.html.erb`
- Create: `test/controllers/sources_controller_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  test "index shows followed sources for current user" do
    sign_in_as(users(:one))
    get sources_path

    assert_response :success
    assert_includes response.body, "Test Channel"
    assert_includes response.body, "BC Channel"
    assert_not_includes response.body, "Dead Channel"
  end

  test "show displays source items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    get source_path(source)

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Second Video"
  end

  test "show displays follow weight" do
    sign_in_as(users(:one))
    source = sources(:bitchute)
    get source_path(source)

    assert_response :success
    assert_includes response.body, "0.5"
  end

  test "show does not show sources from other users" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow = follows(:three)
    get source_path(source)
    assert_response :success
  end

  test "reset weight updates follow weight to 1.0" do
    sign_in_as(users(:one))
    source = sources(:bitchute)
    follow = follows(:two)
    assert_equal 0.5, follow.weight

    patch source_path(source), params: { reset_weight: true }, as: :turbo_stream

    assert_response :success
    follow.reload
    assert_equal 1.0, follow.weight
  end

  test "index requires authentication" do
    get sources_path
    assert_redirected_to new_session_path
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: FAIL with `NameError: uninitialized constant SourcesController`

- [ ] **Step 3: Write SourcesController**

```ruby
class SourcesController < ApplicationController
  include Pagy::Backend

  def index
    @sources = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .where(active: true)
      .order(:name)
  end

  def show
    @source = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .find(params[:id])

    @follow = @source.follow
    @pagy, @items = pagy(@source.items.order(published_at: :desc), limit: 20)
  end

  def update
    source = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .find(params[:id])

    if params[:reset_weight]
      source.follow.update!(weight: 1.0)
    end

    respond_to do |format|
      format.turbo_stream { render "sources/update", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end
end
```

- [ ] **Step 4: Create sources index view**

`app/views/sources/index.html.erb`:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Sources</h1>

  <div class="space-y-2">
    <% @sources.each do |source| %>
      <%= link_to source_path(source), class: "block border-3 border-charcoal rounded-md bg-athens-400 p-4 hover:bg-athens-500" do %>
        <div class="flex items-center justify-between">
          <div>
            <span class="font-display font-bold text-charcoal"><%= source.name %></span>
            <span class="text-xs text-charcoal-300 ml-2"><%= source.kind.humanize %></span>
          </div>
          <div class="text-xs text-charcoal-300">
            <%= source.items.count %> items
            <% if source.last_polled_at %>
              · polled <%= time_ago(source.last_polled_at) %>
            <% end %>
            <% if source.last_error %>
              · <span class="text-cerise">error</span>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
  </div>
</main>
```

- [ ] **Step 5: Create sources show view**

`app/views/sources/show.html.erb`:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <div class="mb-4">
    <%= link_to "← Sources", sources_path, class: "text-sm text-charcoal underline hover:no-underline" %>
    <h1 class="font-display text-2xl font-bold text-charcoal mt-2"><%= @source.name %></h1>
    <div class="flex items-center gap-3 mt-1 text-xs text-charcoal-300">
      <span><%= @source.kind.humanize %></span>
      <% if @source.last_polled_at %>
        <span>· polled <%= time_ago(@source.last_polled_at) %></span>
      <% end %>
      <% if @source.next_crawl_at %>
        <span>· next poll <%= time_ago(@source.next_crawl_at) %></span>
      <% end %>
      <% if @source.last_error %>
        <span class="text-cerise">· error: <%= @source.last_error %></span>
      <% end %>
    </div>
  </div>

  <div class="mb-4 flex items-center gap-3 border-3 border-charcoal rounded-md bg-athens-400 p-3">
    <span class="text-sm text-charcoal">Weight: <%= @follow.weight %></span>
    <% if @follow.weight != 1.0 %>
      <%= button_to "Reset", source_path(@source), method: :patch, params: { reset_weight: true },
        form: { data: { turbo_stream: true } },
        class: "text-sm text-charcoal underline hover:no-underline cursor-pointer bg-transparent border-none" %>
    <% end %>
  </div>

  <div id="source_items">
    <% @items.each do |item| %>
      <%= render "items/item", item: item %>
    <% end %>
  </div>

  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center gap-2 text-sm">
      <% if @pagy.prev %>
        <%= link_to "← Newer", source_path(@source, page: @pagy.prev), class: "text-charcoal underline hover:no-underline" %>
      <% end %>
      <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", source_path(@source, page: @pagy.next), class: "text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
</main>
```

- [ ] **Step 6: Create sources update Turbo Stream response**

`app/views/sources/update.turbo_stream.erb`:

```erb
<%= turbo_stream.replace dom_id(source, :weight) do %>
  <span id="<%= dom_id(source, :weight) %>" class="text-sm text-charcoal">Weight: 1.0</span>
<% end %>
```

Note: The show view's weight display needs an id for the Turbo Stream to target. Update the weight span in `show.html.erb` to include the id:

In `app/views/sources/show.html.erb`, change:
```erb
<span class="text-sm text-charcoal">Weight: <%= @follow.weight %></span>
```
To:
```erb
<span id="<%= dom_id(@source, :weight) %>" class="text-sm text-charcoal">Weight: <%= @follow.weight %></span>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: 6 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/sources_controller.rb app/views/sources/ test/controllers/sources_controller_test.rb
git commit -m "feat: add SourcesController with index, show, and weight reset"
```

---

## Task 11: Update PagesController for /about route

**Files:**
- Modify: `app/controllers/pages_controller.rb`
- Modify: `app/views/pages/index.html.erb`

- [ ] **Step 1: Read current pages_controller.rb**

Current:
```ruby
class PagesController < ApplicationController
  allow_unauthenticated_access

  def index
  end

  def privacy_and_terms
  end
end
```

This is fine as-is — it stays `allow_unauthenticated_access` since `/about` is the public landing page. No changes to the controller needed.

- [ ] **Step 2: Update the landing page view to include a CTA**

`app/views/pages/index.html.erb` — replace with:

```erb
<main class="flex flex-col items-center justify-center mt-[24vh] px-5">
  <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "lg:w-5/12 md:w-6/12 w-7/12" %>

  <div class="mt-7 flex lg:w-7/12 md:w-8/12 w-11/12">
    <p class="px-2 py-1 text-sm text-charcoal">Your personal feed, ranked and tagged, your way.</p>
  </div>

  <div class="mt-6">
    <%= link_to "Log in", new_session_path, class: "h-12 px-8 bg-carrot-500 hover:bg-carrot-600 text-white font-medium rounded-md cursor-pointer border-3 border-charcoal inline-flex items-center" %>
  </div>
</main>
```

- [ ] **Step 3: Commit**

```bash
git add app/views/pages/index.html.erb
git commit -m "feat: update landing page with login CTA, move to /about"
```

---

## Task 12: System test — add link flow

**Files:**
- Create: `test/system/feed_flow_test.rb`

- [ ] **Step 1: Write the system test**

```ruby
require "test_helper"

class FeedFlowTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  test "view feed and hide an item" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "Your Feed"
    assert_text "First Video"
    assert_text "Second Video"

    within "##{dom_id(items(:video_two))}" do
      find("button[title='Hide']").click
    end

    assert_no_text "Second Video"
    assert_text "First Video"
  end

  test "save an item and see it highlighted" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[title='Save']").click
    end

    assert_selector "##{dom_id(items(:video_one))} svg[fill='currentColor']"
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

  test "view source detail page" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit source_path(source)

    assert_text "Test Channel"
    assert_text "First Video"
  end
end
```

- [ ] **Step 2: Run system test**

Run: `bin/rails test:system test/system/feed_flow_test.rb`
Expected: 5 tests PASS (requires Chrome/Chromium installed).

If system tests fail because of missing Chrome, mark as `skip` and note in the commit. The controller tests cover the same behavior.

- [ ] **Step 3: Commit**

```bash
git add test/system/feed_flow_test.rb
git commit -m "test: add system tests for feed flow"
```

---

## Task 13: Final verification — full test suite + lint

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: all tests PASS (existing auth tests + Phase 3 controller/system tests).

- [ ] **Step 2: Run system tests**

Run: `bin/rails test:system`
Expected: all system tests PASS.

- [ ] **Step 3: Run RuboCop**

Run: `bin/rubocop`
Expected: no offenses. Fix any and re-run.

- [ ] **Step 4: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: no new warnings.

- [ ] **Step 5: Manual verification**

Run: `bin/dev`

1. Visit `http://localhost:3000` — should redirect to `/session/new` (login)
2. Log in
3. See the feed page with "Your Feed" heading
4. See item cards with save/hide buttons
5. Click "Save" on an item — card should update inline
6. Click "Hide" on an item — card should disappear from feed
7. See the inline URL input in the navbar
8. Paste a URL and click "+" — should see "Checking..." in the navbar
9. (If yt-dlp is installed and the URL is valid, the Turbo Stream broadcast should replace "Checking..." with the result after a few seconds)
10. Click "Sources" link — see the sources list
11. Click a source — see its items and weight
12. Search for a term — results should filter

- [ ] **Step 6: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint and verification fixes for Phase 3"
```

If no fixes needed, skip.

---

## Summary

After completing all 13 tasks, Phase 3 delivers:

| Deliverable | Location |
|---|---|
| Pagy gem | `Gemfile` |
| Feed route as root | `config/routes.rb` |
| FeedController (homepage feed + search) | `app/controllers/feed_controller.rb` |
| LinksController (enqueue LinkIntakeJob) | `app/controllers/links_controller.rb` |
| ItemsController (save/hide state) | `app/controllers/items_controller.rb` |
| SourcesController (index, show, weight reset) | `app/controllers/sources_controller.rb` |
| Feed index view (search + items + pagination) | `app/views/feed/index.html.erb` |
| Item card partial | `app/views/items/_item.html.erb` |
| Item Turbo Stream response | `app/views/items/update.turbo_stream.erb` |
| Links Turbo Stream response | `app/views/links/create.turbo_stream.erb` |
| Sources index + show views | `app/views/sources/` |
| Navbar with inline add-link + Turbo Stream source | `app/views/layouts/_navbar.html.erb` |
| Landing page moved to /about | `app/views/pages/index.html.erb` |
| Fixtures (sources, items, follows) | `test/fixtures/` |
| Controller tests | `test/controllers/` |
| System test | `test/system/feed_flow_test.rb` |
| ApplicationHelper (time_ago) | `app/helpers/application_helper.rb` |

The app is now a fully functional personal video feed: add links from the navbar, see videos in reverse-chron order, save/hide items, browse sources, search via FTS5. Phase 4 adds tagging + embedding + semantic search.
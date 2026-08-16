# UI Shell Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the Stray UI into a three-zone app shell — sticky header bar (logo + search + paste-link + user), horizontal tag filter bar, collapsible left sidebar with source favicons and unseen counts — and migrate brand/favicon assets from `stray_old`.

**Architecture:** The layout moves from a single navbar into a structured shell: `application.html.erb` renders header (`_navbar`), an optional tag bar (yielded content), a sidebar (`sources/_sidebar`), and the main content area. The `FeedController` gains tag filtering and a tags collection. A new `sidebar_controller` Stimulus handles mobile drawer toggling. Favicon assets are copied from `stray_old` and wired via a `_favicon` partial.

**Tech Stack:** Rails 8, ERB, Tailwind CSS v4, Hotwire (Turbo + Stimulus), Minitest, Pagy, `full_search` gem (FTS5).

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Copy | `app/assets/images/favicon/*` (6 files) | Favicon set from stray_old |
| Copy | `app/assets/images/stray-logo.svg` | Wordmark logo from stray_old (replaces current) |
| Copy | `public/favicon.ico` | Root-level favicon fallback |
| Remove | `public/icon.svg`, `public/icon.png` | Old placeholder icons |
| Create | `app/views/layouts/_favicon.html.erb` | Favicon `<link>` tags partial |
| Modify | `app/views/layouts/application.html.erb` | New shell: header + tag bar slot + sidebar + content |
| Modify | `app/views/layouts/_navbar.html.erb` | Header bar: logo + search + paste + user menu |
| Create | `app/views/shared/_tag_bar.html.erb` | Horizontal tag filter chips |
| Create | `app/views/sources/_sidebar.html.erb` | Source list with favicons + unseen counts |
| Create | `app/javascript/controllers/sidebar_controller.js` | Mobile drawer toggle |
| Modify | `app/controllers/feed_controller.rb` | Tag filtering + tags collection |
| Modify | `app/views/feed/index.html.erb` | Remove inline search, render tag bar, adapt layout |
| Modify | `app/views/sources/index.html.erb` | Add sidebar-compatible layout |
| Modify | `app/views/sources/show.html.erb` | Add sidebar-compatible layout |
| Create | `app/helpers/sources_helper.rb` | Favicon fallback helper |
| Modify | `app/views/pwa/manifest.json.erb` | Reference new favicon PNGs |
| Modify | `config/routes.rb` | Add PWA routes |
| Create | `test/fixtures/tags.yml` | Tag fixtures for tests |
| Create | `test/fixtures/taggings.yml` | Tagging fixtures for tests |
| Modify | `test/controllers/feed_controller_test.rb` | Tag filtering tests |
| Create | `test/helpers/sources_helper_test.rb` | Favicon helper tests |
| Modify | `test/system/feed_flow_test.rb` | Update search selector, add tag filter + sidebar tests |

---

## Task 1: Copy Favicon and Logo Assets from stray_old

**Files:**
- Copy: `app/assets/images/favicon/favicon.svg` (from stray_old)
- Copy: `app/assets/images/favicon/favicon.ico` (from stray_old)
- Copy: `app/assets/images/favicon/favicon-96x96.png` (from stray_old)
- Copy: `app/assets/images/favicon/apple-touch-icon.png` (from stray_old)
- Copy: `app/assets/images/favicon/web-app-manifest-192x192.png` (from stray_old)
- Copy: `app/assets/images/favicon/web-app-manifest-512x512.png` (from stray_old)
- Copy: `app/assets/images/stray-logo.svg` (from stray_old, overwrites current)
- Copy: `public/favicon.ico` (from stray_old)
- Remove: `public/icon.svg`, `public/icon.png`

- [ ] **Step 1: Copy the favicon directory from stray_old**

Run:
```bash
cp -r /home/bendangelo/Projects/stray_old/app/assets/images/favicon/ /home/bendangelo/Projects/stray/app/assets/images/favicon/
```

Verify:
```bash
ls -la /home/bendangelo/Projects/stray/app/assets/images/favicon/
```
Expected: 6 files (apple-touch-icon.png, favicon-96x96.png, favicon.ico, favicon.svg, web-app-manifest-192x192.png, web-app-manifest-512x512.png)

- [ ] **Step 2: Copy the wordmark logo from stray_old (overwrites current vector logo)**

Run:
```bash
cp /home/bendangelo/Projects/stray_old/app/assets/images/stray-logo.svg /home/bendangelo/Projects/stray/app/assets/images/stray-logo.svg
```

- [ ] **Step 3: Copy root-level favicon.ico from stray_old**

Run:
```bash
cp /home/bendangelo/Projects/stray_old/public/favicon.ico /home/bendangelo/Projects/stray/public/favicon.ico
```

- [ ] **Step 4: Remove old placeholder icons**

Run:
```bash
rm /home/bendangelo/Projects/stray/public/icon.svg /home/bendangelo/Projects/stray/public/icon.png
```

- [ ] **Step 5: Commit**

```bash
git add app/assets/images/favicon/ app/assets/images/stray-logo.svg public/favicon.ico
git rm public/icon.svg public/icon.png
git commit -m "assets: migrate favicon set and logo from stray_old"
```

---

## Task 2: Create Favicon Partial and Update Layout Head

**Files:**
- Create: `app/views/layouts/_favicon.html.erb`
- Modify: `app/views/layouts/application.html.erb:17-19`

- [ ] **Step 1: Create the favicon partial**

Create `app/views/layouts/_favicon.html.erb`:

```erb
<link rel="icon" type="image/png" href="<%= asset_path('favicon/favicon-96x96.png') %>" sizes="96x96">
<link rel="icon" type="image/svg+xml" href="<%= asset_path('favicon/favicon.svg') %>">
<link rel="shortcut icon" href="<%= asset_path('favicon/favicon.ico') %>">
<link rel="apple-touch-icon" sizes="180x180" href="<%= asset_path('favicon/apple-touch-icon.png') %>">
<meta name="apple-mobile-web-app-title" content="Stray">
```

- [ ] **Step 2: Update application.html.erb to use the favicon partial**

In `app/views/layouts/application.html.erb`, replace lines 17-19:

```erb
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">
```

with:

```erb
    <%= render "layouts/favicon" %>
```

- [ ] **Step 3: Verify the app still boots and serves a page**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb -v
```
Expected: All existing tests still pass (favicon change is in `<head>`, doesn't affect test assertions).

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/_favicon.html.erb app/views/layouts/application.html.erb
git commit -m "layout: use favicon partial with migrated assets"
```

---

## Task 3: Update PWA Manifest and Routes

**Files:**
- Modify: `app/views/pwa/manifest.json.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Update the PWA manifest to reference new favicon PNGs**

Replace the entire contents of `app/views/pwa/manifest.json.erb` with:

```erb
{
  "name": "Stray",
  "short_name": "Stray",
  "icons": [
    {
      "src": "<%= asset_path 'favicon/web-app-manifest-192x192.png' %>",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "maskable"
    },
    {
      "src": "<%= asset_path 'favicon/web-app-manifest-512x512.png' %>",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"
    }
  ],
  "theme_color": "#F8F2E8",
  "background_color": "#F8F2E8",
  "display": "standalone",
  "start_url": "/",
  "scope": "/"
}
```

- [ ] **Step 2: Add PWA routes**

In `config/routes.rb`, add after the `get "up"` line (line 5):

```ruby
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
```

- [ ] **Step 3: Uncomment the manifest link in application.html.erb**

In `app/views/layouts/application.html.erb`, replace line 15:

```erb
    <%#= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>
```

with:

```erb
    <%= tag.link rel: "manifest", href: pwa_manifest_path(format: :json) %>
```

- [ ] **Step 4: Verify manifest route responds**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb -v
```
Expected: All existing tests still pass. The manifest route is a new route, existing tests are unaffected.

- [ ] **Step 5: Commit**

```bash
git add app/views/pwa/manifest.json.erb config/routes.rb app/views/layouts/application.html.erb
git commit -m "pwa: update manifest with favicon assets and enable routes"
```

---

## Task 4: Create Sources Helper with Favicon Fallback

**Files:**
- Create: `app/helpers/sources_helper.rb`
- Create: `test/helpers/sources_helper_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/helpers/sources_helper_test.rb`:

```ruby
require "test_helper"

class SourcesHelperTest < ActionView::TestCase
  test "source_icon_url returns icon_url when present" do
    source = Source.new(url: "https://example.com", icon_url: "https://example.com/icon.png")
    assert_equal "https://example.com/icon.png", source_icon_url(source)
  end

  test "source_icon_url falls back to DuckDuckGo for youtube URLs" do
    source = Source.new(url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfeed", icon_url: nil)
    assert_equal "https://icons.duckduckgo.com/ip3/www.youtube.com.ico", source_icon_url(source)
  end

  test "source_icon_url falls back to DuckDuckGo for generic URLs" do
    source = Source.new(url: "https://bitchute.com/channel/feedbc", icon_url: nil)
    assert_equal "https://icons.duckduckgo.com/ip3/bitchute.com.ico", source_icon_url(source)
  end

  test "source_icon_url returns nil for invalid URLs" do
    source = Source.new(url: "not-a-url", icon_url: nil)
    assert_nil source_icon_url(source)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/helpers/sources_helper_test.rb -v
```
Expected: FAIL with `undefined method 'source_icon_url'`

- [ ] **Step 3: Write the helper**

Create `app/helpers/sources_helper.rb`:

```ruby
module SourcesHelper
  def source_icon_url(source)
    return source.icon_url if source.icon_url.present?

    uri = begin
      URI.parse(source.url)
    rescue URI::InvalidURIError
      nil
    end
    return nil unless uri&.host

    "https://icons.duckduckgo.com/ip3/#{uri.host}.ico"
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/helpers/sources_helper_test.rb -v
```
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add app/helpers/sources_helper.rb test/helpers/sources_helper_test.rb
git commit -m "helpers: add source_icon_url with DuckDuckGo favicon fallback"
```

---

## Task 5: Add Tag and Tagging Fixtures

**Files:**
- Create: `test/fixtures/tags.yml`
- Create: `test/fixtures/taggings.yml`

- [ ] **Step 1: Create tag fixtures**

Create `test/fixtures/tags.yml`:

```yaml
ruby:
  user: one
  name: "ruby"

rails:
  user: one
  name: "rails"

ai:
  user: one
  name: "ai"
```

- [ ] **Step 2: Create tagging fixtures**

Create `test/fixtures/taggings.yml`:

```yaml
video_one_ruby:
  item: video_one
  tag: ruby
  source: 0

video_one_rails:
  item: video_one
  tag: rails
  source: 0

video_two_ai:
  item: video_two
  tag: ai
  source: 0
```

- [ ] **Step 3: Verify fixtures load correctly**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb -v
```
Expected: All existing tests still pass (fixtures load but aren't used by existing tests yet).

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/tags.yml test/fixtures/taggings.yml
git commit -m "test: add tag and tagging fixtures"
```

---

## Task 6: Add Tag Filtering to FeedController

**Files:**
- Modify: `app/controllers/feed_controller.rb`
- Modify: `test/controllers/feed_controller_test.rb`

- [ ] **Step 1: Write failing tests for tag filtering**

Add to `test/controllers/feed_controller_test.rb` (append before the final `end`):

```ruby
  test "tag filter shows only items with that tag" do
    sign_in_as(users(:one))
    get root_path, params: { tag: "ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "tag filter combined with search" do
    sign_in_as(users(:one))
    get root_path, params: { q: "Ruby", tag: "ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "assigns tags collection for tag bar" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_not_nil assigns(:tags)
  end

  test "tag bar includes tag names" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_includes response.body, "ruby"
    assert_includes response.body, "rails"
    assert_includes response.body, "ai"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb -v
```
Expected: FAIL — new tag filter tests fail (no `@tags`, no tag filtering), `assigns(:tags)` is nil.

- [ ] **Step 3: Implement tag filtering in FeedController**

Replace the entire contents of `app/controllers/feed_controller.rb`:

```ruby
class FeedController < ApplicationController
  include Pagy::Method

  def index
    @q = params[:q].presence
    @tag = params[:tag].presence

    scope = Item.joins(source: :follow)
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(state: :hidden)

    scope = scope.search(@q) if @q
    scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag

    @pagy, @items = pagy(scope.order(published_at: :desc).distinct, limit: 20)

    @tags = Tag.joins(taggings: { item: [ source: :follow ] })
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(items: { state: :hidden })
      .group(:id, :name)
      .select(:name, "COUNT(*) AS item_count")
      .order("item_count DESC")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb -v
```
Expected: PASS — all existing + new tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/feed_controller.rb test/controllers/feed_controller_test.rb
git commit -m "feed: add tag filtering and tags collection for tag bar"
```

---

## Task 7: Create the Sidebar Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/sidebar_controller.js`

- [ ] **Step 1: Create the sidebar controller**

Create `app/javascript/controllers/sidebar_controller.js`:

```javascript
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
    if (this.openValue) {
      this.sidebarTarget.classList.remove("-translate-x-full")
      this.backdropTarget.classList.remove("hidden")
    } else {
      this.sidebarTarget.classList.add("-translate-x-full")
      this.backdropTarget.classList.add("hidden")
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/sidebar_controller.js
git commit -m "stimulus: add sidebar_controller for mobile drawer toggle"
```

---

## Task 8: Create the Sources Sidebar Partial

**Files:**
- Create: `app/views/sources/_sidebar.html.erb`

- [ ] **Step 1: Create the sidebar partial**

Create `app/views/sources/_sidebar.html.erb`:

```erb
<aside id="sidebar"
       class="fixed inset-y-0 left-0 z-40 w-64 border-r-3 border-charcoal bg-champagne overflow-y-auto transition-transform duration-200 -translate-x-full md:translate-x-0 md:static md:w-52 lg:w-60 md:z-0"
       data-sidebar-target="sidebar">
  <div class="p-4">
    <h2 class="font-display text-sm font-bold text-charcoal mb-3 uppercase tracking-wide">Sources</h2>

    <div class="space-y-1">
      <% if @sources&.any? %>
        <% unseen_counts = Item.where(source_id: @sources.map(&:id), state: :unseen).group(:source_id).count %>
      <% else %>
        <% unseen_counts = {} %>
      <% end %>

      <% @sources&.each do |source| %>
        <%= link_to source_path(source), class: "flex items-center gap-2 p-2 rounded-md hover:bg-athens-400" do %>
          <img src="<%= source_icon_url(source) || missing_thumb %>"
               alt=""
               class="w-8 h-8 rounded border-2 border-charcoal object-cover shrink-0"
               loading="lazy">

          <span class="flex-1 text-sm text-charcoal truncate"><%= source.name %></span>

          <% if unseen_counts[source.id].to_i > 0 %>
            <span class="text-xs font-bold text-champagne bg-carrot-500 px-1.5 py-0.5 rounded-full">
              <%= unseen_counts[source.id] %>
            </span>
          <% end %>
        <% end %>
      <% end %>
    </div>

    <%= link_to "All Sources", sources_path, class: "block mt-4 text-sm text-charcoal underline hover:no-underline" %>
  </div>
</aside>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/sources/_sidebar.html.erb
git commit -m "views: add sources sidebar partial with favicons and unseen counts"
```

---

## Task 9: Create the Tag Bar Partial

**Files:**
- Create: `app/views/shared/_tag_bar.html.erb`

- [ ] **Step 1: Create the tag bar partial**

Create `app/views/shared/_tag_bar.html.erb`:

```erb
<% if defined?(@tags) && @tags&.any? %>
  <div class="border-b-3 border-charcoal bg-champagne">
    <div class="flex overflow-x-auto whitespace-nowrap px-2 md:px-4 lg:px-16 py-2 gap-1">
      <% active_class = "border-b-6 border-carrot font-semibold text-carrot" %>
      <% inactive_class = "border-b-6 border-transparent text-charcoal hover:text-carrot" %>

      <%= link_to "All",
        root_path(request.query_parameters.except("tag", "page")),
        class: (@tag.blank? ? active_class : inactive_class) + " px-3 py-1 text-sm whitespace-nowrap" %>

      <% @tags.each do |tag| %>
        <%= link_to tag.name,
          root_path(request.query_parameters.except("page").merge(tag: tag.name)),
          class: (@tag == tag.name ? active_class : inactive_class) + " px-3 py-1 text-sm whitespace-nowrap" %>
      <% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/shared/_tag_bar.html.erb
git commit -m "views: add horizontal tag bar partial with filter links"
```

---

## Task 10: Rewrite the Navbar as the Header Bar

**Files:**
- Modify: `app/views/layouts/_navbar.html.erb`

- [ ] **Step 1: Rewrite the navbar partial**

Replace the entire contents of `app/views/layouts/_navbar.html.erb`:

```erb
<nav class="border-b-3 border-charcoal bg-champagne sticky top-0 z-30">
  <div class="flex items-center gap-2 px-2 md:px-4 lg:px-16 py-2">

    <% if authenticated? %>
      <button type="button"
              class="md:hidden text-charcoal p-1"
              data-action="click->sidebar#toggle"
              aria-label="Toggle sources">
        <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>
    <% end %>

    <%= link_to root_path, tabindex: "-1", class: "flex items-center shrink-0" do %>
      <%= image_tag "stray-logo.svg", alt: "Stray Logo", class: "w-0 md:w-20 lg:w-28" %>
      <%= image_tag "favicon/apple-touch-icon.png", alt: "Stray", class: "w-8 h-8 md:hidden rounded border-2 border-charcoal" %>
    <% end %>

    <% if authenticated? %>
      <div class="flex-1 flex justify-center">
        <%= form_with url: root_path, method: :get, class: "w-full max-w-xl flex",
          data: { turbo_frame: "_top" } do |form| %>
          <div class="flex items-center w-full rounded-md border-3 border-charcoal bg-athens-400">
            <%= form.text_field :q,
              value: @q,
              placeholder: "Search your feed...",
              class: "flex-1 h-10 px-3 bg-athens-400 rounded-l-md text-charcoal placeholder:text-charcoal-300 focus:outline-none text-sm" %>
            <button type="submit" class="text-carrot-600 hover:bg-carrot-500 hover:text-champagne h-10 w-10 flex items-center justify-center rounded-r-md">
              <svg class="w-5 h-5" fill="none" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
                <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2" d="m19 19-4-4m0-7A7 7 0 1 1 1 8a7 7 0 0 1 14 0" />
              </svg>
            </button>
          </div>
        <% end %>
      </div>

      <%= turbo_stream_from "user_#{current_user.id}_intake" %>

      <%= form_with url: links_path, class: "flex gap-1 shrink-0", data: { turbo_stream: true } do |form| %>
        <%= form.url_field :url,
          placeholder: "Paste a link...",
          class: "h-10 w-24 md:w-36 lg:w-64 px-2 bg-athens-400 border-3 border-charcoal rounded-md text-sm text-charcoal placeholder:text-charcoal-300 focus:outline-none" %>
        <%= form.submit "+",
          class: "h-10 w-10 bg-carrot-500 hover:bg-carrot-600 text-white font-bold rounded-md cursor-pointer border-3 border-charcoal shrink-0" %>
      <% end %>

      <span id="intake_status" class="text-charcoal text-sm shrink-0"></span>

      <div class="flex items-center gap-2 text-sm shrink-0">
        <span class="text-charcoal hidden sm:inline"><%= current_user.username %></span>
        <%= button_to "Log out", session_path, method: :delete, class: "text-charcoal hover:text-carrot-600 underline cursor-pointer bg-transparent border-none" %>
      </div>
    <% else %>
      <div class="flex-1"></div>
      <%= link_to "Log in", new_session_path, class: "text-charcoal hover:text-carrot-600 underline text-sm" %>
    <% end %>
  </div>
</nav>
```

- [ ] **Step 2: Verify existing tests still pass (the search form changed)**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb test/controllers/links_controller_test.rb -v
```
Expected: PASS — controller tests check response bodies, not form structure. The `links_controller_test` checks for `id="intake_status"` and "Checking" which are still present.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/_navbar.html.erb
git commit -m "layout: rewrite navbar as header bar with search, paste-link, and sidebar toggle"
```

---

## Task 11: Restructure the Application Layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Rewrite the layout body**

Replace the `<body>` section (lines 26-38) of `app/views/layouts/application.html.erb`:

```erb
  <body class="bg-champagne">
    <div data-controller="sidebar">
      <%= render "layouts/navbar" %>

      <%= yield :tag_bar %>

      <div class="flex">
        <% if authenticated? %>
          <%= render "sources/sidebar" %>
          <div data-sidebar-target="backdrop"
               class="hidden fixed inset-0 bg-charcoal/50 z-30 md:hidden"
               data-action="click->sidebar#close"></div>
        <% end %>

        <main class="flex-1 min-w-0">
          <% if flash[:alert] %>
            <div class="mx-auto max-w-md mt-4 px-4 py-3 border-3 border-cerise text-cerise text-sm"><%= flash[:alert] %></div>
          <% end %>
          <% if flash[:notice] %>
            <div class="mx-auto max-w-md mt-4 px-4 py-3 border-3 border-mint-500 text-mint-700 text-sm"><%= flash[:notice] %></div>
          <% end %>
          <%= yield %>
        </main>
      </div>
    </div>

    <%= render "layouts/footer" %>
  </body>
```

The `data-controller="sidebar"` wraps the entire content area so the hamburger button in the navbar (which uses `data-action="click->sidebar#toggle"`) can control the sidebar and backdrop targets below it.

- [ ] **Step 2: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "layout: restructure into three-zone shell with sidebar"
```

---

## Task 12: Make Sources Available App-Wide for Sidebar

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/sources_controller.rb`

- [ ] **Step 1: Add a before_action to set sidebar sources**

In `app/controllers/application_controller.rb`, add inside the class body (after `prepend_before_action :redirect_to_setup_if_needed`):

```ruby
  before_action :set_sidebar_sources, if: :authenticated?

  private

  def set_sidebar_sources
    @sources = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .where(active: true)
      .order(:name)
  end
```

- [ ] **Step 2: Remove the now-redundant query from SourcesController#index**

In `app/controllers/sources_controller.rb`, replace the `index` method (lines 4-9):

```ruby
  def index
    @sources = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .where(active: true)
      .order(:name)
  end
```

with:

```ruby
  def index
  end
```

- [ ] **Step 3: Verify all tests still pass**

Run:
```bash
bin/rails test test/controllers -v
```
Expected: PASS — `@sources` is now set by `ApplicationController` for all authenticated requests, so `sources/index` view and the sidebar partial both have it.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/application_controller.rb app/controllers/sources_controller.rb
git commit -m "controllers: set sidebar sources app-wide via before_action"
```

---

## Task 13: Update Feed Index View

**Files:**
- Modify: `app/views/feed/index.html.erb`
- Delete: `app/views/feed/_search.html.erb`

- [ ] **Step 1: Rewrite the feed index view**

Replace the entire contents of `app/views/feed/index.html.erb`:

```erb
<% content_for :tag_bar do %>
  <%= render "shared/tag_bar" %>
<% end %>

<div class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
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
        <% if @q.present? || @tag.present? %>
          No results<% if @q.present? %> for "<%= @q %>"<% end %><% if @tag.present? %> tagged "<%= @tag %>"<% end %>.
        <% else %>
          Your feed is empty. Add a link above to start following sources.
        <% end %>
      </p>
    </div>
  <% end %>

  <% if @pagy.pages > 1 %>
    <div class="mt-4 flex justify-center gap-2 text-sm">
      <% if @pagy.previous %>
        <%= link_to "← Newer", root_path(page: @pagy.previous, q: @q, tag: @tag),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
      <span class="text-charcoal-300"><%= @pagy.page %> / <%= @pagy.pages %></span>
      <% if @pagy.next %>
        <%= link_to "Older →", root_path(page: @pagy.next, q: @q, tag: @tag),
          class: "text-charcoal underline hover:no-underline" %>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Delete the now-unused search partial**

Run:
```bash
rm /home/bendangelo/Projects/stray/app/views/feed/_search.html.erb
```

- [ ] **Step 3: Update system tests for new search form**

In `test/system/feed_flow_test.rb`, the "search filters items" test (lines 43-51) uses `fill_in "q"` and `click_button "Search"`. The new header search form still has a field named `q`, but the submit button is now an icon `<button>` without text "Search". Update the test:

Replace the "search filters items" test (lines 43-51):

```ruby
  test "search filters items" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Ruby"
    find("button[type='submit']").click

    assert_text "First Video"
    assert_no_text "Second Video"
  end
```

with:

```ruby
  test "search filters items" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Ruby"
    within "nav form[action='/']" do
      find("button[type='submit']").click
    end

    assert_text "First Video"
    assert_no_text "Second Video"
  end
```

- [ ] **Step 4: Add system test for tag filtering**

Append to `test/system/feed_flow_test.rb` (before the final `end`):

```ruby
  test "clicking a tag filters the feed" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "ruby"
    click_on "ruby"

    assert_text "First Video"
    assert_no_text "Second Video"
  end
```

- [ ] **Step 5: Run all tests to verify**

Run:
```bash
bin/rails test test/controllers/feed_controller_test.rb test/system/feed_flow_test.rb -v
```
Expected: PASS — controller tests pass (tag filtering from Task 6), system tests pass with updated selectors.

- [ ] **Step 6: Commit**

```bash
git add app/views/feed/index.html.erb test/system/feed_flow_test.rb
git rm app/views/feed/_search.html.erb
git commit -m "feed: move search to header, add tag bar, adapt layout for sidebar"
```

---

## Task 14: Update Sources Index and Show Views for Sidebar Layout

**Files:**
- Modify: `app/views/sources/index.html.erb`
- Modify: `app/views/sources/show.html.erb`

- [ ] **Step 1: Update sources index to work within the sidebar layout**

Replace the entire contents of `app/views/sources/index.html.erb`:

```erb
<div class="container mx-auto px-4 pt-4 pb-16 max-w-3xl">
  <h1 class="font-display text-2xl font-bold text-charcoal mb-4">Sources</h1>

  <div class="space-y-2">
    <% @sources.each do |source| %>
      <%= link_to source_path(source), class: "block border-3 border-charcoal rounded-md bg-athens-400 p-4 hover:bg-athens-500" do %>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <img src="<%= source_icon_url(source) || missing_thumb %>"
                 alt=""
                 class="w-8 h-8 rounded border-2 border-charcoal object-cover shrink-0"
                 loading="lazy">
            <div>
              <span class="font-display font-bold text-charcoal"><%= source.name %></span>
              <span class="text-xs text-charcoal-300 ml-2"><%= source.kind.humanize %></span>
            </div>
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
</div>
```

- [ ] **Step 2: Update sources show to work within the sidebar layout**

Replace the opening `<main>` tag on line 1 of `app/views/sources/show.html.erb`:

```erb
<main class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
```

with:

```erb
<div class="container mx-auto px-4 pt-4 pb-16 max-w-screen-xl">
```

And replace the closing `</main>` at the end of the file (line 55) with `</div>`.

- [ ] **Step 3: Verify tests pass**

Run:
```bash
bin/rails test test/controllers/sources_controller_test.rb test/system/feed_flow_test.rb -v
```
Expected: PASS — sources index test checks for "Test Channel" and "BC Channel" text (still present). Source show test checks for item text and grid selector (still present).

- [ ] **Step 4: Commit**

```bash
git add app/views/sources/index.html.erb app/views/sources/show.html.erb
git commit -m "views: adapt sources index and show for sidebar layout"
```

---

## Task 15: Add System Tests for Sidebar and Tag Bar

**Files:**
- Modify: `test/system/feed_flow_test.rb`

- [ ] **Step 1: Add sidebar and tag bar system tests**

Append to `test/system/feed_flow_test.rb` (before the final `end`):

```ruby
  test "sources sidebar shows on feed page" do
    sign_in_as(users(:one))
    visit root_path

    assert_selector "#sidebar"
    assert_text "Test Channel", count: 2
  end

  test "sources sidebar shows unseen count badge" do
    sign_in_as(users(:one))
    visit root_path

    within "#sidebar" do
      assert_selector ".bg-carrot-500", minimum: 1
    end
  end
```

Note: "Test Channel" appears twice — once in the sidebar, once in the main feed if it's the source name shown on items. The `count: 2` may need adjustment depending on how many items from the youtube source are visible. If the test fails, adjust the count or scope the assertion to `within "#sidebar"`.

- [ ] **Step 2: Run system tests**

Run:
```bash
bin/rails test test/system/feed_flow_test.rb -v
```
Expected: PASS — all system tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/system/feed_flow_test.rb
git commit -m "test: add system tests for sidebar and tag bar"
```

---

## Task 16: Full Test Suite and Lint

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run:
```bash
bin/rails test -v
```
Expected: All tests pass. If any fail, investigate and fix before proceeding.

- [ ] **Step 2: Run RuboCop**

Run:
```bash
bin/rubocop
```
Expected: No offenses. If there are offenses, fix them.

- [ ] **Step 3: Run Brakeman**

Run:
```bash
bin/brakeman --no-pager
```
Expected: No security warnings related to the changes.

- [ ] **Step 4: Run full CI pass**

Run:
```bash
bin/ci
```
Expected: All checks pass.

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "ci: full suite passes after UI shell redesign"
```
(Only if there were fixes to commit.)
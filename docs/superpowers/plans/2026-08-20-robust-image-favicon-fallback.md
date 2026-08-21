# Robust Image & Favicon Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all external images (source favicons, item thumbnails) degrade gracefully when they 404 or fail to load, via a single Stimulus controller and a consolidated `ImagesHelper`.

**Architecture:** A new `ImageFallbackController` (Stimulus) lives on a wrapper element around each external `<img>`. On `error`, it either swaps `src` to a local fallback asset (for thumbnails) or hides the `<img>` and reveals a pre-rendered letter-avatar `<div>` sibling (for source icons). A new `ImagesHelper` centralizes all image rendering; the existing `SourcesHelper#source_icon` becomes a thin delegate. No schema changes, no ActiveStorage, no caching.

**Tech Stack:** Rails 8, Stimulus 3.2 (via importmap), Minitest, Capybara (headless Chrome).

**Spec:** `docs/superpowers/specs/2026-08-20-robust-image-favicon-fallback-design.md`

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `app/javascript/controllers/image_fallback_controller.js` | Stimulus controller: on `<img>` error, swap src or reveal letter fallback | Create |
| `app/helpers/images_helper.rb` | `fallback_image_tag` + `source_icon_tag` helpers | Create |
| `app/helpers/sources_helper.rb` | `source_icon` → delegate to `source_icon_tag` | Modify |
| `app/views/items/_item.html.erb` | Thumbnail + source-icon overlay | Modify |
| `app/views/items/_player.html.erb` | Thumbnail + source icon | Modify |
| `app/views/items/show.html.erb` | Two thumbnail `<img>` tags | Modify |
| `app/views/sources/_sidebar.html.erb` | Source icon | Modify |
| `test/helpers/images_helper_test.rb` | Helper unit tests | Create |
| `test/helpers/sources_helper_test.rb` | Update 2 assertions for new wrapper markup | Modify |
| `test/system/image_fallback_test.rb` | End-to-end: error event triggers fallback | Create |
| `docs/PLAN.md` | Note the deferred local-image-cache decision | Create |

Helper registration: Rails auto-includes all helpers in `app/helpers/` into all views by default (no `config.action_controller.default_helpers` override in this app — confirmed: `app/controllers/items_controller.rb` includes `ApplicationHelper` directly but views get all helpers via the default `helper :all`). The new `ImagesHelper` module is auto-loaded; no registration step needed.

Stimulus controller registration: `app/javascript/controllers/index.js` uses `eagerLoadControllersFrom("controllers", application)`, which auto-registers any `*_controller.js` file. The new `image_fallback_controller.js` is picked up automatically — no manual registration.

---

### Task 1: Create the `ImageFallbackController`

**Files:**
- Create: `app/javascript/controllers/image_fallback_controller.js`

- [ ] **Step 1: Write the controller**

Create `app/javascript/controllers/image_fallback_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "primary", "fallback" ]
  static values = { fallbackSrc: String }

  connect() {
    this.fallbackApplied = false
  }

  onError() {
    if (this.fallbackApplied) return
    this.fallbackApplied = true

    if (this.hasFallbackTarget) {
      this.primaryTarget.classList.add("hidden")
      this.fallbackTarget.classList.remove("hidden")
    } else if (this.fallbackSrcValue) {
      this.primaryTarget.src = this.fallbackSrcValue
    }
  }
}
```

- [ ] **Step 2: Verify it's registered**

Run: `bin/rails runner "puts Rails.application.importmap.pins.keys.grep(/image_fallback/)"`

Expected: prints `controllers/image_fallback_controller` (or similar). If empty, confirm the file is at `app/javascript/controllers/image_fallback_controller.js` (the `eagerLoadControllersFrom` in `index.js` auto-registers it).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/image_fallback_controller.js
git commit -m "feat: add ImageFallbackController for runtime image fallback"
```

---

### Task 2: Write failing helper tests for `fallback_image_tag`

**Files:**
- Create: `test/helpers/images_helper_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/helpers/images_helper_test.rb`:

```ruby
require "test_helper"

class ImagesHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "fallback_image_tag with nil src renders fallback directly without controller" do
    html = fallback_image_tag(nil, fallback: "/fallback.jpg", alt: "x", class: "w-10")
    assert_includes html, "/fallback.jpg"
    assert_includes html, "w-10"
    refute_includes html, "data-controller"
    refute_includes html, "image-fallback"
  end

  test "fallback_image_tag with empty src renders fallback directly without controller" do
    html = fallback_image_tag("", fallback: "/fallback.jpg", alt: "x")
    assert_includes html, "/fallback.jpg"
    refute_includes html, "data-controller"
  end

  test "fallback_image_tag with src renders wrapper with controller and img" do
    html = fallback_image_tag("https://example.com/a.jpg", fallback: "/fallback.jpg", alt: "A", class: "thumb")
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "https://example.com/a.jpg"
    assert_includes html, "thumb"
    assert_includes html, "error->image-fallback#onError"
    assert_includes html, "image_fallback_target"
    assert_includes html, "/fallback.jpg"
    assert_includes html, 'loading="lazy"'
  end

  test "fallback_image_tag uses missing_thumb default when no fallback given" do
    html = fallback_image_tag("https://example.com/a.jpg", alt: "A")
    assert_includes html, "missing-video.jpg"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/images_helper_test.rb`

Expected: FAIL with `NoMethodError: undefined method 'fallback_image_tag'` (the helper doesn't exist yet).

- [ ] **Step 3: Commit the failing test**

```bash
git add test/helpers/images_helper_test.rb
git commit -m "test: add failing tests for fallback_image_tag helper"
```

---

### Task 3: Implement `fallback_image_tag` in `ImagesHelper`

**Files:**
- Create: `app/helpers/images_helper.rb`

- [ ] **Step 1: Write the helper**

Create `app/helpers/images_helper.rb`:

```ruby
module ImagesHelper
  def fallback_image_tag(src, fallback: missing_thumb, alt: "", class: "", **opts)
    if src.blank?
      return image_tag(fallback, alt: alt, class: class, **opts)
    end

    content_tag :span, class: "inline-flex", data: { controller: "image-fallback" } do
      image_tag(src,
        alt: alt,
        class: class,
        loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError",
          image_fallback_fallback_src_value: fallback
        },
        **opts)
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `bin/rails test test/helpers/images_helper_test.rb`

Expected: PASS (4 tests).

- [ ] **Step 3: Commit**

```bash
git add app/helpers/images_helper.rb
git commit -m "feat: add ImagesHelper#fallback_image_tag with runtime fallback"
```

---

### Task 4: Write failing helper tests for `source_icon_tag`

**Files:**
- Modify: `test/helpers/images_helper_test.rb`

- [ ] **Step 1: Append the failing tests**

Add to the end of `test/helpers/images_helper_test.rb` (before the final `end`):

```ruby
  test "source_icon_tag with icon_url renders wrapper, img, and hidden letter div" do
    source = Source.new(url: "https://example.com", name: "Example", icon_url: "https://example.com/icon.png")
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "https://example.com/icon.png"
    assert_includes html, "image_fallback_target"
    assert_includes html, "error->image-fallback#onError"
    assert_includes html, ">E<"  # the letter
    assert_includes html, "hidden"  # letter div starts hidden
  end

  test "source_icon_tag with nil icon_url but valid source url uses DuckDuckGo favicon" do
    source = Source.new(url: "https://bitchute.com/channel/feedbc", name: "BC", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, "https://icons.duckduckgo.com/ip3/bitchute.com.ico"
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "hidden"  # letter fallback div
    assert_includes html, ">B<"  # letter B
  end

  test "source_icon_tag with invalid url renders letter div only, no img, no controller" do
    source = Source.new(url: "not-a-url", name: "Foo", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, ">F<"
    refute_includes html, "<img"
    refute_includes html, "data-controller"
    refute_includes html, "image-fallback"
  end

  test "source_icon_tag applies class param to the wrapper" do
    source = Source.new(url: "https://example.com", name: "Example", icon_url: "https://example.com/icon.png")
    html = source_icon_tag(source, size: "w-5 h-5", class: "absolute left-2 bottom-2")
    assert_includes html, "absolute left-2 bottom-2"
  end

  test "source_icon_tag handles empty source name gracefully" do
    source = Source.new(url: "not-a-url", name: "", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    refute_includes html, "<img"
    refute_includes html, "data-controller"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/images_helper_test.rb`

Expected: FAIL on the new tests with `NoMethodError: undefined method 'source_icon_tag'`. The first 4 `fallback_image_tag` tests still pass.

- [ ] **Step 3: Commit the failing tests**

```bash
git add test/helpers/images_helper_test.rb
git commit -m "test: add failing tests for source_icon_tag helper"
```

---

### Task 5: Implement `source_icon_tag` and delegate `source_icon`

**Files:**
- Modify: `app/helpers/images_helper.rb`
- Modify: `app/helpers/sources_helper.rb:38-47`

- [ ] **Step 1: Add `source_icon_tag` to `ImagesHelper`**

Add this method to `app/helpers/images_helper.rb` (inside the `module ImagesHelper` block, after `fallback_image_tag`):

```ruby
  def source_icon_tag(source, size: "w-8 h-8", class: "", **opts)
    url = source_icon_url(source)
    letter = source.name.to_s.first.upcase
    letter_classes = "#{size} rounded border-2 border-charcoal bg-charcoal " \
                     "text-white font-bold text-sm flex items-center justify-center shrink-0"

    if url.blank?
      return content_tag(:div, letter, class: "#{letter_classes} #{class}".strip, **opts)
    end

    content_tag :span, class: "inline-flex #{class}".strip,
                data: { controller: "image-fallback" } do
      concat(image_tag(url,
        alt: source.name,
        class: "#{size} rounded border-2 border-charcoal shrink-0 object-contain bg-white p-0.5",
        loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError"
        }))
      concat(content_tag(:div, letter,
        class: "hidden #{letter_classes}",
        data: { image_fallback_target: "fallback" }))
    end
  end
```

- [ ] **Step 2: Delegate `source_icon` to `source_icon_tag`**

In `app/helpers/sources_helper.rb`, replace the existing `source_icon` method (lines 38-47):

```ruby
  def source_icon(source, size: "w-8 h-8")
    source_icon_tag(source, size: size)
  end
```

Leave `source_icon_url` (lines 25-36) unchanged.

- [ ] **Step 3: Run the helper tests to verify they pass**

Run: `bin/rails test test/helpers/images_helper_test.rb`

Expected: PASS (9 tests).

- [ ] **Step 4: Run the existing sources helper tests to see what breaks**

Run: `bin/rails test test/helpers/sources_helper_test.rb`

Expected: The "renders image with icon_url when present" and "falls back to favicon image when icon_url is nil" tests may fail because the markup now includes a wrapper `<span>` and a hidden letter `<div>`. The `assert_match(/<img/, html)` assertions still pass (there's still an `<img>`), but `assert_includes html, "https://example.com/icon.png"` should still hold. Check the actual failure output — if the assertions still pass, skip to Step 5. If they fail, continue to Task 6 to fix them.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/images_helper.rb app/helpers/sources_helper.rb
git commit -m "feat: add source_icon_tag with letter-avatar fallback; delegate source_icon"
```

---

### Task 6: Update `sources_helper_test.rb` assertions for new wrapper markup

**Files:**
- Modify: `test/helpers/sources_helper_test.rb`

- [ ] **Step 1: Run the existing tests and inspect failures**

Run: `bin/rails test test/helpers/sources_helper_test.rb`

If all tests pass, the existing `assert_includes`/`assert_match` assertions are tolerant enough for the new markup (the `<img>` and its `src` are still present; the wrapper `<span>` and hidden letter `<div>` are additive). Skip to Step 3.

If any fail, the likely culprit is `refute_match(/<img/, html)` in the "renders letter avatar for invalid URLs" test — but that branch (no URL) renders only a `<div>` with no `<img>`, so it should still pass. Check the actual error.

- [ ] **Step 2: Fix any failing assertions**

The existing test at line 24-29 ("renders image with icon_url when present") asserts:
```ruby
assert_includes html, "https://example.com/icon.png"
assert_match(/<img/, html)
```
Both still hold with the new markup. No change needed.

The existing test at line 31-36 ("falls back to favicon image when icon_url is nil") asserts:
```ruby
assert_includes html, "https://icons.duckduckgo.com/ip3/bitchute.com.ico"
assert_match(/<img/, html)
```
Both still hold. No change needed.

The existing test at line 38-43 ("renders letter avatar for invalid URLs") asserts:
```ruby
assert_includes html, "B"
refute_match(/<img/, html)
```
Both still hold (no `<img>` in the no-URL branch). No change needed.

If all pass, proceed. If any fail unexpectedly, update the assertion to match the new markup — but the design's delegate preserves the same `<img>`/letter-div behavior, so failures here indicate a bug in the implementation, not the test. Fix the implementation, not the test.

- [ ] **Step 3: Verify all helper tests pass together**

Run: `bin/rails test test/helpers/`

Expected: PASS (all helper tests).

- [ ] **Step 4: Commit (only if any test files were modified)**

```bash
git add test/helpers/sources_helper_test.rb
git commit -m "test: update sources_helper assertions for image-fallback wrapper"
```

If no files were modified, skip this commit.

---

### Task 7: Migrate `items/_item.html.erb` (thumbnail + source icon overlay)

**Files:**
- Modify: `app/views/items/_item.html.erb:8-21`

- [ ] **Step 1: Replace the thumbnail `<img>` and source-icon `<img>`**

In `app/views/items/_item.html.erb`, replace lines 8-21:

```erb
      <img class="group-hover:border-2 border-carrot-400 object-cover w-full aspect-video rounded-md border-3 border-charcoal"
           src="<%= item.thumbnail_url || missing_thumb %>"
           alt="<%= item.title %>"
           loading="lazy">
      <% if video?(item) %>
        <div class="absolute inset-0 flex items-center justify-center pointer-events-none opacity-0 group-hover:opacity-100 scale-90 group-hover:scale-100 transition">
          <%= phosphor_icon "play", style: :fill, class: "w-10 h-10 text-white/80" %>
        </div>
      <% end %>
      <% if (icon = source_icon_url(item.source)) %>
        <img src="<%= icon %>" alt="" loading="lazy"
             class="absolute left-2 bottom-2 w-5 h-5 rounded border-2 border-charcoal bg-charcoal/80 object-cover">
      <% end %>
```

with:

```erb
      <%= fallback_image_tag(item.thumbnail_url,
            alt: item.title,
            class: "group-hover:border-2 border-carrot-400 object-cover w-full aspect-video rounded-md border-3 border-charcoal") %>
      <% if video?(item) %>
        <div class="absolute inset-0 flex items-center justify-center pointer-events-none opacity-0 group-hover:opacity-100 scale-90 group-hover:scale-100 transition">
          <%= phosphor_icon "play", style: :fill, class: "w-10 h-10 text-white/80" %>
        </div>
      <% end %>
      <%= source_icon_tag(item.source,
            size: "w-5 h-5",
            class: "absolute left-2 bottom-2") %>
```

Key changes:
- `fallback_image_tag` replaces the raw `<img>`. The `loading="lazy"` is now applied inside the helper, so it's removed from the call. The `class` is passed through.
- `source_icon_tag` replaces the `if (icon = source_icon_url(...))` block. The positioning classes (`absolute left-2 bottom-2`) move to the `class:` param on the wrapper. The `bg-charcoal/80` overlay style is dropped — the letter-avatar fallback already uses `bg-charcoal` (solid), which is close enough and avoids a per-call style override. (The original `<img>` had `bg-charcoal/80` as a translucent backdrop behind the tiny favicon; the letter fallback is solid charcoal, so the backdrop difference is negligible at 5x5px.)

- [ ] **Step 2: Run the existing item-related tests**

Run: `bin/rails test test/system/item_show_test.rb`

Expected: PASS. The system tests assert on text content and `iframe`/`button` selectors, not on the `<img>` tag structure, so the wrapper change shouldn't break them.

- [ ] **Step 3: Manual visual check (optional but recommended)**

Run: `bin/dev`, open the feed, and confirm:
- Item thumbnails render as before.
- The source-icon overlay appears at the bottom-left of thumbnails.
- To test the fallback: open browser DevTools, block the domain `icons.duckduckgo.com` (Network tab → block request domain), refresh, and confirm the letter avatar appears in place of the favicon.

- [ ] **Step 4: Commit**

```bash
git add app/views/items/_item.html.erb
git commit -m "feat: migrate item card to fallback_image_tag and source_icon_tag"
```

---

### Task 8: Migrate `items/_player.html.erb` (thumbnail + source icon)

**Files:**
- Modify: `app/views/items/_player.html.erb:11-13, 33-36`

- [ ] **Step 1: Replace the thumbnail `<img>`**

In `app/views/items/_player.html.erb`, the thumbnail branch (lines 11-13) is inside an `elsif`:

```erb
  <% elsif item.thumbnail_url.present? %>
    <img class="object-cover w-full lg:mx-6 lg:w-1/2 h-72 lg:h-96 rounded-md border-3 border-charcoal"
         src="<%= item.thumbnail_url %>" alt="<%= item.title %>">
```

Replace with:

```erb
  <% elsif item.thumbnail_url.present? %>
    <%= fallback_image_tag(item.thumbnail_url,
          alt: item.title,
          class: "object-cover w-full lg:mx-6 lg:w-1/2 h-72 lg:h-96 rounded-md border-3 border-charcoal") %>
```

The `elsif ...present?` guard stays — the player only shows a thumbnail section when one exists. (If the URL is present but 404s at runtime, the fallback controller swaps to `missing-video.jpg`, which is the desired graceful degradation.)

- [ ] **Step 2: Replace the source-icon `<img>`**

Replace lines 33-36:

```erb
      <% if (icon = source_icon_url(item.source)) %>
        <img src="<%= icon %>" alt="" loading="lazy"
             class="w-5 h-5 rounded border-2 border-charcoal object-cover">
      <% end %>
```

with:

```erb
      <%= source_icon_tag(item.source, size: "w-5 h-5") %>
```

- [ ] **Step 3: Run player-related system tests**

Run: `bin/rails test test/system/item_show_test.rb`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/views/items/_player.html.erb
git commit -m "feat: migrate player partial to fallback_image_tag and source_icon_tag"
```

---

### Task 9: Migrate `items/show.html.erb` (two thumbnail `<img>` tags)

**Files:**
- Modify: `app/views/items/show.html.erb:34-35, 51-52`

- [ ] **Step 1: Replace the video-branch thumbnail**

In `app/views/items/show.html.erb`, replace lines 34-35:

```erb
        <img class="object-cover w-full aspect-video rounded-md border-3 border-charcoal"
             src="<%= @item.thumbnail_url %>" alt="<%= @item.title %>">
```

with:

```erb
        <%= fallback_image_tag(@item.thumbnail_url,
              alt: @item.title,
              class: "object-cover w-full aspect-video rounded-md border-3 border-charcoal") %>
```

- [ ] **Step 2: Replace the non-video-branch thumbnail**

Replace lines 51-52:

```erb
        <img class="object-cover w-full aspect-video rounded-md border-3 border-charcoal mb-4"
             src="<%= @item.thumbnail_url %>" alt="<%= @item.title %>">
```

with:

```erb
        <%= fallback_image_tag(@item.thumbnail_url,
              alt: @item.title,
              class: "object-cover w-full aspect-video rounded-md border-3 border-charcoal mb-4") %>
```

- [ ] **Step 3: Run show-page system tests**

Run: `bin/rails test test/system/item_show_test.rb`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add app/views/items/show.html.erb
git commit -m "feat: migrate item show page thumbnails to fallback_image_tag"
```

---

### Task 10: Migrate `sources/_sidebar.html.erb` (source icon)

**Files:**
- Modify: `app/views/sources/_sidebar.html.erb:18-21`

- [ ] **Step 1: Replace the source-icon `<img>`**

In `app/views/sources/_sidebar.html.erb`, replace lines 18-21:

```erb
            <img src="<%= source_icon_url(source) || missing_thumb %>"
                 alt=""
                 class="w-8 h-8 rounded border-2 border-charcoal object-cover shrink-0"
                 loading="lazy">
```

with:

```erb
            <%= source_icon_tag(source, size: "w-8 h-8") %>
```

Note: the old `|| missing_thumb` was a weaker fallback (only fired when the URL *resolver* returned nil). The new helper covers both the nil-URL case (letter avatar) and the runtime-404 case (letter avatar via JS). The `shrink-0` class was on the old `<img>`; the new helper applies `shrink-0` inside `letter_classes` for the letter div, and the `<img>` gets `shrink-0` in its class string. The wrapper `<span class="inline-flex">` doesn't have `shrink-0` — add it to prevent the wrapper from shrinking inside the flex parent:

```erb
            <%= source_icon_tag(source, size: "w-8 h-8", class: "shrink-0") %>
```

- [ ] **Step 2: Run sidebar-related system tests**

Run: `bin/rails test test/system/sources_test.rb`

Expected: PASS (the sidebar renders; tests assert on text/links, not `<img>` structure).

- [ ] **Step 3: Commit**

```bash
git add app/views/sources/_sidebar.html.erb
git commit -m "feat: migrate sidebar source icons to source_icon_tag"
```

---

### Task 11: Write the system test for runtime image fallback

**Files:**
- Create: `test/system/image_fallback_test.rb`

- [ ] **Step 1: Write the system test**

Create `test/system/image_fallback_test.rb`:

```ruby
require "test_helper"
require "application_system_test_case"

class ImageFallbackTest < ApplicationSystemTestCase
  test "thumbnail swaps to missing-video.jpg when remote image errors" do
    sign_in_as(users(:one))
    item = items(:video_one)
    item.update!(thumbnail_url: "https://invalid.example/broken.jpg")
    visit root_path

    img = find("img[src='https://invalid.example/broken.jpg']", wait: 2)
    img.execute_script("this.dispatchEvent(new Event('error', { bubbles: true }))")

    assert_equal asset_url("missing-video.jpg"), img["src"]
  end

  test "source icon falls back to letter avatar when remote favicon errors" do
    sign_in_as(users(:one))
    source = sources(:video)
    source.update!(icon_url: "https://invalid.example/broken-favicon.ico", name: "TestSource")
    visit root_path

    img = find("img[src='https://invalid.example/broken-favicon.ico']", wait: 2)
    img.execute_script("this.dispatchEvent(new Event('error', { bubbles: true }))")

    wrapper = img.find(:xpath, "..")
    letter_div = wrapper.find("[data-image-fallback-target='fallback']")
    refute_includes letter_div[:class], "hidden"
    assert_includes img[:class], "hidden"
    assert_includes letter_div.text, "T"
  end
end
```

Notes on the test:
- `asset_url("missing-video.jpg")` resolves to the full URL the asset pipeline serves. The `img["src"]` after the swap should match this. If `asset_url` isn't available in system tests (it's a view helper), use a regex or `assert_includes img["src"], "missing-video.jpg"` instead. Prefer the tolerant `assert_includes` form:
  ```ruby
  assert_includes img["src"], "missing-video.jpg"
  ```
- The `execute_script` dispatches a synthetic `error` event because headless Chrome won't reliably 404 on a fake localhost URL (it may just hang or timeout). The synthetic event deterministically triggers the Stimulus controller.
- `find(:xpath, "..")` gets the parent wrapper `<span>` of the `<img>`.

- [ ] **Step 2: Run the system test to verify it passes**

Run: `bin/rails test:system test/system/image_fallback_test.rb`

Expected: PASS (2 tests). If the first test fails on the `src` assertion, replace `assert_equal asset_url(...)` with `assert_includes img["src"], "missing-video.jpg"` and re-run.

If the second test fails because the `img` isn't found (e.g. the feed doesn't show that source's items), adjust the fixture or visit the source show page instead: `visit source_path(source)` and find the icon there.

- [ ] **Step 3: Commit**

```bash
git add test/system/image_fallback_test.rb
git commit -m "test: add system test for runtime image fallback behavior"
```

---

### Task 12: Add deferred-cache note to `docs/PLAN.md`

**Files:**
- Create: `docs/PLAN.md`

- [ ] **Step 1: Check if `docs/PLAN.md` exists**

Run: `ls docs/PLAN.md`

If it exists, read it and append the note to an appropriate "Future" / "Deferred" section. If it doesn't exist, create it.

- [ ] **Step 2: Create or update `docs/PLAN.md`**

If creating new:

```markdown
# Stray Product Roadmap

AGENTS.md references this file. It tracks deferred decisions and future work.

## Deferred

### Local image cache / proxy

Download favicons and item thumbnails once, serve from the app (ActiveStorage or a `/img/proxy?u=...` controller with Solid Cache). Survives third-party outages, improves privacy (no referrer leaks to CDNs), and enables offline-ish reading.

**Why deferred:** Adds storage growth, cleanup jobs, and volume-sizing concerns that conflict with the one-command self-host principle for v1. The robust runtime fallback (added 2026-08-20) solves the visible broken-image problem without this cost.

**Revisit when:** The broken-image fallback proves insufficient (e.g. third-party CDNs are down for extended periods and users want images to persist).

**See:** `docs/superpowers/specs/2026-08-20-robust-image-favicon-fallback-design.md`
```

- [ ] **Step 3: Commit**

```bash
git add docs/PLAN.md
git commit -m "docs: add deferred local-image-cache note to PLAN.md"
```

---

### Task 13: Final verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`

Expected: PASS (all unit + integration + helper tests).

- [ ] **Step 2: Run the system tests**

Run: `bin/rails test:system`

Expected: PASS (all system tests including the new `image_fallback_test.rb`).

- [ ] **Step 3: Run RuboCop**

Run: `bin/rubocop`

Expected: No offenses in the new/modified files. If offenses appear, fix them (the helper uses named kwargs like `class:` which may need RuboCop's `Style/ClassAndModuleChildren` or `Layout/ArgumentAlignment` attention — match the style used by existing helpers in the repo).

- [ ] **Step 4: Run the full CI pass**

Run: `bin/ci`

Expected: PASS. If anything fails, fix and re-run.

- [ ] **Step 5: Manual smoke test**

Run: `bin/dev`, open the app, and verify:
1. Feed page: item thumbnails render; source-icon overlays render.
2. Open a source's show page (`/sources/:id`): source icon renders.
3. Block `icons.duckduckgo.com` in DevTools Network → block request. Refresh. Source icons in the sidebar and item overlays should show the letter avatar.
4. Block a thumbnail CDN domain (e.g. `i.ytimg.com`). Refresh. Item thumbnails should show `missing-video.jpg`.
5. Open the player (click an item). Thumbnail and source icon render.
6. Open the item detail page (`/items/:id`). Thumbnail renders.

- [ ] **Step 6: Commit any final fixes (if any)**

If the smoke test surfaced issues, fix and commit them. Otherwise, the plan is complete.
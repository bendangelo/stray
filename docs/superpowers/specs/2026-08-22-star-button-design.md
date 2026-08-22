# Star Button — Player, Details Page, and Thumbnail Badge

**Date:** 2026-08-22
**Status:** Approved

## Problem

Starring (saving) an item is currently only reachable through the overflow `...` menu on the feed card, the player, and the details page. The star state is invisible until you open the menu — there is no always-present toggle, and no way to glance at the grid and see which videos you've starred.

## Solution

1. **Always-visible star toggle** on the player and details page, next to the title / in the meta row.
2. **Display-only star badge** on thumbnails for saved items (top-left corner, opposite the unseen dot).
3. **Shared partial** drives both the new toggle and the existing menu entry, so they share state and Turbo Stream feedback.
4. **Extend `update.turbo_stream.erb`** to also replace the star button(s) on the page, so toggling reflects instantly on whichever surface you're viewing.

No new routes, models, or controller actions. Reuses `Item#state = :saved` and the existing `PATCH /items/:id` flow. The `saved → :starred` `Ranking.apply_interaction!` mapping is unchanged.

## Components

### 1. New partial: `app/views/items/_star_button.html.erb`

A self-contained star toggle with a stable dom_id (`item_star_<id>`) so Turbo Stream can target it regardless of which page rendered it.

**Variants** (controlled by a local, not separate partials):

- **Default** (no variant arg) — icon-only button used inline on the player title row and the details page meta row. Sized to match the actions menu button (`min-w-9 min-h-9 p-2`).
- **`variant: :menu`** — block, full-width dropdown item with a text label ("Star"/"Unstar"), used inside `_actions_menu.html.erb` to replace the inline `action_link_to` star entry. Same `item_star_<id>` id so Turbo Stream replace updates it in sync with the inline button.

**Markup (default variant):**

```erb
<%= action_link_to item_path(item), method: :patch,
      params: { state: item.saved? ? "unseen" : "saved" },
      data: { turbo_stream: true },
      aria: { pressed: item.saved?, label: item.saved? ? "Unstar" : "Star" },
      title: item.saved? ? "Unstar" : "Star",
      class: "...text-charcoal-300 hover:text-carrot-500 rounded-md bg-transparent border-none cursor-pointer p-2 min-w-9 min-h-9 inline-flex items-center justify-center" do %>
  <%= phosphor_icon "star", style: item.saved? ? :fill : :regular, class: "w-4 h-4" %>
<% end %>
```

The `action_link_to` helper already handles `turbo_method: :patch` and query param appending. `aria-pressed` reflects state for assistive tech.

**Markup (menu variant):**

```erb
<%= action_link_to item_path(item), method: :patch,
      params: { state: item.saved? ? "unseen" : "saved" },
      data: { turbo_stream: true },
      class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer" do %>
  <%= phosphor_icon "star", style: item.saved? ? :fill : :regular, class: "w-3.5 h-3.5" %>
  <%= item.saved? ? "Unstar" : "Star" %>
<% end %>
```

Wrapping the partial in a `<span id="item_star_<%= item.id %>" class="inline-flex">` so Turbo Stream `replace` targets the wrapper, not the link — this keeps the id stable across re-renders regardless of which variant is active.

### 2. Player (`app/views/items/_player.html.erb`)

Insert the star button in the title row (lines 18-24), before the actions menu, with the title keeping `flex-1 min-w-0`:

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

### 3. Details page (`app/views/items/show.html.erb`)

Add the star button in the existing meta row (lines 11-29), after the "Open at source" link and before the actions menu:

```erb
<%= link_to @item.url, target: "_blank", rel: "noopener",
      class: "inline-flex items-center gap-1 text-carrot-600 hover:underline" do %>
  Open at source <%= phosphor_icon "arrow-up-right", class: "w-3 h-3" %>
<% end %>
<%= render "items/star_button", item: @item %>
<%= render "items/actions_menu", item: @item %>
```

### 4. Thumbnail badge (`app/views/items/_item.html.erb`)

In the thumbnail overlay region (after the unseen dot at lines 25-27), add a display-only star badge in the **top-left** corner, shown only when `item.saved?`:

```erb
<% if item.saved? %>
  <span class="absolute top-2 left-2 text-carrot-500 drop-shadow-sm" title="Starred">
    <%= phosphor_icon "star", style: :fill, class: "w-4 h-4" %>
  </span>
<% end %>
```

No click handler — the thumbnail already opens the player on click. The badge is pure status display. Top-left is chosen so it doesn't collide with:
- Unseen dot (top-right)
- Source icon (bottom-left)
- Duration badge (bottom-right)
- Play overlay (center)

### 5. Turbo Stream feedback (`app/views/items/update.turbo_stream.erb`)

Extend to also replace any `item_star_<id>` elements on the page, in addition to the feed card replacement:

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

`turbo_stream.replace` targets by id. Since the wrapper span carries `id="item_star_<id>"` in every variant, a single PATCH updates whichever surface(s) are on the page — the feed card's menu item, the player's inline button, or the details page's meta-row button. The thumbnail badge updates via the `turbo_stream.replace dom_id(item)` (full card re-render) that already runs for non-hidden states.

### 6. Actions menu (`app/views/items/_actions_menu.html.erb`)

Replace the inline `action_link_to` star entry (lines 24-29) with the shared partial:

```erb
<%= render "items/star_button", item: item, variant: :menu %>
```

Removes duplication, ensures the menu item and the inline buttons stay in sync visually and behaviorally.

## Files Changed

| File | Change |
|---|---|
| `app/views/items/_star_button.html.erb` | **New** — shared star toggle partial, default + menu variants, `item_star_<id>` wrapper |
| `app/views/items/_player.html.erb` | Add `<%= render "items/star_button", item: item %>` to title row before actions menu |
| `app/views/items/show.html.erb` | Add `<%= render "items/star_button", item: @item %>` to meta row before actions menu |
| `app/views/items/_item.html.erb` | Add top-left star badge for `item.saved?` thumbnails |
| `app/views/items/_actions_menu.html.erb` | Replace inline star entry with `<%= render "items/star_button", item: item, variant: :menu %>` |
| `app/views/items/update.turbo_stream.erb` | Add `turbo_stream.replace "item_star_#{item.id}"` for non-hidden states |

## Tests

1. **System test** — feed → open player → click star → assert icon switches to filled, assert `aria-pressed` flips, assert thumbnail now shows top-left star badge after stream replace.
2. **System test** — details page → click star in meta row → assert toggle reflects, assert state persists after reload (navigate away and back).
3. **System test** — star an item via the player, then open the overflow menu on the feed card and assert the menu entry reads "Unstar" (single source of truth).
4. **Controller test** — existing `PATCH /items/:id state=saved` test should still pass; add assertion that the Turbo Stream response body includes an `item_star_` replace action.

## Out of Scope

- No new routes, models, or controller actions.
- No new Stimulus controller — the existing Turbo Stream round-trip is sufficient.
- No changes to `Ranking.apply_interaction!` or `Interaction` — the `saved → :starred` mapping is unchanged.
- No change to the unseen dot logic; starred-and-unseen items show both badges (top-left star, top-right dot) since they're orthogonal signals.
- No star *toggle* on the thumbnail itself — toggling stays on the player/details page to avoid a second interactive zone on a click target that already opens the player.
- No bulk star/unstar.
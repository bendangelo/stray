# Ranking, Tags & Overflow Menu — Design

Date: 2026-08-16
Status: Approved
Scope: Implement v1 weighted-chronological feed ranking (Interactions, weight nudging, mute-enough, "why" UI), wire up tag autocomplete + allow removing AI tags, polish overflow menu hover states.

## Goal

Make `Follow.weight` actually affect the feed (currently dead), with explainable math; record the interactions that nudge weight; let users see *why* each item is where it is; finish the stubbed tag autocomplete; allow removing AI-sourced tags; polish the actions menu.

## Non-goals

- v2 "similar to saved" embedding-based ranking — separate future spec.
- `sqlite-vec` — brute-force is fine; no vector index needed for weight ranking (pure SQL).
- Implicit behavioral tracking (dwell/scroll) — explicitly out per AGENTS.md.
- Distinguishing extractor-origin `:user` tags from manual `:user` tags in provenance labels — v2.
- A dedicated video/item show page — keeping the inline grid player (per 2026-08-14 spec).

## Architecture

```
User action (hide/save/open/mute-source)
  → ItemsController#update / #player
  → Interaction.create!(kind:)
  → Follow.weight nudge (synchronous, clamped)
  → if 3+ hidden interactions on source's items in 7d → Follow.muted = true
  → feed_controller ORDER BY effective_time DESC
  → item card <details> shows: recency, weight factor, effective position
```

The feed stays reverse-chronological at its core; weight becomes an **additive time offset** so every ranking decision is human-readable.

## Section 1 — Ranking math

**Formula:** `effective_time = published_at + (weight - 1.0) * BOOST_WINDOW`

- `BOOST_WINDOW = 24.hours` (tunable constant in `lib/stray/ranking.rb`).
- weight 1.5 → item behaves as if published **12h later** (boosted toward top).
- weight 0.5 → item behaves as if published **12h earlier** (demoted).
- weight 1.0 → unchanged (the common case; no offset).

**Clamp:** `Follow.weight` clamped to `[0.1, 3.0]` via `before_save` callback on `Follow`. The existing Reset link (back to 1.0) stays.

**SQL** (in `feed_controller.rb`, replacing `order(published_at: :desc)`):

```ruby
scope
  .joins(:source) # already joined via follows
  .order(Arel.sql(
    "datetime(items.published_at, '+' || ((follows.weight - 1.0) * #{Stray::Ranking::BOOST_HOURS}) || ' hours') DESC"
  ))
```

`follows.weight` is already available because `feed_controller.rb:8` joins `source: :follows`. No new join needed.

**Source show page** (`sources_controller.rb:16`) keeps `order(published_at: :desc)` — weight ranking is feed-wide; within a single source, pure recency is correct and matches user expectation.

## Section 2 — Interaction model + nudge logic

### Migration

New `interactions` table:

```ruby
create_table "interactions" do |t|
  t.references :item, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.integer :kind, null: false          # 0=opened, 1=starred, 2=hidden, 3=muted_source
  t.datetime :created_at, null: false
  t.index [:item_id, :user_id, :kind], unique: true, name: "index_interactions_on_item_user_kind_unique"
  t.index [:user_id, :created_at]
end
```

Unique index: one of each `kind` per item per user (re-opening an already-opened item is a no-op).

### Model `app/models/interaction.rb`

```ruby
class Interaction < ApplicationRecord
  belongs_to :item
  belongs_to :user
  enum :kind, { opened: 0, starred: 1, hidden: 2, muted_source: 3 }
  validates :kind, uniqueness: { scope: [:item_id, :user_id] }
end
```

### Nudge constants (`lib/stray/ranking.rb`)

```ruby
OPEN_BOOST      = 0.05
STAR_BOOST      = 0.10
HIDE_PENALTY    = 0.10
MUTE_PENALTY    = 0.30
MUTE_WINDOW     = 7.days
MUTE_THRESHOLD  = 3
WEIGHT_MIN      = 0.1
WEIGHT_MAX      = 3.0
BOOST_HOURS     = 24
```

### Where interactions get written

**`ItemsController#update`** (currently only flips `Item.state` at `items_controller.rb:18`):

```ruby
def update
  item = Item.find_by(id: params[:id], user_id: current_user.id)
  return head :not_found unless item

  state = params[:state]
  return head :bad_request unless ALLOWED_STATES.include?(state)

  item.update!(state: state)
  Stray::Ranking.apply_interaction!(user: current_user, item: item, kind: interaction_kind_for(state))

  respond_to do |format|
    format.turbo_stream { render "items/update", locals: { item:, state: } }
    format.html { redirect_to root_path }
  end
end

private

def interaction_kind_for(state)
  { "saved" => :starred, "hidden" => :hidden, "unseen" => nil }.fetch(state, nil)
end
```

**`ItemsController#player`** (`items_controller.rb:4-9`) — opening the inline player records an `:opened` interaction (once per item per user, via the unique index):

```ruby
def player
  item = Item.find_by(id: params[:id], user_id: current_user.id)
  return head :not_found unless item

  Stray::Ranking.apply_interaction!(user: current_user, item: item, kind: :opened)
  render partial: "items/player", locals: { item: }, layout: false
end
```

### `Stray::Ranking.apply_interaction!`

`lib/stray/ranking.rb`:

```ruby
module Stray
  module Ranking
    DELTAS = { opened: OPEN_BOOST, starred: STAR_BOOST, hidden: -HIDE_PENALTY, muted_source: -MUTE_PENALTY }.freeze

    def self.apply_interaction!(user:, item:, kind:)
      return if kind.nil?

      follow = Follow.find_by(user_id: user.id, source_id: item.source_id)
      return unless follow

      created = Interaction.find_or_create_by!(item: item, user: user, kind: kind) do |i|
        # no extra attrs
      end

      # Only nudge on first occurrence (unique index means find_or_create created it now)
      return unless created.previously_new_record?

      follow.weight = clamp(follow.weight + DELTAS.fetch(kind))
      follow.muted = muted_enough?(user: user, source_id: item.source_id)
      follow.save!
    end

    def self.muted_enough?(user:, source_id:)
      Interaction.joins(:item)
        .where(user_id: user.id, kind: :hidden)
        .where("interactions.created_at >= ?", MUTE_WINDOW.ago)
        .where(items: { source_id: source_id })
        .count >= MUTE_THRESHOLD
    end

    def self.clamp(weight)
      weight.clamp(WEIGHT_MIN, WEIGHT_MAX)
    end

    def self.order_sql
      "datetime(items.published_at, '+' || ((follows.weight - 1.0) * #{BOOST_HOURS}) || ' hours') DESC, items.published_at DESC"
    end
  end
end
```

### `Follow` changes

`app/models/follow.rb`:

```ruby
class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :source
  validates :source_id, uniqueness: { scope: :user_id }
  before_save :clamp_weight
  private
  def clamp_weight
    self.weight = Stray::Ranking.clamp(weight)
  end
end
```

Migration adds `muted` boolean to `follows`:

```ruby
add_column :follows, :muted, :boolean, default: false, null: false
```

### "Mute this source" action (new, in actions menu)

A fourth item in `items/_actions_menu.html.erb`:

```erb
<%= action_link_to mute_source_path(item.source), method: :post,
      data: { turbo_stream: true },
      class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer" do %>
  <%= phosphor_icon "speaker-slash", class: "w-3.5 h-3.5 inline-block" %> Mute source
<% end %>
```

Route: `POST /sources/:id/mute` → `SourcesController#mute` → creates `Interaction(kind: :muted_source)` + nudges weight by `MUTE_PENALTY` + sets `follow.muted = true`.

`SourcesController#unmute` (new): clears `follow.muted`, leaves weight as-is (user can Reset separately if desired).

## Section 3 — Feed controller + muted toggle

### `FeedController#index` (rewrite of `feed_controller.rb:8-16`)

```ruby
def index
  @q = params[:q].presence
  @tag = params[:tag].presence
  @show_muted = params[:show_muted] == "1"

  scope = Item.joins(source: :follows)
    .where(follows: { user_id: current_user.id })
    .where(items: { user_id: current_user.id })
    .where.not(state: :hidden)
    .includes(source: :follows)

  scope = scope.where(follows: { muted: false }) unless @show_muted

  scope = scope.search(@q) if @q
  scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag

  @pagy, @items = pagy(
    scope.order(Arel.sql(Stray::Ranking.order_sql)).distinct,
    limit: 20
  )

  @muted_count = current_user.follows.where(muted: true).count
  @tags = Tag.joins(taggings: { item: [ source: :follows ] })
    .where(follows: { user_id: current_user.id })
    .where(items: { user_id: current_user.id })
    .where.not(items: { state: :hidden })
    .group(:id, :name)
    .select(:name, "COUNT(*) AS item_count")
    .order("item_count DESC")
end
```

### "Show muted" toggle (feed header)

`app/views/shared/_muted_toggle.html.erb`, rendered in `feed/index.html.erb` next to the tag bar — only when `@muted_count > 0`:

```erb
<% if @muted_count > 0 %>
  <div class="ml-auto text-xs">
    <%= link_to root_path(show_muted: @show_muted ? "0" : "1"),
          class: "px-2 py-1 rounded-md border-3 border-charcoal #{@show_muted ? 'bg-mint text-charcoal' : 'bg-athens-400 text-charcoal hover:bg-athens-500'}" do %>
      <%= phosphor_icon "speaker-slash", class: "w-3 h-3 inline-block" %>
      <%= @show_muted ? "Hiding" : "Showing" %> <%= @muted_count %> muted
    <% end %>
  </div>
<% end %>
```

## Section 4 — "Why is this here" UI

### Helper `app/helpers/ranking_helper.rb`

```ruby
module RankingHelper
  def ranking_explanation_for(item, follow)
    offset_hours = ((follow.weight - 1.0) * Stray::Ranking::BOOST_HOURS).round(1)
    OpenStruct.new(
      published_at: item.published_at,
      weight: follow.weight,
      offset_hours: offset_hours,
      effective_at: item.published_at&.then { |t| t + offset_hours.hours },
      muted: follow.muted
    )
  end

  def offset_label(hours)
    return "no weight adjustment" if hours.zero?
    sign = hours.positive? ? "+" : "−"
    "#{sign}#{hours.abs}h"
  end
end
```

### Partial `app/views/items/_why.html.erb`

```erb
<% exp = ranking_explanation_for(item, follow) %>
<details class="mt-1 text-xs text-charcoal-300">
  <summary class="cursor-pointer hover:text-carrot-500 select-none">why?</summary>
  <div class="mt-1 pl-2 border-l-2 border-charcoal space-y-0.5">
    <p>Published <%= time_ago(exp.published_at) %>.</p>
    <p>Weight <%= exp.weight %> from <%= item.source.name %> — <%= offset_label(exp.offset_hours) %>.</p>
    <p>Shown as if published <%= time_ago(exp.effective_at) %>.</p>
    <% if exp.muted %>
      <p class="text-cerise">Source muted (3+ hides in the last week).</p>
    <% end %>
  </div>
</details>
```

Rendered in `items/_item.html.erb` after the timestamp row (around line 42) and in `items/_player.html.erb` similarly. `follow` is resolved via `item.source.follows.find_by(user_id: current_user.id)` — eager-loaded via `includes(source: :follows)` in the feed controller so no N+1.

## Section 5 — Tag editing improvements

### 5a. Autocomplete in `tag_input_controller.js`

Replace the stubbed `search()` (lines 28-37) with a working results dropdown:

- Inject a `<ul data-tag-input-target="results">` below the input.
- Debounce fetch 150ms.
- `GET /tags/search?q=...` → render up to 5 matches as `<li>`; click → set input value → `submit()`.
- Keyboard: ArrowDown/Up to move highlight, Enter selects highlighted (or submits current input if none highlighted), Esc closes.
- If input is non-empty and no exact match exists, render a final `<li>Create "<input>"</li>` that calls `submit()` directly.
- Close on outside click (already wired via `click@window->dropdown#hide`).

No controller split needed; the existing single controller gains a `results` target and a small `highlightIndex` value.

### 5b. Remove AI tags from chips with confirm

`app/views/tags/_tag_chip.html.erb` — always show `×`, gate AI-sourced removals behind `data-turbo-confirm`:

```erb
<%= link_to root_path(tag: tagging.tag.name),
      id: dom_id(tagging),
      class: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs border-3 border-charcoal bg-athens-400 hover:bg-athens-300 #{'ring-2 ring-carrot-400' if @tag == tagging.tag.name}" do %>
  <span class="w-2 h-2 rounded-full dot-<%= tagging.source %>"></span>
  <span class="text-charcoal"><%= tagging.tag.name %></span>
  <%= button_to tagging_path(tagging), method: :delete,
        form: { data: { turbo_stream: true, turbo_confirm: (tagging.source == "user" ? nil : "Remove AI-assigned tag \"#{tagging.tag.name}\"?") } },
        class: "ml-1 text-charcoal-300 hover:text-cerise text-xs leading-none" do %>
    ×
  <% end %>
<% end %>
```

The provenance dot (`.dot-ai_embedding` / `.dot-ai_llm` / `.dot-user`) stays, so the user can see *why* a tag is there and choose to distrust/remove it — satisfying the "distrust by origin" principle without hiding the affordance.

## Section 6 — Overflow menu hover polish

`app/views/items/_actions_menu.html.erb`:

**Trigger button (line 7)** — add background + focus-visible:

```erb
class="text-charcoal-300 hover:text-carrot-500 hover:bg-athens-500 rounded-md bg-transparent border-none cursor-pointer p-1 -mr-1
       focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500 focus-visible:outline-offset-1"
```

**Menu items (lines 20, 27, 33, + new mute item)** — coordinated text+bg hover + focus-visible + leading icon + flex layout:

```erb
class: "flex items-center gap-2 w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer
        focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500"
```

Existing leading icons (`star`, `x`, `tag`) stay; new `speaker-slash` for mute-source.

Container (line 12-17) unchanged — no hover needed, transitions stay.

## Section 7 — Source show page weight display

Stays at `sources/show.html.erb:64-71` (now meaningful, since weight is actually used). Add an **Unmute** action alongside the Reset link when `@follow.muted`:

```erb
<div class="mb-4 flex items-center gap-3 border-3 border-charcoal rounded-md bg-athens-400 p-3">
  <span id="<%= dom_id(@source, :weight) %>" class="text-sm text-charcoal">Weight: <%= @follow.weight %></span>
  <% if @follow.weight != 1.0 %>
    <%= action_link_to "Reset", source_path(@source), method: :patch, params: { reset_weight: true },
      data: { turbo_stream: true },
      class: "text-sm text-charcoal underline hover:no-underline cursor-pointer bg-transparent border-none" %>
  <% end %>
  <% if @follow.muted %>
    <span class="text-sm text-cerise">· muted</span>
    <%= action_link_to "Unmute", unmute_source_path(@source), method: :post,
      data: { turbo_stream: true },
      class: "text-sm text-charcoal underline hover:no-underline cursor-pointer bg-transparent border-none" %>
  <% end %>
</div>
```

## Routes summary

```ruby
# config/routes.rb additions
post "sources/:id/mute",   to: "sources#mute",   as: :mute_source
post "sources/:id/unmute", to: "sources#unmute", as: :unmute_source
```

(`items` and `taggings` resources already present.)

## Migrations

1. `db/migrate/<ts>_create_interactions.rb` — table as above.
2. `db/migrate/<ts>_add_muted_to_follows.rb` — `add_column :follows, :muted, :boolean, default: false, null: false`.

No data migration needed — existing follows default to `muted: false`, `weight: 1.0`.

## Testing

- `Stray::Ranking` — `clamp`, `order_sql` string, `muted_enough?` with various interaction counts within/outside the window, `apply_interaction!` happy path, idempotency (second interaction of same kind doesn't nudge again — verified via `previously_new_record?`).
- `Interaction` model — enum, uniqueness validation.
- `Follow` — `clamp_weight` callback clamps on save (over/under bounds).
- `ItemsController#update` — saves/starred/hides create correct interactions + nudge weight; `unseen` creates no interaction.
- `ItemsController#player` — creates `:opened` interaction, idempotent on repeat opens.
- `SourcesController#mute` / `#unmute` — toggles `follow.muted`, nudges weight on mute.
- `FeedController#index` — ordering by effective_time (assert order with weights 0.5 / 1.0 / 1.5 on same `published_at`); `show_muted` param reveals muted sources' items; default hides them.
- `ranking_explanation_for` helper — offset math, effective_at, muted flag.
- `tags/_tag_chip` — `×` always present; AI-sourced taggings render `data-turbo-confirm`.
- `tag_input_controller` — autocomplete fetch + render + keyboard nav (system test with Capybara).
- System test — hide 3 items from a source in a week → source muted → feed excludes by default → toggle reveals.

## File inventory (new)

- `lib/stray/ranking.rb`
- `app/models/interaction.rb`
- `app/helpers/ranking_helper.rb`
- `app/views/items/_why.html.erb`
- `app/views/shared/_muted_toggle.html.erb`
- `db/migrate/<ts>_create_interactions.rb`
- `db/migrate/<ts>_add_muted_to_follows.rb`

## File inventory (modified)

- `app/controllers/feed_controller.rb` — effective_time ordering, `show_muted` param, `@muted_count`, eager-load follows for `_why`.
- `app/controllers/items_controller.rb` — `#update` writes interactions + nudges; `#player` writes `:opened`.
- `app/controllers/sources_controller.rb` — `#mute`, `#unmute` actions.
- `app/models/follow.rb` — `clamp_weight` callback.
- `app/views/items/_item.html.erb` — render `_why` partial after timestamp row.
- `app/views/items/_player.html.erb` — render `_why` partial.
- `app/views/items/_actions_menu.html.erb` — hover polish + focus-visible + leading icons + new "Mute source" item.
- `app/views/tags/_tag_chip.html.erb` — always show `×`; AI-sourced removals gated by `data-turbo-confirm`.
- `app/views/sources/show.html.erb` — Unmute action when `@follow.muted`.
- `app/views/feed/index.html.erb` — render `shared/_muted_toggle`.
- `app/javascript/controllers/tag_input_controller.js` — working autocomplete (results dropdown, keyboard nav, debounce, create-new option).
- `config/routes.rb` — `mute_source`, `unmute_source`.

## Open decisions deferred

- Distinguishing extractor-origin `:user` tags from manual `:user` tags in provenance labels (v2).
- v2 "similar to saved" embedding-based ranking (separate spec).
- Adaptive `poll_interval` already exists on `Source`; it is unrelated to `Follow.weight` and untouched here.
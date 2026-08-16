# Ranking, Tags & Overflow Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Follow.weight` actually affect feed ordering via an explainable additive time-offset, record the interactions that nudge weight, show "why is this here" per item, wire up tag autocomplete, allow removing AI tags, and polish the overflow menu.

**Architecture:** A new `Stray::Ranking` module holds the math (offset, clamp, mute-check) and the SQL order string. A new `Interaction` model records open/star/hide/mute-source events. `ItemsController` writes interactions synchronously and nudges `Follow.weight`. `FeedController` orders by `effective_time = published_at + (weight-1)*24h` in SQL and excludes muted sources by default. A `<details>` partial on each item card explains the weight factor. Tag autocomplete gets a real results dropdown. AI-sourced tag chips show `×` with a confirm dialog. The actions menu gains hover/focus-visible polish and a new "Mute source" item.

**Tech Stack:** Rails 8, Ruby 4.0.5, SQLite, Minitest, Stimulus, Hotwire/Turbo.

---

### Task 1: Stray::Ranking module

**Files:**
- Create: `lib/stray/ranking.rb`
- Test: `test/lib/stray/ranking_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class Stray::RankingTest < ActiveSupport::TestCase
  test "clamp clamps weight to [0.1, 3.0]" do
    assert_equal 0.1, Stray::Ranking.clamp(0.0)
    assert_equal 3.0, Stray::Ranking.clamp(5.0)
    assert_equal 1.5, Stray::Ranking.clamp(1.5)
  end

  test "order_sql returns effective_time DESC with tiebreaker" do
    sql = Stray::Ranking.order_sql
    assert_includes sql, "datetime(items.published_at, '+' || ((follows.weight - 1.0) * 24) || ' hours') DESC"
    assert_includes sql, "items.published_at DESC"
  end

  test "muted_enough returns true when 3+ hidden interactions in window" do
    user = users(:one)
    source = sources(:youtube)
    3.times do |i|
      item = source.items.create!(
        user: user, external_id: "mute-#{i}", title: "Mute #{i}",
        url: "https://example.com/#{i}", content_text: "x",
        published_at: 1.day.ago, state: 0
      )
      Interaction.create!(user: user, item: item, kind: :hidden)
    end
    assert Stray::Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "muted_enough returns false when fewer than 3 hidden interactions" do
    user = users(:one)
    source = sources(:youtube)
    item = source.items.create!(
      user: user, external_id: "mute-1", title: "Mute 1",
      url: "https://example.com/1", content_text: "x",
      published_at: 1.day.ago, state: 0
    )
    Interaction.create!(user: user, item: item, kind: :hidden)
    assert_not Stray::Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "muted_enough ignores interactions outside the 7-day window" do
    user = users(:one)
    source = sources(:youtube)
    3.times do |i|
      item = source.items.create!(
        user: user, external_id: "old-mute-#{i}", title: "Old Mute #{i}",
        url: "https://example.com/old-#{i}", content_text: "x",
        published_at: 10.days.ago, state: 0
      )
      interaction = Interaction.create!(user: user, item: item, kind: :hidden)
      interaction.update_column(:created_at, 10.days.ago)
    end
    assert_not Stray::Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "apply_interaction nudges weight up for opened" do
    user = users(:one)
    source = sources(:bitchute)
    follow = follows(:two)
    assert_equal 0.5, follow.weight
    item = source.items.create!(
      user: user, external_id: "open-1", title: "Open 1",
      url: "https://example.com/open-1", content_text: "x",
      published_at: 1.hour.ago, state: 0
    )
    Stray::Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    follow.reload
    assert_in_delta 0.55, follow.weight, 0.001
  end

  test "apply_interaction nudges weight down for hidden" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    assert_equal 1.0, follow.weight
    item = source.items.first
    Stray::Ranking.apply_interaction!(user: user, item: item, kind: :hidden)
    follow.reload
    assert_in_delta 0.9, follow.weight, 0.001
  end

  test "apply_interaction is idempotent — second open does not nudge again" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    item = source.items.first
    Stray::Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    first_weight = follow.reload.weight
    Stray::Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    follow.reload
    assert_equal first_weight, follow.weight
  end

  test "apply_interaction with nil kind is a no-op" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    item = source.items.first
    Stray::Ranking.apply_interaction!(user: user, item: item, kind: nil)
    follow.reload
    assert_equal 1.0, follow.weight
  end

  test "apply_interaction sets muted when 3+ hides in window" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    2.times do |i|
      item = source.items.create!(
        user: user, external_id: "m-#{i}", title: "M #{i}",
        url: "https://example.com/m-#{i}", content_text: "x",
        published_at: 1.day.ago, state: 0
      )
      Stray::Ranking.apply_interaction!(user: user, item: item, kind: :hidden)
    end
    follow.reload
    assert_not follow.muted

    third = source.items.create!(
      user: user, external_id: "m-3", title: "M 3",
      url: "https://example.com/m-3", content_text: "x",
      published_at: 1.day.ago, state: 0
    )
    Stray::Ranking.apply_interaction!(user: user, item: third, kind: :hidden)
    follow.reload
    assert follow.muted
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/stray/ranking_test.rb`
Expected: FAIL — `NameError: uninitialized constant Stray::Ranking` (and `Interaction` not defined yet)

- [ ] **Step 3: Create the Interaction model stub (needed by Ranking tests)**

This is a temporary stub — the real migration + model is Task 2. For now create the model file so the test can load:

```bash
bin/rails g model Interaction item:references user:references kind:integer --no-fixture --skip
```

Then edit `db/migrate/<ts>_create_interactions.rb`:

```ruby
class CreateInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :interactions do |t|
      t.references :item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false
      t.datetime :created_at, null: false
      t.index [:item_id, :user_id, :kind], unique: true, name: "index_interactions_on_item_user_kind_unique"
      t.index [:user_id, :created_at]
    end
  end
end
```

Edit `app/models/interaction.rb`:

```ruby
class Interaction < ApplicationRecord
  belongs_to :item
  belongs_to :user
  enum :kind, { opened: 0, starred: 1, hidden: 2, muted_source: 3 }
  validates :kind, uniqueness: { scope: [:item_id, :user_id] }
end
```

Run: `bin/rails db:migrate` and `bin/rails db:test:prepare`

- [ ] **Step 4: Write the Stray::Ranking module**

Create `lib/stray/ranking.rb`:

```ruby
module Stray
  module Ranking
    OPEN_BOOST     = 0.05
    STAR_BOOST     = 0.10
    HIDE_PENALTY   = 0.10
    MUTE_PENALTY   = 0.30
    MUTE_WINDOW    = 7.days
    MUTE_THRESHOLD = 3
    WEIGHT_MIN     = 0.1
    WEIGHT_MAX     = 3.0
    BOOST_HOURS    = 24

    DELTAS = {
      opened:        OPEN_BOOST,
      starred:       STAR_BOOST,
      hidden:       -HIDE_PENALTY,
      muted_source: -MUTE_PENALTY
    }.freeze

    def self.clamp(weight)
      weight.clamp(WEIGHT_MIN, WEIGHT_MAX)
    end

    def self.order_sql
      "datetime(items.published_at, '+' || ((follows.weight - 1.0) * #{BOOST_HOURS}) || ' hours') DESC, items.published_at DESC"
    end

    def self.muted_enough?(user:, source_id:)
      Interaction.joins(:item)
        .where(user_id: user.id, kind: :hidden)
        .where("interactions.created_at >= ?", MUTE_WINDOW.ago)
        .where(items: { source_id: source_id })
        .count >= MUTE_THRESHOLD
    end

    def self.apply_interaction!(user:, item:, kind:)
      return if kind.nil?

      follow = Follow.find_by(user_id: user.id, source_id: item.source_id)
      return unless follow

      created = Interaction.find_or_create_by!(item: item, user: user, kind: kind)
      return unless created.previously_new_record?

      follow.weight = clamp(follow.weight + DELTAS.fetch(kind))
      follow.muted = muted_enough?(user: user, source_id: item.source_id)
      follow.save!
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/lib/stray/ranking_test.rb`
Expected: PASS (all 9 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/stray/ranking.rb test/lib/stray/ranking_test.rb \
  app/models/interaction.rb db/migrate/*_create_interactions.rb
git commit -m "feat: Stray::Ranking module + Interaction model

Additive time-offset ranking math (weight × 24h), clamp to [0.1, 3.0],
muted_enough check (3+ hides in 7d), apply_interaction! with idempotent
nudging via previously_new_record?. Interaction model with kind enum
(opened/starred/hidden/muted_source) and unique index."
```

---

### Task 2: Follow muted column + clamp callback

**Files:**
- Create: `db/migrate/<ts>_add_muted_to_follows.rb`
- Modify: `app/models/follow.rb`
- Test: `test/models/follow_test.rb` (append)

- [ ] **Step 1: Append failing tests to follow_test.rb**

Add to `test/models/follow_test.rb`:

```ruby
  test "default muted is false" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed2", external_id: "UC2")
    follow = Follow.create!(user: users(:one), source:)
    assert_not follow.muted
  end

  test "clamp_weight clamps on save when above max" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed3", external_id: "UC3")
    follow = Follow.create!(user: users(:one), source:, weight: 10.0)
    assert_equal 3.0, follow.weight
  end

  test "clamp_weight clamps on save when below min" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed4", external_id: "UC4")
    follow = Follow.create!(user: users(:one), source:, weight: 0.0)
    assert_equal 0.1, follow.weight
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/follow_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'muted'` (column doesn't exist yet)

- [ ] **Step 3: Generate migration and add column**

```bash
bin/rails g migration AddMutedToFollows muted:boolean
```

Edit the generated migration:

```ruby
class AddMutedToFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :follows, :muted, :boolean, default: false, null: false
  end
end
```

Run: `bin/rails db:migrate` && `bin/rails db:test:prepare`

- [ ] **Step 4: Add clamp_weight callback to Follow**

Replace `app/models/follow.rb`:

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

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/models/follow_test.rb`
Expected: PASS (all 5 tests)

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*_add_muted_to_follows.rb app/models/follow.rb test/models/follow_test.rb
git commit -m "feat: Follow muted column + weight clamp callback

Add boolean 'muted' column (default false). before_save clamps weight
to [0.1, 3.0] via Stray::Ranking.clamp."
```

---

### Task 3: ItemsController#update writes interactions + nudges

**Files:**
- Modify: `app/controllers/items_controller.rb`
- Test: `test/controllers/items_controller_test.rb` (append)

- [ ] **Step 1: Append failing tests**

Add to `test/controllers/items_controller_test.rb`:

```ruby
  test "saving an item creates a starred interaction and nudges weight up" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)
    assert_equal 1.0, follow.weight

    assert_difference -> { Interaction.count }, 1 do
      patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "starred")
    follow.reload
    assert_in_delta 1.1, follow.weight, 0.001
  end

  test "hiding an item creates a hidden interaction and nudges weight down" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)
    assert_equal 1.0, follow.weight

    assert_difference -> { Interaction.count }, 1 do
      patch item_path(item), params: { state: "hidden" }, as: :turbo_stream
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "hidden")
    follow.reload
    assert_in_delta 0.9, follow.weight, 0.001
  end

  test "setting state to unseen creates no interaction" do
    sign_in_as(users(:one))
    item = items(:video_saved)

    assert_no_difference -> { Interaction.count } do
      patch item_path(item), params: { state: "unseen" }, as: :turbo_stream
    end
  end

  test "second save of same item does not nudge weight again" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    first_weight = follow.reload.weight

    patch item_path(item), params: { state: "unseen" }, as: :turbo_stream
    patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    follow.reload
    assert_equal first_weight, follow.weight
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: FAIL — no Interaction created (current `update` only does `item.update!(state: state)`)

- [ ] **Step 3: Modify ItemsController#update**

Replace `app/controllers/items_controller.rb`:

```ruby
class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze
  KIND_MAP = { "saved" => :starred, "hidden" => :hidden }.freeze

  def player
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    Stray::Ranking.apply_interaction!(user: current_user, item: item, kind: :opened)
    render partial: "items/player", locals: { item: }, layout: false
  end

  def update
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    state = params[:state]
    return head :bad_request unless ALLOWED_STATES.include?(state)

    item.update!(state: state)
    Stray::Ranking.apply_interaction!(user: current_user, item: item, kind: KIND_MAP[state])

    respond_to do |format|
      format.turbo_stream { render "items/update", locals: { item:, state: } }
      format.html { redirect_to root_path }
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: PASS (all tests, including existing ones — `KIND_MAP["unseen"]` returns `nil` so `apply_interaction!` no-ops)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/items_controller.rb test/controllers/items_controller_test.rb
git commit -m "feat: ItemsController writes interactions + nudges weight

#update creates starred/hidden interactions via Stray::Ranking
(KIND_MAP). unseen → nil kind → no-op. Idempotent via unique index."
```

---

### Task 4: ItemsController#player writes :opened interaction

**Files:**
- Modify: `test/controllers/items_controller_test.rb` (append) — the controller change is already in Task 3's implementation

- [ ] **Step 1: Append failing test**

Add to `test/controllers/items_controller_test.rb`:

```ruby
  test "opening player creates an opened interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    assert_difference -> { Interaction.count }, 1 do
      get player_item_path(item)
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "opened")
  end

  test "second open of same player does not create a second interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get player_item_path(item)
    assert_difference -> { Interaction.count }, 0 do
      get player_item_path(item)
    end
  end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bin/rails test test/controllers/items_controller_test.rb`
Expected: PASS — the `#player` action already calls `Stray::Ranking.apply_interaction!(kind: :opened)` from Task 3's rewrite. The unique index + `previously_new_record?` ensures idempotency.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/items_controller_test.rb
git commit -m "test: player action records :opened interaction (idempotent)"
```

---

### Task 5: SourcesController mute/unmute + routes

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/sources_controller.rb`
- Test: `test/controllers/sources_controller_test.rb` (append)

- [ ] **Step 1: Append failing tests**

Add to `test/controllers/sources_controller_test.rb`:

```ruby
  test "mute sets follow muted and nudges weight down" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow = follows(:one)
    assert_equal 1.0, follow.weight
    assert_not follow.muted

    assert_difference -> { Interaction.count }, 1 do
      post mute_source_path(source), as: :turbo_stream
    end

    assert_response :success
    follow.reload
    assert follow.muted
    assert_in_delta 0.7, follow.weight, 0.001
  end

  test "unmute clears follow muted" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow = follows(:one)
    follow.update!(muted: true)

    post unmute_source_path(source), as: :turbo_stream

    assert_response :success
    follow.reload
    assert_not follow.muted
  end

  test "mute returns 404 for unfollowed source" do
    sign_in_as(users(:two))
    post mute_source_path(sources(:bitchute)), as: :turbo_stream
    assert_response :not_found
  end

  test "mute requires authentication" do
    post mute_source_path(sources(:youtube))
    assert_redirected_to new_session_path
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: FAIL — `No route matches /sources/:id/mute`

- [ ] **Step 3: Add routes**

In `config/routes.rb`, replace the `resources :sources` block:

```ruby
  resources :sources do
    member do
      post :pull
      post :mute
      post :unmute
    end
  end
```

- [ ] **Step 4: Add mute/unmute actions to SourcesController**

Add to `app/controllers/sources_controller.rb`, after the `pull` method:

```ruby
  def mute
    source = scoped_source
    follow = source.follows.find_by(user_id: current_user.id)
    return head :not_found unless follow

    item = source.items.first
    if item
      Stray::Ranking.apply_interaction!(user: current_user, item: item, kind: :muted_source)
    else
      follow.update!(weight: Stray::Ranking.clamp(follow.weight - Stray::Ranking::MUTE_PENALTY))
    end
    follow.update!(muted: true)

    respond_to do |format|
      format.turbo_stream { render "sources/update_weight", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end

  def unmute
    source = scoped_source
    follow = source.follows.find_by(user_id: current_user.id)
    return head :not_found unless follow

    follow.update!(muted: false)

    respond_to do |format|
      format.turbo_stream { render "sources/update_weight", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/sources_controller.rb test/controllers/sources_controller_test.rb
git commit -m "feat: SourcesController mute/unmute actions

POST /sources/:id/mute sets follow.muted + nudges weight down by
MUTE_PENALTY. POST /sources/:id/unmute clears muted. Reuses the
update_weight turbo stream to refresh the weight display."
```

---

### Task 6: FeedController ranking order + show_muted

**Files:**
- Modify: `app/controllers/feed_controller.rb`
- Test: `test/controllers/feed_controller_test.rb` (append)

- [ ] **Step 1: Append failing tests**

Add to `test/controllers/feed_controller_test.rb`:

```ruby
  test "feed orders by effective_time so a boosted weight surfaces older items" do
    sign_in_as(users(:one))
    # video_one (youtube, weight 1.0) published 2.days.ago
    # video_two (youtube, weight 1.0) published 1.day.ago → normally first
    # Give bitchute weight 2.0 so its 3-day-old Saved Video (state 2=saved, not hidden)
    # effective_time = 3.days.ago + (1.0 * 24h) = 2.days.ago — should tie with video_one
    # Instead set youtube weight to 0.1 so video_two demotes below video_one
    follows(:one).update!(weight: 0.1)
    follows(:two).update!(weight: 2.0, muted: false)

    get root_path

    assert_response :success
    body = response.body
    # Saved Video (bitchute, weight 2.0, 3d ago → effective 1d ago) should appear before
    # Second Video (youtube, weight 0.1, 1d ago → effective 1d - 21.6h = ~22h ago)
    saved_pos = body.index("Saved Video")
    second_pos = body.index("Second Video")
    assert saved_pos < second_pos, "boosted Saved Video should rank above demoted Second Video"
  end

  test "feed excludes items from muted sources by default" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path

    assert_response :success
    assert_not_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "feed includes muted sources when show_muted=1" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path, params: { show_muted: "1" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "feed assigns muted_count" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path

    assert_response :success
    assert_equal 1, assigns(:muted_count)
  end

  test "feed with no muted sources does not show muted toggle" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_not_includes response.body, "muted"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: FAIL — ordering is still `published_at DESC`, muted sources not excluded.

- [ ] **Step 3: Rewrite FeedController#index**

Replace `app/controllers/feed_controller.rb`:

```ruby
class FeedController < ApplicationController
  include Pagy::Method

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
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: PASS — note the existing "shows items from followed sources, reverse chronological" test may need updating since order changed. If it fails, the order assertion there is checking that "Second Video" appears before "First Video" — with equal weights (1.0) the effective_time equals published_at, so the tiebreaker `items.published_at DESC` keeps the same order. It should still pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/feed_controller.rb test/controllers/feed_controller_test.rb
git commit -m "feat: FeedController orders by effective_time + excludes muted

ORDER BY datetime(published_at + (weight-1)*24h) DESC with
published_at tiebreaker. Muted sources excluded unless show_muted=1.
Eager-loads source.follows for the why partial. Assigns muted_count."
```

---

### Task 7: RankingHelper + _why partial

**Files:**
- Create: `app/helpers/ranking_helper.rb`
- Create: `app/views/items/_why.html.erb`
- Test: `test/helpers/ranking_helper_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/helpers/ranking_helper_test.rb`:

```ruby
require "test_helper"

class RankingHelperTest < ActionView::TestCase
  test "ranking_explanation_for returns offset_hours and effective_at" do
    item = items(:video_one)
    follow = follows(:two) # weight 0.5
    exp = ranking_explanation_for(item, follow)
    assert_equal 0.5, exp.weight
    assert_equal -12.0, exp.offset_hours
    assert_equal item.published_at + (-12.hours), exp.effective_at
    assert_not exp.muted
  end

  test "ranking_explanation_for with weight 1.0 gives zero offset" do
    item = items(:video_one)
    follow = follows(:one) # weight 1.0
    exp = ranking_explanation_for(item, follow)
    assert_equal 0.0, exp.offset_hours
  end

  test "ranking_explanation_for reflects muted flag" do
    item = items(:video_one)
    follow = follows(:one)
    follow.update!(muted: true)
    exp = ranking_explanation_for(item, follow.reload)
    assert exp.muted
  end

  test "offset_label returns no adjustment for zero" do
    assert_equal "no weight adjustment", offset_label(0.0)
  end

  test "offset_label returns +N for positive" do
    assert_equal "+12.0h", offset_label(12.0)
  end

  test "offset_label returns -N for negative" do
    assert_equal "−5.0h", offset_label(-5.0)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/helpers/ranking_helper_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'ranking_explanation_for'`

- [ ] **Step 3: Create the helper**

Create `app/helpers/ranking_helper.rb`:

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

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/helpers/ranking_helper_test.rb`
Expected: PASS (6 tests)

- [ ] **Step 5: Create the _why partial**

Create `app/views/items/_why.html.erb`:

```erb
<% follow = item.source.follows.find_by(user_id: current_user.id) if defined?(current_user) && current_user %>
<% if follow %>
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
<% end %>
```

- [ ] **Step 6: Commit**

```bash
git add app/helpers/ranking_helper.rb test/helpers/ranking_helper_test.rb app/views/items/_why.html.erb
git commit -m "feat: RankingHelper + _why partial for explainable ranking

ranking_explanation_for computes offset_hours and effective_at from
item + follow. offset_label formats as +N h / -N h / no adjustment.
_why.html.erb renders a <details> expandable with the weight factor."
```

---

### Task 8: Render _why in item card and player

**Files:**
- Modify: `app/views/items/_item.html.erb`
- Modify: `app/views/items/_player.html.erb`

- [ ] **Step 1: Render _why in item card**

In `app/views/items/_item.html.erb`, after the timestamp div (after line 42, inside the `flex-1 min-w-0 flex flex-col` div), add:

```erb
        <%= render "items/why", item: item %>
```

The insertion point: after the closing `</div>` of the `flex items-center gap-2 mt-1 text-xs text-charcoal-300` block (line 42), before the closing `</div>` of `flex-1 min-w-0 flex flex-col` (line 43).

- [ ] **Step 2: Render _why in player**

In `app/views/items/_player.html.erb`, after the source/timestamp block (after line 41, before the `content_text` block at line 44), add:

```erb
    <%= render "items/why", item: item %>
```

- [ ] **Step 3: Run feed and items tests to verify nothing breaks**

Run: `bin/rails test test/controllers/feed_controller_test.rb test/controllers/items_controller_test.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add app/views/items/_item.html.erb app/views/items/_player.html.erb
git commit -m "feat: render _why partial in item card and player

Shows the explainable ranking <details> after the timestamp row in
both the grid card and the inline player."
```

---

### Task 9: Muted toggle partial in feed

**Files:**
- Create: `app/views/shared/_muted_toggle.html.erb`
- Modify: `app/views/feed/index.html.erb`

- [ ] **Step 1: Create the muted toggle partial**

Create `app/views/shared/_muted_toggle.html.erb`:

```erb
<% if @muted_count&.positive? %>
  <div class="ml-auto text-xs">
    <%= link_to root_path(show_muted: @show_muted ? "0" : "1"),
          class: "inline-flex items-center gap-1 px-2 py-1 rounded-md border-3 border-charcoal #{@show_muted ? 'bg-mint text-charcoal' : 'bg-athens-400 text-charcoal hover:bg-athens-500'}" do %>
      <%= phosphor_icon "speaker-slash", class: "w-3 h-3" %>
      <%= @show_muted ? "Hiding" : "Showing" %> <%= @muted_count %> muted
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 2: Render it in the feed index**

In `app/views/feed/index.html.erb`, after the `content_for :tag_bar` block (after line 13), add a new `content_for`:

```erb
<% content_for :muted_toggle do %>
  <%= render "shared/muted_toggle" %>
<% end %>
```

- [ ] **Step 3: Render the content_for in the layout**

In `app/views/layouts/application.html.erb`, after `<%= yield :tag_bar %>` (line 28), add:

```erb
      <% if content_for?(:muted_toggle) %>
        <div class="container mx-auto px-4 pt-2 max-w-screen-xl">
          <%= yield :muted_toggle %>
        </div>
      <% end %>
```

- [ ] **Step 4: Run feed test to verify the toggle appears when muted**

Run: `bin/rails test test/controllers/feed_controller_test.rb`
Expected: PASS — the "feed with no muted sources does not show muted toggle" test checks `assert_not_includes response.body, "muted"`. The word "muted" appears in the partial only when `@muted_count > 0`. However, the link text says "muted" — when `@muted_count` is zero the partial renders nothing. Check: the existing test `feed with no muted sources does not show muted toggle` asserts `assert_not_includes response.body, "muted"`. Since the partial is conditional, it should pass. If the word "muted" appears elsewhere in the response (e.g. in the `_why` partial when a source is muted), that test uses a fresh state with no muted sources, so it's fine.

- [ ] **Step 5: Commit**

```bash
git add app/views/shared/_muted_toggle.html.erb app/views/feed/index.html.erb app/views/layouts/application.html.erb
git commit -m "feat: muted sources toggle in feed header

Link appears only when muted_count > 0. Toggles show_muted param to
include/exclude muted sources' items from the feed."
```

---

### Task 10: Source show page unmute UI

**Files:**
- Modify: `app/views/sources/show.html.erb`

- [ ] **Step 1: Add unmute UI to the weight bar**

In `app/views/sources/show.html.erb`, replace lines 64-71 (the weight bar div):

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

- [ ] **Step 2: Run source controller tests to verify nothing breaks**

Run: `bin/rails test test/controllers/sources_controller_test.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/sources/show.html.erb
git commit -m "feat: unmute action on source show page

Shows '· muted' label + Unmute link when follow.muted is true,
alongside the existing weight + Reset bar."
```

---

### Task 11: Tag chip — always show × with confirm for AI tags

**Files:**
- Modify: `app/views/tags/_tag_chip.html.erb`
- Test: `test/controllers/taggings_controller_test.rb` (append)

- [ ] **Step 1: Append failing test**

Add to `test/controllers/taggings_controller_test.rb`:

```ruby
  test "tag chip renders × for user-sourced tagging without confirm" do
    sign_in_as(users(:one))
    tagging = taggings(:video_one_ruby) # source: user
    get root_path
    assert_select "button[data-turbo-confirm]", false, "user tags should not have confirm"
  end
```

If the fixture name doesn't exist, check `test/fixtures/taggings.yml` and adjust. The key assertion: AI-sourced tag chips have `data-turbo-confirm`, user-sourced do not.

- [ ] **Step 2: Modify the tag chip partial**

Replace `app/views/tags/_tag_chip.html.erb`:

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

- [ ] **Step 3: Run test to verify it passes**

Run: `bin/rails test test/controllers/taggings_controller_test.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add app/views/tags/_tag_chip.html.erb test/controllers/taggings_controller_test.rb
git commit -m "feat: always show × on tag chips, confirm for AI-sourced

AI-sourced taggings (ai_embedding, ai_llm) now show the remove button
with a data-turbo-confirm dialog. User-sourced tags remove immediately.
Satisfies the 'distrust by origin' principle."
```

---

### Task 12: Actions menu hover polish + mute source item

**Files:**
- Modify: `app/views/items/_actions_menu.html.erb`

- [ ] **Step 1: Replace the actions menu partial**

Replace `app/views/items/_actions_menu.html.erb`:

```erb
<div data-controller="dropdown" class="relative shrink-0">
  <button type="button"
          data-dropdown-target="button"
          data-action="dropdown#toggle click@window->dropdown#hide"
          aria-expanded="false"
          aria-controls="item-actions-<%= item.id %>"
          class="text-charcoal-300 hover:text-carrot-500 hover:bg-athens-500 rounded-md bg-transparent border-none cursor-pointer p-1 -mr-1
                 focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500 focus-visible:outline-offset-1"
          aria-label="Item actions">
    <%= phosphor_icon "dots-three-vertical", class: "w-4 h-4" %>
  </button>

  <div id="item-actions-<%= item.id %>"
       data-dropdown-target="menu"
       class="hidden absolute right-0 mt-1 z-20 w-44 rounded-md border-3 border-charcoal bg-athens-400 p-1 shadow-lg
              transition transform origin-top-right
              data-[transition-enter-from]:opacity-0 data-[transition-enter-to]:opacity-100
              data-[transition-leave-from]:opacity-100 data-[transition-leave-to]:opacity-0">
    <%= action_link_to item_path(item), method: :patch, params: { state: item.saved? ? "unseen" : "saved" },
          data: { turbo_stream: true },
          class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500" do %>
      <%= phosphor_icon "star", style: item.saved? ? :fill : :regular, class: "w-3.5 h-3.5" %>
      <%= item.saved? ? "Unsave" : "Save" %>
    <% end %>

    <%= action_link_to item_path(item), method: :patch, params: { state: "hidden" },
          data: { turbo_stream: true },
          class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500" do %>
      <%= phosphor_icon "x", class: "w-3.5 h-3.5" %> Hide
    <% end %>

    <%= action_link_to "#",
          data: { controller: "tag-input", action: "tag-input#toggle click@window->dropdown#hide", tag_input_item_id_value: item.id },
          class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500" do %>
      <%= phosphor_icon "tag", class: "w-3.5 h-3.5" %> Add tag
    <% end %>

    <%= action_link_to mute_source_path(item.source), method: :post,
          data: { turbo_stream: true },
          class: "flex items-center gap-2 block w-full text-left px-2 py-1 text-xs text-charcoal hover:bg-athens-300 hover:text-carrot-600 rounded border-none bg-transparent cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-carrot-500" do %>
      <%= phosphor_icon "speaker-slash", class: "w-3.5 h-3.5" %> Mute source
    <% end %>
  </div>
</div>
```

- [ ] **Step 2: Run items and feed controller tests to verify nothing breaks**

Run: `bin/rails test test/controllers/items_controller_test.rb test/controllers/feed_controller_test.rb test/system/tagging_flow_test.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/views/items/_actions_menu.html.erb
git commit -m "feat: actions menu hover polish + Mute source item

Trigger button gains bg hover + focus-visible outline. Menu items
gain coordinated text+bg hover + focus-visible. New 'Mute source'
action posts to mute_source_path. Leading icons on all items."
```

---

### Task 13: Tag input autocomplete

**Files:**
- Modify: `app/javascript/controllers/tag_input_controller.js`
- Test: `test/system/tagging_flow_test.rb` (append)

- [ ] **Step 1: Append a system test**

Add to `test/system/tagging_flow_test.rb` (check existing structure first, then append):

```ruby
  test "tag autocomplete shows matching tags and creates new tag" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-controller='dropdown'] [data-dropdown-target='button']").click
    click_on "Add tag"

    fill_in "tag name", with: "ru" # should match "ruby" fixture tag

    within "[data-tag-input-target='results']" do
      assert_text "ruby"
      find("li", text: "ruby").click
    end

    assert_selector "[data-tag-input-target='input']", visible: false
  end
```

If Capybara can't find the input by "tag name" placeholder, adjust the `fill_in` to use the CSS selector: `find("input[placeholder='tag name']").fill_in(with: "ru")`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test:system test/system/tagging_flow_test.rb`
Expected: FAIL — no results dropdown rendered

- [ ] **Step 3: Rewrite the tag input controller**

Replace `app/javascript/controllers/tag_input_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { itemId: Number }
  static targets = ["input", "results"]

  connect() {
    this.highlightIndex = -1
    this.debounceTimer = null
  }

  toggle(event) {
    event.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.focus()
      return
    }

    const form = document.createElement("div")
    form.className = "flex flex-col gap-1 mt-1"
    form.innerHTML = `
      <div class="flex gap-1">
        <input type="text" placeholder="tag name"
          data-${this.identifier}-target="input"
          data-action="keydown.esc->${this.identifier}#close keydown.enter->${this.identifier}#submit keydown ArrowDown->${this.identifier}#moveHighlight:prevent keydown ArrowUp->${this.identifier}#moveHighlight:prevent input->${this.identifier}#search"
          class="flex-1 h-8 px-2 text-xs border-3 border-charcoal rounded-md bg-athens-400 text-charcoal focus:outline-none" autocomplete="off">
        <button data-action="${this.identifier}#submit"
          class="h-8 px-3 bg-carrot-500 text-white text-xs rounded-md border-3 border-charcoal">Add</button>
      </div>
      <ul data-${this.identifier}-target="results"
        class="hidden border-3 border-charcoal rounded-md bg-athens-400 text-xs max-h-32 overflow-y-auto"></ul>
    `
    this.element.appendChild(form)
    this.inputTarget.focus()
  }

  search() {
    const query = this.inputTarget.value.trim()
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchResults(query), 150)
  }

  fetchResults(query) {
    if (query.length < 1) {
      this.hideResults()
      return
    }

    fetch(`/tags/search?q=${encodeURIComponent(query)}`)
      .then(response => response.json())
      .then(tags => this.renderResults(tags, query))
  }

  renderResults(tags, query) {
    this.highlightIndex = -1
    this.resultsTarget.innerHTML = ""
    let hasExact = false

    tags.slice(0, 5).forEach((tag, i) => {
      if (tag.name.toLowerCase() === query.toLowerCase()) hasExact = true
      const li = document.createElement("li")
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600"
      li.dataset.action = "click->" + this.identifier + "#select"
      li.dataset.index = i
      li.textContent = tag.name
      this.resultsTarget.appendChild(li)
    })

    if (!hasExact && query.length > 0) {
      const li = document.createElement("li")
      li.className = "px-2 py-1 cursor-pointer hover:bg-athens-300 hover:text-carrot-600 border-t-3 border-charcoal"
      li.dataset.action = this.identifier + "#submit"
      li.dataset.index = tags.length
      li.textContent = `Create "${query}"`
      this.resultsTarget.appendChild(li)
    }

    if (this.resultsTarget.children.length > 0) {
      this.resultsTarget.classList.remove("hidden")
    } else {
      this.hideResults()
    }
  }

  moveHighlight(event) {
    const items = this.resultsTarget.children
    if (items.length === 0) return

    if (event.key === "ArrowDown") {
      this.highlightIndex = Math.min(this.highlightIndex + 1, items.length - 1)
    } else if (event.key === "ArrowUp") {
      this.highlightIndex = Math.max(this.highlightIndex - 1, -1)
    }

    Array.from(items).forEach((li, i) => {
      li.classList.toggle("bg-mint", i === this.highlightIndex)
    })

    if (this.highlightIndex >= 0) {
      items[this.highlightIndex].scrollIntoView({ block: "nearest" })
    }
  }

  select(event) {
    event.preventDefault()
    const li = event.target.closest("li")
    if (!li) return
    this.inputTarget.value = li.textContent
    this.submit(event)
  }

  submit(event) {
    event.preventDefault()
    const name = this.inputTarget.value.trim().toLowerCase()
    if (!name) return

    const formData = new FormData()
    formData.append("tagging[item_id]", this.itemIdValue)
    formData.append("tagging[tag_name]", name)

    fetch("/taggings", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
      body: formData
    }).then(() => this.close())
  }

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("hidden")
      this.resultsTarget.innerHTML = ""
    }
  }

  close(event) {
    event?.preventDefault()
    if (this.hasInputTarget) {
      this.inputTarget.closest("div").parentElement.remove()
    }
  }
}
```

- [ ] **Step 4: Run the system test to verify it passes**

Run: `bin/rails test:system test/system/tagging_flow_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/tag_input_controller.js test/system/tagging_flow_test.rb
git commit -m "feat: tag input autocomplete with results dropdown

Debounced fetch to /tags/search, renders up to 5 matches + a
'Create \"...\"' option when no exact match. Keyboard navigation
(ArrowUp/Down to highlight, Enter to select/submit, Esc to close).
Click a result to fill and submit."
```

---

### Task 14: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: PASS (all unit + integration + system tests)

- [ ] **Step 2: Run RuboCop**

Run: `bin/rubocop`
Expected: PASS (no new offenses in changed files)

- [ ] **Step 3: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: PASS (no new warnings — the Arel.sql in feed_controller is a static string with no user input interpolation)

- [ ] **Step 4: Verify the Arel.sql is safe**

Confirm `Stray::Ranking.order_sql` contains only constant values (`BOOST_HOURS` integer), no user input. The `follows.weight` and `items.published_at` are column references, not interpolated values. Safe.

- [ ] **Step 5: Final commit if any lint fixes were needed**

```bash
git add -A
git commit -m "style: rubocop fixes from ranking/tags/overflow implementation"
```

---

## Self-Review

**Spec coverage:**
- §1 Ranking math → Task 1 (Ranking module) + Task 6 (FeedController order)
- §2 Interaction model + nudge → Task 1 (model + apply_interaction!) + Task 3 (ItemsController) + Task 4 (player) + Task 5 (mute/unmute)
- §3 Feed controller + muted toggle → Task 6 (controller) + Task 9 (toggle UI)
- §4 "Why" UI → Task 7 (helper + partial) + Task 8 (render in views)
- §5a Tag autocomplete → Task 13
- §5b Remove AI tags → Task 11
- §6 Overflow menu polish → Task 12
- §7 Source show unmute → Task 10
- Migrations → Task 1 (interactions) + Task 2 (muted column)
- Routes → Task 5 (mute/unmute)

All sections covered.

**Placeholder scan:** No TBDs, no "implement later", no "similar to Task N". All code blocks contain complete code.

**Type consistency:** `Stray::Ranking.apply_interaction!` signature is consistent across Tasks 1, 3, 4, 5. `Interaction` enum values (`opened`, `starred`, `hidden`, `muted_source`) match in the model, migration, and all controller usages. `follow.muted` boolean used consistently in Follow, FeedController, SourcesController, RankingHelper, and views. `KIND_MAP` in ItemsController returns symbols matching the `DELTAS` hash keys in Ranking.
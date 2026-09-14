# frozen_string_literal: true

class FeedInterleaver
  WINDOW_PER_SOURCE = 30
  RESULT_LIMIT = 300
  MAX_RUN = 2

  Entry = Data.define(:item, :source_id, :source_position)

  def self.call(user:, show_muted: false, include_items: [],
                window_per_source: WINDOW_PER_SOURCE,
                result_limit: RESULT_LIMIT,
                max_run: MAX_RUN)
    new(
      user: user,
      show_muted: show_muted,
      include_items: include_items,
      window_per_source: window_per_source,
      result_limit: result_limit,
      max_run: max_run
    ).entries
  end

  def self.interleave(queues:, weights:, max_run: MAX_RUN, result_limit: RESULT_LIMIT)
    queues = queues.transform_values(&:dup)
    virtual_time = Hash.new(0.0)
    counts = Hash.new(0)
    entries = []
    last = nil
    run = 0

    loop do
      eligible = queues.keys.select { |source_id| queues[source_id].any? }
      break if eligible.empty?

      if run >= max_run && eligible.size > 1
        eligible = eligible.reject { |source_id| source_id == last }
      end

      chosen = eligible.min_by do |source_id|
        head = queues[source_id].first
        [ virtual_time[source_id], -(head.published_at&.to_f || 0.0), source_id ]
      end

      item = queues[chosen].shift
      counts[chosen] += 1
      entries << Entry.new(item: item, source_id: chosen, source_position: counts[chosen])
      virtual_time[chosen] += 1.0 / (weights[chosen] || 1.0)
      run = chosen == last ? run + 1 : 1
      last = chosen

      break if entries.size >= result_limit
    end

    entries
  end

  def initialize(user:, show_muted: false, include_items: [],
                 window_per_source: WINDOW_PER_SOURCE,
                 result_limit: RESULT_LIMIT,
                 max_run: MAX_RUN)
    @user = user
    @show_muted = show_muted
    @include_items = include_items
    @window_per_source = window_per_source
    @result_limit = result_limit
    @max_run = max_run
  end

  def entries
    self.class.interleave(
      queues: queues,
      weights: weights,
      max_run: @max_run,
      result_limit: @result_limit
    )
  end

  private

  attr_reader :user, :show_muted, :include_items, :window_per_source

  def follows
    @follows ||= begin
      relation = user.follows
      relation = relation.where(muted: false) unless show_muted
      relation.to_a
    end
  end

  def source_ids
    @source_ids ||= follows.map(&:source_id)
  end

  def weights
    @weights ||= follows.to_h { |follow| [ follow.source_id, follow.weight.to_f ] }
  end

  def queues
    @queues ||= begin
      grouped = candidate_items.group_by(&:source_id)
      included_items.each do |item|
        (grouped[item.source_id] ||= []) << item
      end

      grouped.transform_values do |items|
        items
          .uniq(&:id)
          .sort_by { |item| [ item.published_at&.to_f || 0.0, item.id ] }
          .reverse
      end
    end
  end

  def candidate_items
    return [] if source_ids.empty?

    ranked_sql = Item
      .where(user_id: user.id, source_id: source_ids, state: Item.states[:unseen])
      .where.not(published_at: nil)
      .select("items.*, ROW_NUMBER() OVER (PARTITION BY items.source_id ORDER BY items.published_at DESC, items.id DESC) AS source_rank")
      .to_sql

    Item
      .from("(#{ranked_sql}) items")
      .where("source_rank <= ?", window_per_source)
      .includes(source: :follows)
      .to_a
  end

  def included_items
    include_items.select do |item|
      next false if item.state == "hidden"
      next false unless source_ids.include?(item.source_id)
      next false if muted_source_ids.include?(item.source_id) && !show_muted

      true
    end
  end

  def muted_source_ids
    @muted_source_ids ||= user.follows.where(muted: true).pluck(:source_id)
  end
end

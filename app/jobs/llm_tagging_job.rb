require "faraday"

class LlmTaggingJob < ApplicationJob
  queue_as :default
  retry_on Faraday::Error, wait: 30.seconds, attempts: 3

  def perform(item_id)
    return if AppConfig.ai_provider[:name] == "NONE"
    return unless Setting.get(:llm_tagging_enabled)

    item = Item.find_by(id: item_id)
    return unless item

    response = call_llm(item)
    tag_names = parse_tags(response)
    tag_names.each { |name| assign_tag(item, name) }
  rescue JSON::ParserError => e
    Rails.logger.warn("[LlmTaggingJob] Failed to parse LLM response for item #{item_id}: #{e.message}")
  end

  private

  def call_llm(item)
    prompt = build_prompt(item)
    response = http_client.post("/v1/chat/completions", {
      model: Setting.get(:llm_tagging_model) || "gpt-4o-mini",
      messages: [ { role: "user", content: prompt } ],
      stream: false
    }.to_json)
    JSON.parse(response.body).dig("choices", 0, "message", "content")
  end

  def build_prompt(item)
    text = (item.content_text || "").truncate(1000)
    "Suggest 1 to 5 short tag names for this content. Return ONLY a JSON array of strings, nothing else.\n\nTitle: #{item.title}\nContent: #{text}"
  end

  def parse_tags(response)
    match = response&.match(/\[.*?\]/m)
    return [] unless match

    tags = JSON.parse(match[0])
    tags.map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq.first(5)
  end

  def assign_tag(item, name)
    tag = Tag.find_or_create_by!(user_id: item.user_id, name: name)
    if tag.embedding.nil?
      EmbeddingJob.perform_later("Tag", tag.id)
    end
    Tagging.find_or_create_by!(item: item, tag: tag, source: :ai_llm)
  end

  def http_client
    Faraday.new(url: AppConfig.ai_provider[:url]) do |conn|
      conn.headers["Authorization"] = "Bearer #{AppConfig.ai_provider[:api_key]}" if AppConfig.ai_provider[:api_key].present?
      conn.headers["Content-Type"] = "application/json"
      conn.adapter :net_http
    end
  end
end

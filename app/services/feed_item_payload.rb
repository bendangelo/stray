module FeedItemPayload
  module_function

  def payload(item)
    {
      external_id: item.external_id,
      title: item.title,
      url: item.url,
      content_text: item.content_text,
      content_html: item.content_html,
      thumbnail_url: item.thumbnail_url,
      published_at: item.published_at&.iso8601,
      duration: item.duration,
      tags: item.tags.pluck(:name)
    }
  end
end

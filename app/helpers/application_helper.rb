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

  def pretty_duration(seconds)
    return "" if seconds.nil? || seconds <= 0

    if seconds >= 3600
      "%d:%02d:%02d" % [ seconds / 3600, (seconds / 60) % 60, seconds % 60 ]
    else
      "%d:%02d" % [ seconds / 60, seconds % 60 ]
    end
  end

  def embed_url(item)
    case item.source.kind
    when "youtube_channel"
      "https://www.youtube.com/embed/#{item.external_id}"
    when "video_channel"
      uri = begin
        URI.parse(item.url)
      rescue URI::InvalidURIError
        nil
      end
      if uri&.host&.include?("bitchute.com")
        "https://www.bitchute.com/embed/#{item.external_id}"
      else
        nil
      end
    else
      nil
    end
  end

  def missing_thumb
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='180' fill='%233E3E3E'%3E%3Crect width='320' height='180'/%3E%3C/svg%3E"
  end

  def video?(item = nil)
    item ||= @item
    return false unless item&.source
    item.source.kind.in?(%w[youtube_channel video_channel])
  end
end

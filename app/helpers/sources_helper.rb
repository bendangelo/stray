module SourcesHelper
  def source_ingest_label(source)
    case source.kind
    when "rss_feed" then "RSS feed"
    when "youtube_channel" then "YouTube RSS feed"
    when "odysee_channel" then "Odysee RSS feed"
    when "rumble_channel", "bitchute_channel", "peertube_channel" then "Channel page (scraped)"
    when "generic_page" then "Page URL"
    when "stray_collection" then "Manifest URL"
    else "Source URL"
    end
  end

  def source_kind_note(source)
    case source.kind
    when "rss_feed" then "Polled via RSS/Atom feed."
    when "youtube_channel", "odysee_channel" then "Polled via a generated RSS feed."
    when "rumble_channel", "bitchute_channel", "peertube_channel" then "Scraped from the channel HTML page — no RSS feed."
    when "generic_page" then "Single page extraction."
    when "stray_collection" then "Stray relay manifest."
    else ""
    end
  end

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

  def source_icon(source, size: "w-8 h-8")
    icon = source_icon_url(source)
    if icon.present?
      image_tag icon, alt: source.name, class: "#{size} rounded border-2 border-charcoal shrink-0 object-contain bg-white p-0.5"
    else
      letter = source.name.to_s.first.upcase
      content_tag :div, letter,
        class: "#{size} rounded border-2 border-charcoal bg-charcoal text-white font-bold text-sm flex items-center justify-center shrink-0"
    end
  end
end

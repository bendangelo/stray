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

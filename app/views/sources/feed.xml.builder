xml.instruct!
xml.rss(version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom") do
  xml.channel do
    xml.title @source.display_name
    xml.link @source.url
    xml.description @source.display_name
    xml.atom(:link, href: request.url, rel: "self", type: "application/rss+xml")

    @items.each do |item|
      xml.item do
        xml.title item.title
        xml.link item.url
        xml.guid item.url
        xml.pubDate item.published_at&.rfc2822
        xml.description item.content_text || item.title
        xml.enclosure(url: item.thumbnail_url, type: "image/jpeg") if item.thumbnail_url
      end
    end
  end
end

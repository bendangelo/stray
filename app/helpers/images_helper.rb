module ImagesHelper
  def fallback_image_tag(src, fallback: missing_thumb, alt: "", **opts)
    klass = opts.delete(:class)

    if src.blank?
      return image_tag(fallback, alt: alt, class: klass, **opts)
    end

    content_tag :span, class: "inline-flex", data: { controller: "image-fallback" } do
      image_tag(src,
        alt: alt,
        class: klass,
        loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError",
          image_fallback_fallback_src_value: fallback
        },
        **opts)
    end
  end

  def source_icon_tag(source, size: "w-8 h-8", **opts)
    klass = opts.delete(:class)
    url = source_icon_url(source)
    letter = source.name.to_s.first.upcase
    letter_classes = "#{size} rounded border-2 border-charcoal bg-charcoal " \
                     "text-white font-bold text-sm flex items-center justify-center shrink-0"

    if url.blank?
      return content_tag(:div, letter, class: "#{letter_classes} #{klass}".strip, **opts)
    end

    content_tag :span, class: "inline-flex #{klass}".strip,
                data: { controller: "image-fallback" } do
      concat(image_tag(url,
        alt: source.name,
        class: "#{size} rounded border-2 border-charcoal shrink-0 object-contain bg-white p-0.5",
        loading: "lazy",
        data: {
          image_fallback_target: "primary",
          action: "error->image-fallback#onError"
        }))
      concat(content_tag(:div, letter,
        class: "hidden #{letter_classes}",
        data: { image_fallback_target: "fallback" }))
    end
  end
end

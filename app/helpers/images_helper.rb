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
end

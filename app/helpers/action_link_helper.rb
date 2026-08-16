module ActionLinkHelper
  def action_link_to(name, url = nil, method: :get, confirm: nil, params: nil, **opts, &block)
    if url.nil?
      url = name
      name = nil
    end
    data = opts.fetch(:data, {}).reverse_merge(
      turbo_method: (method == :get ? nil : method),
      turbo_confirm: confirm
    ).compact
    url = append_query_params(url, params) if params
    if block
      link_to url, **opts.merge(data: data), &block
    else
      link_to name, url, **opts.merge(data: data)
    end
  end

  private

  def append_query_params(url, params)
    uri = URI.parse(url)
    uri.query = [uri.query, params.to_query].compact.reject(&:empty?).join("&")
    uri.to_s
  end
end

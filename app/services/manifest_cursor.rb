require "json"
require "base64"

module ManifestCursor
  CURSOR_HEADER = "sc1"

  module_function

  def decode_offset(cursor)
    return 0 if cursor.blank?
    decoded = Base64.urlsafe_decode64(cursor.to_s)
    payload = JSON.parse(decoded)
    return 0 unless payload["h"] == CURSOR_HEADER
    payload["o"].to_i
  rescue ArgumentError, JSON::ParserError
    0
  end

  def encode_offset(offset)
    Base64.urlsafe_encode64(JSON.generate({ h: CURSOR_HEADER, o: offset }))
  end

  def next_url(base_url:, path:, cursor:)
    return nil if cursor.nil?
    if base_url
      "#{base_url}#{path}?cursor=#{cursor}"
    else
      "#{path}?cursor=#{cursor}"
    end
  end
end

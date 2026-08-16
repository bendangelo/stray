require "ipaddr"
require "uri"

module Stray
  module UrlGuard
    class Blocked < StandardError; end

    PRIVATE_RANGES = [
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10")
    ].freeze

    LOOPBACK_HOSTS = %w[localhost].freeze

    def self.allowed?(url)
      return false if url.blank?
      uri = URI.parse(url.to_s)
      return false unless uri.host
      return false unless uri.scheme.in?(%w[http https])

      host = uri.host.downcase.delete("[]")
      return false if LOOPBACK_HOSTS.include?(host)

      ip = parse_ip(host)
      return false if ip && PRIVATE_RANGES.any? { |range| range.include?(ip) }

      true
    rescue URI::InvalidURIError
      false
    end

    def self.parse_ip(host)
      IPAddr.new(host)
    rescue IPAddr::InvalidAddressError
      nil
    end
    private_class_method :parse_ip
  end
end

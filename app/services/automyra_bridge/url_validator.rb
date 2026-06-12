require 'ipaddr'
require 'resolv'

module AutomyraBridge
  class UrlValidator
    BLOCKED_RANGES = [
      IPAddr.new('0.0.0.0/8'),
      IPAddr.new('127.0.0.0/8'),
      IPAddr.new('10.0.0.0/8'),
      IPAddr.new('100.64.0.0/10'),
      IPAddr.new('172.16.0.0/12'),
      IPAddr.new('192.168.0.0/16'),
      IPAddr.new('169.254.0.0/16'),
      IPAddr.new('192.0.0.0/24'),
      IPAddr.new('192.0.2.0/24'),
      IPAddr.new('198.18.0.0/15'),
      IPAddr.new('198.51.100.0/24'),
      IPAddr.new('203.0.113.0/24'),
      IPAddr.new('224.0.0.0/4'),
      IPAddr.new('240.0.0.0/4'),
      IPAddr.new('::/128'),
      IPAddr.new('::1/128'),
      IPAddr.new('::ffff:0:0/96'),
      IPAddr.new('64:ff9b::/96'),
      IPAddr.new('100::/64'),
      IPAddr.new('2001:db8::/32'),
      IPAddr.new('fc00::/7'),
      IPAddr.new('fe80::/10'),
      IPAddr.new('ff00::/8')
    ].freeze

    attr_reader :error

    def self.safe?(url, settings = Setting.plugin_redmine_automyra_bridge)
      new(url, settings).safe?
    end

    def self.dangerous?(url, settings = Setting.plugin_redmine_automyra_bridge)
      !safe?(url, settings)
    end

    def self.validate!(url, settings = Setting.plugin_redmine_automyra_bridge)
      validator = new(url, settings)
      return URI.parse(url.to_s) if validator.safe?

      raise ArgumentError, "Outbound URL is not permitted: #{validator.error}"
    end

    def self.validate_connected_peer!(http, host = nil, settings = Setting.plugin_redmine_automyra_bridge)
      peer_address = connected_peer_address(http)
      raise ArgumentError, 'Outbound URL is not permitted: connected peer address is unavailable' if peer_address.blank?

      address = IPAddr.new(peer_address)
      return true unless BLOCKED_RANGES.any? { |range| range.include?(address) }
      return true if trusted_internal_host?(host, settings)

      raise ArgumentError, 'Outbound URL is not permitted: connected peer is a blocked address'
    rescue ArgumentError => e
      raise e
    rescue StandardError
      raise ArgumentError, 'Outbound URL is not permitted: connected peer address is unavailable'
    end

    def initialize(url, settings = Setting.plugin_redmine_automyra_bridge)
      @url = url.to_s.strip
      @settings = settings || {}
      @error = nil
    end

    def safe?
      uri = parse_uri
      return false unless uri
      return fail_with('URL must include a hostname') if uri.host.blank?
      return fail_with('URL must use HTTP or HTTPS') unless uri.is_a?(URI::HTTP)

      trusted_internal = self.class.trusted_internal_host?(uri.host, @settings)
      return fail_with('HTTP URLs are disabled') if uri.scheme == 'http' && !allow_http? && !trusted_internal
      return fail_with('hostname is not allowlisted') unless host_allowed?(uri.host)

      addresses = resolved_addresses(uri.host)
      return fail_with('hostname did not resolve') if addresses.empty?
      return fail_with('hostname resolves to a blocked address') if !trusted_internal && addresses.any? { |address| blocked_address?(address) }

      true
    end

    def dangerous?
      !safe?
    end

    private

    def self.connected_peer_address(http)
      socket = http.instance_variable_get(:@socket)
      io = socket&.io
      peer = io&.peeraddr
      peer&.last
    end

    def self.trusted_internal_host?(host, settings)
      return false if host.blank?

      raw = settings['trusted_internal_outbound_hosts'] || settings[:trusted_internal_outbound_hosts]
      raw.to_s.split(/[\s,]+/).map { |entry| entry.strip.downcase }.reject(&:blank?).include?(host.to_s.downcase)
    end

    def parse_uri
      URI.parse(@url)
    rescue URI::InvalidURIError
      fail_with('URL is invalid')
      nil
    end

    def allow_http?
      truthy?(@settings['allow_http_outbound']) || truthy?(@settings[:allow_http_outbound])
    end

    def host_allowed?(host)
      allowed_hosts = allowlist
      return true if allowed_hosts.empty?

      normalized_host = host.to_s.downcase
      allowed_hosts.include?(normalized_host)
    end

    def allowlist
      raw = @settings['allowed_outbound_hosts'] || @settings[:allowed_outbound_hosts]
      raw = @settings['automyra_allowed_hosts'] || @settings[:automyra_allowed_hosts] if raw.blank?
      raw.to_s.split(/[\s,]+/).map { |host| host.strip.downcase }.reject(&:blank?).uniq
    end

    def resolved_addresses(host)
      Resolv.getaddresses(host).map { |address| IPAddr.new(address) }
    rescue Resolv::ResolvError, ArgumentError
      []
    end

    def blocked_address?(address)
      BLOCKED_RANGES.any? { |range| range.include?(address) }
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.downcase)
    end

    def fail_with(message)
      @error = message
      false
    end
  end
end

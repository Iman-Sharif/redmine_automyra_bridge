# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'securerandom'

module AutomyraBridge
  # Best-effort, async outbound fanout to the Hermes Agent webhook server.
  # Wire format (X-Hub-Signature-256, sha256=<hex>) matches Hermes' aiohttp
  # listener at gateway/platforms/webhook.py — see _validate_signature.
  class HermesWebhookNotifier
    USER_AGENT = 'Automyra-Bridge-Hermes-Notifier/1.0'

    def self.deliver(event_type:, payload:, delivery_id: nil)
      new.deliver(event_type: event_type, payload: payload, delivery_id: delivery_id)
    end

    def initialize(settings = Setting.plugin_redmine_automyra_bridge)
      @settings = settings || {}
    end

    def deliver(event_type:, payload:, delivery_id: nil)
      url = webhook_url_for_event_type(event_type)
      return nil if url.blank? || secret.blank?

      uri = safe_uri_or_nil(url)
      return nil unless uri

      delivery = delivery_id.presence || SecureRandom.uuid
      body_bytes = { event_type: event_type, payload: payload }.to_json
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body_bytes)}"

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['X-Hub-Signature-256'] = signature
      request['X-GitHub-Event'] = event_type.to_s
      request['X-GitHub-Delivery'] = delivery
      request['User-Agent'] = USER_AGENT
      request.body = body_bytes

      Net::HTTP.start(uri.hostname, uri.port,
                      use_ssl: uri.scheme == 'https',
                      read_timeout: timeout, open_timeout: timeout) do |http|
        AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, @settings)
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          message = "Hermes webhook returned HTTP #{response.code}: #{response.body.to_s.truncate(500)}"
          Rails.logger.error("[AutomyraBridge::HermesWebhookNotifier] #{message} event=#{event_type} delivery_id=#{delivery}")
          raise message
        end

        Rails.logger.info("[AutomyraBridge::HermesWebhookNotifier] delivered event=#{event_type} delivery_id=#{delivery} status=#{response.code}")
        response
      end
    end

    private

    def webhook_url_for_event_type(event_type)
      case event_type.to_s
      when 'redmica.issue_created'
        @settings['hermes_webhook_url_creation_review'].presence || @settings['hermes_webhook_url'].to_s.strip
      when 'redmica.issue_mention', 'redmica.task_comment_mention'
        @settings['hermes_webhook_url_mentions'].presence || @settings['hermes_webhook_url'].to_s.strip
      when 'redmica.issue_status_changed'
        @settings['hermes_webhook_url_auto_close'].presence || @settings['hermes_webhook_url'].to_s.strip
      else
        @settings['hermes_webhook_url'].to_s.strip
      end
    end

    def secret
      @settings['hermes_webhook_secret'].to_s
    end

    def timeout
      raw = @settings['request_timeout_seconds']
      value = raw.to_i
      value = 15 if value.zero?
      value.clamp(1, 120)
    end

    # Returns the validated URI, or nil if the URL fails SSRF/allowlist checks.
    # Never raises — Hermes fanout is best-effort.
    def safe_uri_or_nil(url)
      AutomyraBridge::UrlValidator.validate!(url.to_s.strip, @settings)
    rescue ArgumentError => e
      Rails.logger.warn("[AutomyraBridge::HermesWebhookNotifier] outbound URL rejected: #{e.message}")
      nil
    end
  end
end

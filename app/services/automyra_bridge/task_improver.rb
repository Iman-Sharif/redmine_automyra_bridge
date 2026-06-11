require 'net/http'
require 'json'
require 'securerandom'

module AutomyraBridge
  class TaskImprover
    Result = Struct.new(:success?, :suggestions, :error, :audit_event, keyword_init: true)

    def initialize(settings = Setting.plugin_redmine_automyra_bridge)
      @settings = settings || {}
    end

    def call(user:, task_params:, project: nil)
      audit_event = create_audit_event(user, task_params, project)
      return unavailable(audit_event) if endpoint.blank?
      return invalid_endpoint(audit_event) unless valid_endpoint?

      response = post_payload(user, task_params, project, audit_event)
      parsed = parse_response(response.body)
      suggestions = normalize_suggestions(parsed)

      audit_event.update!(status: 'succeeded', response_payload: parsed.to_json)
      Result.new(success?: true, suggestions: suggestions, audit_event: audit_event)
    rescue StandardError => e
      audit_event&.update!(status: 'failed', error_message: e.message)
      Result.new(success?: false, suggestions: {}, error: e.message, audit_event: audit_event)
    end

    private

    def create_audit_event(user, task_params, project)
      AutomyraBridgeAuditEvent.create!(
        user: user,
        project: project,
        action: 'task_improve',
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid,
        status: 'pending',
        request_payload: task_params.to_json
      )
    end

    def unavailable(audit_event)
      message = 'Automyra endpoint is not configured.'
      audit_event.update!(status: 'failed', error_message: message)
      Result.new(success?: false, suggestions: {}, error: message, audit_event: audit_event)
    end

    def invalid_endpoint(audit_event)
      message = 'Automyra endpoint must be an HTTP or HTTPS URL.'
      audit_event.update!(status: 'failed', error_message: message)
      Result.new(success?: false, suggestions: {}, error: message, audit_event: audit_event)
    end

    def post_payload(user, task_params, project, audit_event)
      uri = safe_endpoint_uri!
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{token}" if token.present?
      request['X-Correlation-ID'] = audit_event.correlation_id
      request['Idempotency-Key'] = audit_event.idempotency_key
      request.body = payload(user, task_params, project).to_json

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: timeout, open_timeout: timeout) do |http|
          AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, @settings)
        response = http.request(request)
        raise "Automyra returned HTTP #{response.code}: #{response.body.to_s.truncate(500)}" unless response.is_a?(Net::HTTPSuccess)

        response
      end
    end

    def payload(user, task_params, project)
      {
        action: 'task_improve',
        instruction: 'Use the redmica-monitoring skill and Redmine MCP context. Return improved Task Hub fields only.',
        user: { id: user.id, name: user.name },
        project: project ? { id: project.id, name: project.name, identifier: project.identifier } : nil,
        task: task_params.slice(:title, :notes, :tags, :status, :priority, :due_date, :category_id)
      }
    end

    def parse_response(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      raise 'Automyra returned invalid JSON.'
    end

    def normalize_suggestions(parsed)
      source = parsed['task'] || parsed['suggestions'] || parsed
      {
        title: source['title'].to_s.presence,
        notes: source['notes'].to_s.presence || source['body'].to_s.presence,
        tags: normalize_tags(source['tags']).presence,
        category_id: source['category_id'].presence
      }.compact
    end

    def normalize_tags(value)
      Array(value.is_a?(String) ? value.split(',') : value).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq
    end

    def endpoint
      @settings['automyra_endpoint'].to_s.strip
    end

    def valid_endpoint?
      AutomyraBridge::UrlValidator.safe?(endpoint, @settings)
    end

    def safe_endpoint_uri!
      AutomyraBridge::UrlValidator.validate!(endpoint, @settings)
    rescue ArgumentError => e
      raise e.message
    end

    def token
      @settings['automyra_token'].to_s.strip
    end

    def timeout
      @settings['request_timeout_seconds'].to_i.clamp(1, 60)
    end
  end
end

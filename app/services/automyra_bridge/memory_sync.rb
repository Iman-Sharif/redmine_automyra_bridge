require 'net/http'
require 'json'

module AutomyraBridge
  class MemorySync
    def initialize(settings = Setting.plugin_redmine_automyra_bridge)
      @settings = settings || {}
    end

    def sync_event(event)
      return mark(event, 'skipped') unless configured?

      response = endpoint.include?('/v1/chat/completions') ? invoke_chat_store(event) : invoke_tool('memory_store', text: memory_text(event), importance: importance(event), category: category(event))
      details = response.dig('result', 'details') || response.dig(:result, :details) || {}
      event.update!(sync_status: 'synced', sync_error: nil, external_memory_id: details['id'] || details[:id] || response['id'])
    rescue StandardError => e
      mark(event, 'failed', e.message)
    end

    def recall(query, limit: 5)
      return invoke_chat_recall(query, limit: limit) if endpoint.include?('/v1/chat/completions')

      invoke_tool('memory_recall', query: query, limit: limit)
    end

    def configured?
      endpoint.present? && token.present?
    end

    private

    def invoke_tool(tool, args)
      uri = safe_endpoint_uri!
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{token}"
      request.body = { tool: tool, args: args, sessionKey: session_key }.to_json
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 20, open_timeout: 10) do |http|
          AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, @settings)
        http.request(request)
      end
      raise "memory sync returned HTTP #{response.code}: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body.to_s.presence || '{}')
      raise "memory sync tool failed: #{parsed.dig('error', 'message') || parsed['error']}" if parsed['ok'] == false

      parsed
    end

    def invoke_chat_store(event)
      chat_completion([
        { role: 'system', content: 'You are Automyra memory ingestion. Store the supplied Redmica event in the active Lossless/LanceDB memory stack. Return JSON only.' },
        { role: 'user', content: { action: 'memory_store', event_id: event.id, text: memory_text(event), category: category(event), importance: importance(event) }.to_json }
      ])
    end

    def invoke_chat_recall(query, limit: 5)
      chat_completion([
        { role: 'system', content: 'You are Automyra memory recall. Search the active Lossless/LanceDB memory stack. Return JSON only with a results array.' },
        { role: 'user', content: { action: 'memory_recall', query: query, limit: limit }.to_json }
      ])
    end

    def chat_completion(messages)
      uri = safe_endpoint_uri!
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{token}"
      request.body = { model: memory_model, messages: messages, temperature: 0.0, response_format: { type: 'json_object' } }.to_json
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 60, open_timeout: 10) do |http|
          AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, @settings)
        http.request(request)
      end
      raise "memory chat returned HTTP #{response.code}: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body.to_s.presence || '{}')
      content = parsed.dig('choices', 0, 'message', 'content').to_s
      decoded = JSON.parse(content) rescue { 'response' => content }
      decoded['id'] ||= parsed['id']
      decoded
    end

    def memory_text(event)
      payload = event.payload.to_s.presence
      [
        "Redmica Automyra event #{event.id}",
        "container=#{event.container_type}:#{event.container_id}",
        "role=#{event.role}",
        "event_type=#{event.event_type}",
        "correlation_id=#{event.correlation_id}",
        event.content,
        payload
      ].compact.join("\n")
    end

    def category(event)
      event.role == 'user' ? 'preference' : 'decision'
    end

    def importance(event)
      %w[user_mention assistant_reply tool_result].include?(event.event_type) ? 0.85 : 0.65
    end

    def mark(event, status, error = nil)
      attrs = { sync_status: status }
      attrs[:sync_error] = error if error
      event.update!(attrs) if event.has_attribute?(:sync_status)
      event
    end

    def endpoint
      @settings['memory_endpoint'].to_s.strip
    end

    def safe_endpoint_uri!
      AutomyraBridge::UrlValidator.validate!(endpoint, @settings)
    rescue ArgumentError => e
      raise e.message
    end

    def token
      @settings['memory_token'].to_s.strip
    end

    def session_key
      @settings['memory_session_key'].to_s.presence || 'main'
    end

    def memory_model
      @settings['memory_model'].to_s.presence || 'manifest/auto'
    end
  end
end

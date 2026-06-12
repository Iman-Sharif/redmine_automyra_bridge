module AutomyraBridge
  module RunEvents
    extend ActiveSupport::Concern

    private

    def run_event_json(event)
      payload = proposal_event_payload(event) || event.payload
      {
        id: event.id,
        event_type: event.event_type,
        status: event.status,
        message: event.message,
        payload: payload,
        sources: event_sources(event, payload),
        visible_to_user: event.visible_to_user,
        created_at: event.created_at.utc.iso8601(3)
      }
    end

    def event_sources(event, payload)
      parsed = payload.is_a?(Hash) ? payload : JSON.parse(payload.to_s.presence || '{}')
      raw = parsed['sources'] || parsed[:sources] || parsed['sources_used'] || parsed[:sources_used]
      run_id = event.respond_to?(:automyra_bridge_run_id) ? event.automyra_bridge_run_id : event.run&.id
      return raw if raw.is_a?(Array)
      return [] unless raw.is_a?(Hash)

      [
        *Array(raw['tools'] || raw[:tools]).map { |name| { type: 'tool', name: name } },
        ({ type: 'page_context', context: raw['page_context'] || raw[:page_context] } if (raw['page_context'] || raw[:page_context]).present?),
        *Array(raw['memory_events'] || raw[:memory_events]).map { |id| { type: 'memory_event', id: id } },
        *memory_event_sources_for_run(run_id)
      ].compact
    rescue JSON::ParserError
      []
    end

    def memory_event_sources_for_run(run_id)
      return [] unless run_id && defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

      AutomyraBridgeMemoryEvent.where(run_id: run_id).limit(10).map { |memory| { type: 'memory_event', id: memory.id, event_type: memory.event_type } }
    rescue StandardError => e
      Rails.logger.warn("Automyra memory event sources lookup failed for run #{run_id}: #{e.class}: #{e.message}") if defined?(Rails)
      []
    end

    def proposal_event_payload(event)
      return nil unless event.event_type.to_s.start_with?('action_proposal.', 'proposal.')

      payload = event.payload.is_a?(Hash) ? event.payload.deep_dup : JSON.parse(event.payload.to_s.presence || '{}')
      proposal = AutomyraBridgeActionProposal.find_by(id: payload['proposal_id'] || payload[:proposal_id])
      return payload unless proposal

      risk_level = proposal_risk_level(proposal)
      payload.merge(
        proposal_id: proposal.id,
        action_type: proposal.action_type,
        target_type: proposal.target_type,
        target_id: proposal.target_id,
        risk_level: risk_level,
        reason: proposal_approval_reason(risk_level),
        status: proposal.status,
        can_manage: can_manage_proposal?(proposal),
        result: proposal_result_payload(proposal)
      ).compact
    rescue JSON::ParserError
      event.payload
    end

    def proposal_risk_level(proposal)
      AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)&.risk_level.presence || 'write'
    end

    def proposal_approval_reason(risk_level)
      return 'This read-only action is being shown for review before Automyra continues.' if risk_level == 'read'

      'This action can modify Redmica data and requires operator approval.'
    end

    def can_manage_proposal?(proposal)
      User.current&.admin? || User.current&.allowed_to?(:manage_automyra_bridge, proposal.project)
    end

    def proposal_result_payload(proposal)
      JSON.parse(proposal.result_payload.to_s.presence || '{}')
    rescue JSON::ParserError
      proposal.result_payload
    end

    def stream_run_events(run)
      last_event_id = request.headers['Last-Event-ID'].presence || params[:last_event_id].presence
      after_id = last_event_id.to_i
      heartbeat_at = Time.current

      loop do
        events = run_events_scope(run).where('id > ?', after_id).order(:id).limit(100)
        events.each do |event|
          response.stream.write("data: #{run_event_json(event).to_json}\n\n")
          after_id = event.id
        end

        run.reload
        break if run_terminal?(run) && !run_events_scope(run).where('id > ?', after_id).exists?

        if heartbeat_at <= 25.seconds.ago
          response.stream.write(": heartbeat\n\n")
          heartbeat_at = Time.current
        end

        sleep 1
      rescue ActiveRecord::ActiveRecordError => e
        response.stream.write("event: error\n")
        response.stream.write("data: #{{ error: 'Database unavailable', message: e.message }.to_json}\n\n")
        break
      end
    end

    def run_events_scope(run)
      return AutomyraBridgeRunEvent.none unless AutomyraBridge::RunEventRecorder.available?

      events = run.run_events
      events = events.visible unless can_view_private_run_events?(run)
      events
    end

    def run_terminal?(run)
      %w[completed failed cancelled].include?(run.status.to_s)
    end

    def write_sse_error(error)
      Rails.logger.warn("AutomyraBridge SSE stream failed: #{error.class}: #{error.message}") if defined?(Rails)

      response.stream.write("event: error\n")
      response.stream.write("data: #{{ error: 'SSE stream unavailable' }.to_json}\n\n")
    rescue IOError, ActionController::Live::ClientDisconnected
      nil
    end

    def authorized_to_view_run_events?(run)
      return false unless User.current
      return true if run.user_id == User.current.id

      User.current.allowed_to?(:view_automyra_bridge_chat, run.project) ||
        User.current.allowed_to?(:manage_automyra_bridge, run.project)
    end

    def can_view_private_run_events?(run)
      User.current.admin? || run.user_id == User.current.id
    end
  end
end

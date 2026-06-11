require 'securerandom'

module AutomyraBridge
  # Writes append-only rows to the automyra_activity_logs table so every
  # state-changing Automyra action leaves an audit trail. Calls are best-effort
  # and idempotent: duplicate or invalid rows are swallowed so instrumentation
  # never breaks the underlying action.
  class ActivityLogger
    def self.log!(action_type:, source:, summary:, session_id: nil, target_type: nil,
                  target_id: nil, project_id: nil, user_id: nil, details: nil, occurred_at: nil)
      occurred_at ||= Time.current
      idempotency_key = generate_idempotency_key(source, action_type, target_id, occurred_at)

      AutomyraBridgeActivityLog.create!(
        action_type: action_type,
        source: source,
        summary: summary,
        session_id: session_id,
        target_type: target_type,
        target_id: target_id.to_s.presence,
        project_id: project_id,
        user_id: user_id,
        details: details,
        idempotency_key: idempotency_key,
        occurred_at: occurred_at
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[ActivityLogger] Skipped duplicate or invalid: #{e.message}") if defined?(Rails)
      nil
    rescue StandardError => e
      Rails.logger.warn("[ActivityLogger] Unexpected failure: #{e.class}: #{e.message}") if defined?(Rails)
      nil
    end

    def self.generate_idempotency_key(source, action_type, target_id, occurred_at)
      ts = (occurred_at || Time.current).to_i
      "#{source}-#{action_type}-#{target_id || SecureRandom.hex(8)}-#{ts}"
    end
  end
end

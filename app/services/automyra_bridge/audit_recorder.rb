module AutomyraBridge
  class AuditRecorder
    def self.record(action, user, details = {})
      new.record(action, user, details)
    end

    def record(action, user, details = {})
      detail_payload = details.except(:project_id, :correlation_id, :idempotency_key, :status).to_json
      payload_column = AutomyraBridgeAuditEvent.column_names.include?('details') ? :details : :request_payload

      AutomyraBridgeAuditEvent.create!(
        action: action.to_s,
        user: user,
        project_id: details[:project_id],
        correlation_id: details[:correlation_id] || SecureRandom.uuid,
        idempotency_key: details[:idempotency_key] || "audit-#{action}-#{user.id}-#{SecureRandom.uuid}",
        status: details[:status] || 'success',
        payload_column => detail_payload
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.error "[AutomyraBridge] AuditRecorder failed: #{e.message}"
      nil
    end
  end
end

module AutomyraBridge
  class RunEventRecorder
    def self.record(run:, event_type:, status: nil, role: nil, message: nil, payload: nil, visible_to_user: true, created_by: nil, sequence: nil)
      new.record(
        run: run,
        event_type: event_type,
        status: status,
        role: role,
        message: message,
        payload: payload,
        visible_to_user: visible_to_user,
        created_by: created_by,
        sequence: sequence
      )
    end

    def self.available?
      defined?(AutomyraBridgeRunEvent) && AutomyraBridgeRunEvent.table_exists?
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def record(run:, event_type:, status: nil, role: nil, message: nil, payload: nil, visible_to_user: true, created_by: nil, sequence: nil)
      return unless run
      return unless self.class.available?

      sequence ||= next_sequence(run)
      attributes = {
        event_type: event_type.to_s,
        status: status,
        role: role,
        message: message,
        payload: serialize_payload(payload),
        visible_to_user: visible_to_user,
        created_by: created_by,
        created_at: Time.current
      }

      AutomyraBridgeRunEvent.find_or_create_by!(run: run, sequence: sequence) do |event|
        attributes.each do |name, value|
          event.public_send("#{name}=", value)
        end
      end
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error "[AutomyraBridge] RunEventRecorder failed: #{e.message}"
      nil
    end

    private

    def next_sequence(run)
      run.run_events.maximum(:sequence).to_i + 1
    end

    def serialize_payload(payload)
      return if payload.nil?
      return payload if payload.is_a?(String)

      payload.to_json
    end
  end
end

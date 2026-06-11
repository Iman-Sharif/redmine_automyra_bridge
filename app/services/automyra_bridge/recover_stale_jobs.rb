module AutomyraBridge
  class RecoverStaleJobs
    STALE_THRESHOLD_MINUTES = 10

    def self.call
      new.call
    end

    def call
      recovered = 0
      AutomyraBridgeJob.stale_running.find_each do |job|
        mark_failed!(job)
        recovered += 1
      end
      recovered
    end

    private

    def mark_failed!(job)
      processor = AutomyraBridge::JobProcessor.new
      processor.send(:mark_failed!, job)
    rescue StandardError => e
      safe_mark_failed!(job, "Automyra job was interrupted while running. Recovery error: #{e.message}")
    end

    def safe_mark_failed!(job, message)
      job.update_columns(
        status: 'failed',
        error_message: message,
        finished_at: Time.current,
        updated_at: Time.current
      )
      placeholder = AutomyraBridgeChatMessage.where(job_id: job.id, role: 'assistant').order(:id).last
      placeholder&.update_columns(status: 'failed', content: 'Unable to get response. Retry?', updated_at: Time.current)
      placeholder&.chat_thread&.increment_unread!(placeholder.user_id, sender_type: placeholder.role)
    rescue StandardError
      nil
    end
  end
end

module AutomyraBridge
  # Async fanout to the Hermes Agent webhook server. Best-effort — failures are
  # retried with exponential backoff, then swallowed so the primary
  # AutomyraBridgeJob path is never affected.
  class HermesWebhookDeliverJob < ActiveJob::Base
    queue_as :default

    # Retry transient failures with exponential backoff. When all attempts are
    # exhausted the block runs instead of re-raising, so the failure is logged
    # and swallowed — the AutomyraBridge job system handles its own delivery and
    # Hermes fanout is best-effort.
    retry_on StandardError, wait: :exponentially_longer, attempts: 5 do |job, error|
      Rails.logger.error(
        "[AutomyraBridge::HermesWebhookDeliverJob] giving up after retries: " \
        "event=#{job.arguments[0]} delivery_id=#{job.arguments[2]} error=#{error.class}: #{error.message}"
      )
    end

    def perform(event_type, payload, delivery_id = nil)
      AutomyraBridge::HermesWebhookNotifier.deliver(
        event_type: event_type,
        payload: payload,
        delivery_id: delivery_id
      )
    end
  end
end

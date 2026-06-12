module AutomyraBridge
  # Async fanout to the Hermes Agent webhook server. Best-effort — failures are
  # retried with exponential backoff, then swallowed so the primary
  # AutomyraBridgeJob path is never affected.
  class HermesWebhookDeliverJob < ActiveJob::Base
    queue_as :default

    # :polynomially_longer is the Rails 7.2 spelling (the older
    # :exponentially_longer symbol raises at retry time on this version).
    # attempts: 5 bounds the backoff so retries always terminate.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
      Rails.logger.error(
        '[AutomyraBridge::HermesWebhookDeliverJob] giving up after retries: ' \
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

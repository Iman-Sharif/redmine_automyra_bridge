module AutomyraBridge
  # Async fanout to the Hermes Agent webhook server. Best-effort — failures are
  # retried with exponential backoff, then swallowed so the primary
  # AutomyraBridgeJob path is never affected.
  class HermesWebhookDeliverJob < ActiveJob::Base
    queue_as :default

    def perform(event_type, payload, delivery_id = nil)
      AutomyraBridge::HermesWebhookNotifier.deliver(
        event_type: event_type,
        payload: payload,
        delivery_id: delivery_id
      )
    end
  end
end

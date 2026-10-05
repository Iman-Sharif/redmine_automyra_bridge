module AutomyraBridge
  # Async fanout to the Hermes Agent webhook server.
  #
  # A delivery record (AutomyraBridgeWebhookDelivery) is created BEFORE the HTTP
  # POST so that both successful and failed deliveries are tracked in the DB.
  # The RetryChecker periodically inspects pending records, detects Hermes-side
  # success/failure/timeout via bot-authored journals, and re-delivers as needed.
  #
  # Transient HTTP failures (ECONNREFUSED, timeout, 5xx) are retried in-memory by
  # retry_on with polynomial backoff. If all 5 attempts fail, the delivery record
  # remains pending with last_error set — the RetryChecker will pick it up for
  # DB-backed retry, which survives process restarts.
  class HermesWebhookDeliverJob < ActiveJob::Base
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
      event_type = job.arguments[0]
      delivery_id = job.arguments[2]
      Rails.logger.error(
        '[AutomyraBridge::HermesWebhookDeliverJob] giving up after retries: ' \
        "event=#{event_type} delivery_id=#{delivery_id} error=#{error.class}: #{error.message}"
      )
      # Record the error on the delivery record so RetryChecker has context
      if delivery_id.present?
        AutomyraBridgeWebhookDelivery.where(delivery_id: delivery_id).update_all(
          last_error: "#{error.class}: #{error.message}",
          updated_at: Time.current
        )
      end
    end

    def perform(event_type, payload, delivery_id = nil)
      # Create the delivery record BEFORE the HTTP POST so failed deliveries
      # are captured in the DB for RetryChecker monitoring.
      delivery_record = find_or_create_delivery_record(event_type, payload, delivery_id)

      response = AutomyraBridge::HermesWebhookNotifier.deliver(
        event_type: event_type,
        payload: payload,
        delivery_id: delivery_id
      )

      # On immediate HTTP success, clear any previous error. The record stays
      # pending — RetryChecker resolves it when it detects a bot-authored
      # success journal on the target.
      return unless response.is_a?(Net::HTTPSuccess) && delivery_record

      delivery_record.update_columns(last_error: nil, updated_at: Time.current)
    end

    private

    def find_or_create_delivery_record(event_type, payload, delivery_id)
      return nil if delivery_id.blank?

      # Idempotency: return existing record if one already exists
      existing = AutomyraBridgeWebhookDelivery.find_by(delivery_id: delivery_id)
      return existing if existing

      target_type, target_id, project_id, source_journal_id = extract_target(payload)

      settings = Setting.plugin_redmine_automyra_bridge.to_h
      interval_minutes = (settings['hermes_webhook_retry_interval_minutes'] || '30').to_i

      AutomyraBridgeWebhookDelivery.create!(
        event_type: event_type.to_s,
        delivery_id: delivery_id,
        payload: payload.to_json,
        target_type: target_type,
        target_id: target_id,
        project_id: project_id,
        source_journal_id: source_journal_id,
        status: 'pending',
        next_retry_at: Time.current + interval_minutes.minutes
      )
    rescue StandardError => e
      # Delivery record creation is best-effort — don't fail the job
      Rails.logger.warn(
        "[AutomyraBridge::HermesWebhookDeliverJob] failed to create delivery record: #{e.class}: #{e.message}"
      )
      nil
    end

    def extract_target(payload)
      p = payload.is_a?(Hash) ? payload.with_indifferent_access : JSON.parse(payload.to_s.presence || '{}')

      # Issue-related events
      if p['issue_id']
        project_id = Issue.where(id: p['issue_id']).pluck(:project_id).first
        return ['Issue', p['issue_id'], project_id, p['journal_id']]
      end

      # Task Hub events
      if p['task_id']
        project_id = nil
        task = begin
          TaskHub::Task.find_by(id: p['task_id'])
        rescue StandardError
          nil
        end
        project_id = task&.project_id if task
        return ['TaskHub::Task', p['task_id'], project_id, p['comment_id']]
      end

      # Wiki events
      if p['wiki_page_id']
        page = begin
          WikiPage.find_by(id: p['wiki_page_id'])
        rescue StandardError
          nil
        end
        project_id = page&.wiki&.project_id
        return ['WikiPage', p['wiki_page_id'], project_id, nil]
      end

      # FAQ Hub events
      return ['FaqHub::Faq', p['faq_id'], p['project_id'], nil] if p['faq_id']

      # Error Hub events
      return ['ErrorHub::Error', p['error_id'], p['project_id'], nil] if p['error_id']

      # Contacts Hub events
      return ['ContactsHub::Contact', p['contact_id'], p['project_id'], nil] if p['contact_id']

      # Document Hub events
      return ['DocumentHub::Document', p['document_id'], p['project_id'], nil] if p['document_id']

      # Repo Hub events
      return ['RepoHub::Repository', p['repository_id'], p['project_id'], nil] if p['repository_id']

      # Fallback: use project_id only
      [nil, nil, p['project_id'], nil]
    end
  end
end

# frozen_require_literal: true

require 'json'

module AutomyraBridge
  # Periodic checker that examines pending AutomyraBridgeWebhookDelivery records
  # and determines whether Hermes successfully processed the webhook, failed with
  # a fallback response, or timed out with no response at all.
  #
  # Detection logic per delivery:
  #   1. Find bot-authored journals on the target after delivery.created_at
  #   2. If a journal has STATUS_MARKER + failure text → failure detected → retry
  #   3. If a journal exists by bot user WITHOUT marker → success → mark resolved
  #   4. If no journal at all AND hard timeout exceeded → retry
  #   5. If no journal at all AND timeout not exceeded → skip (still processing)
  #
  # On failure/timeout:
  #   - Replace fallback comment with retry placeholder (direct edit, no archive)
  #   - Re-deliver webhook to Hermes with new delivery_id
  #   - Increment retry_count, set next_retry_at = now + interval
  #   - If retry_count >= max_retries → mark exhausted, post failure comment
  class RetryChecker
    STATUS_MARKER = '<!-- automyra-bridge-status -->'.freeze
    FAILURE_PATTERNS = [
      /Automyra request failed:/i,
      /could not complete/i,
      /API call failed after/i,
      /rate.?limited/i,
      /timeout exceeded/i,
      /upstream idle timeout/i,
      /reviewed the page context and requested additional/i
    ].freeze

    RETRY_PLACEHOLDER = '⏳ Automyra is retrying (attempt %d/%d)...'.freeze
    EXHAUSTED_MESSAGE = lambda do |attempts|
      "#{STATUS_MARKER}\n⚠️ Automyra could not complete this request after #{attempts} attempts (LLM provider rate-limited or timed out). Please try again later or mention @Automyra with more context."
    end

    def self.call
      new.check_all
    end

    def self.check_all
      new.check_all
    end

    def initialize(settings = Setting.plugin_redmine_automyra_bridge)
      @settings = settings.to_h
      @bot_user = AutomyraBridge::BotUser.call(@settings)
      @interval_minutes = (@settings['hermes_webhook_retry_interval_minutes'] || '30').to_i
      @max_retries = (@settings['hermes_webhook_retry_max_retries'] || '3').to_i
      @timeout_minutes = (@settings['hermes_webhook_retry_timeout_minutes'] || '60').to_i
    end

    def check_all
      return 0 unless @bot_user

      checked = 0
      AutomyraBridgeWebhookDelivery.ready_to_check.find_each do |delivery|
        checked += 1
        check_one(delivery)
      rescue StandardError => e
        Rails.logger.error(
          "[AutomyraBridge::RetryChecker] error checking delivery #{delivery.id}: #{e.class}: #{e.message}"
        )
      end
      checked
    end

    private

    def check_one(delivery)
      journals = bot_journals_for(delivery)

      if journals.any?
        handle_journals_exist(delivery, journals)
      else
        handle_no_journals(delivery)
      end
    end

    # --- Detection: journals exist on the target ---

    def handle_journals_exist(delivery, journals)
      failure_journal = journals.find { |j| failure_response?(j) }
      success_journal = journals.find { |j| !failure_response?(j) }

      if failure_journal && !success_journal
        # Only failure journal exists → retry
        handle_failure(delivery, failure_journal)
      elsif success_journal
        # A success journal exists (with or without a failure journal)
        # Success takes priority — Hermes may have posted a fallback then a real response
        delivery.mark_resolved!(success_journal.id, 'bot_user')
        Rails.logger.info(
          "[AutomyraBridge::RetryChecker] delivery #{delivery.delivery_id} resolved " \
          "(journal #{success_journal.id})"
        )
      elsif failure_journal
        handle_failure(delivery, failure_journal)
      end
    end

    # --- Detection: no journals at all ---

    def handle_no_journals(delivery)
      timeout_at = delivery.created_at + @timeout_minutes.minutes

      if Time.current >= timeout_at
        # Hard timeout exceeded → retry
        # But first: do a final check in case Hermes posted while we were checking
        # (already handled by the journals query in check_one — if we're here, no journals)
        handle_timeout(delivery)
      else
        # Still processing — do nothing this cycle
        # Update next_retry_at so it's checked again next cycle
        delivery.update!(next_retry_at: Time.current + 5.minutes)
      end
    end

    # --- Failure handling ---

    def handle_failure(delivery, journal)
      if delivery.retryable?
        replace_fallback_comment(delivery, journal)
        redeliver(delivery)
      else
        mark_exhausted_and_notify(delivery, journal)
      end
    end

    def handle_timeout(delivery)
      Rails.logger.info(
        "[AutomyraBridge::RetryChecker] delivery #{delivery.delivery_id} timed out " \
        "(no bot journal after #{@timeout_minutes} min)"
      )

      if delivery.retryable?
        redeliver(delivery)
      else
        mark_exhausted_and_notify(delivery, nil)
      end
    end

    # --- Re-delivery ---

    def redeliver(delivery)
      new_delivery_id = delivery.next_delivery_id
      payload = delivery.payload_hash

      response = AutomyraBridge::HermesWebhookNotifier.deliver(
        event_type: delivery.event_type,
        payload: payload,
        delivery_id: new_delivery_id
      )

      if response.is_a?(Net::HTTPSuccess)
        delivery.increment_retry!(@interval_minutes)
        Rails.logger.info(
          "[AutomyraBridge::RetryChecker] re-delivered #{delivery.event_type} " \
          "delivery_id=#{new_delivery_id} retry_count=#{delivery.retry_count} status=#{response.code}"
        )
      else
        # Re-delivery failed — keep the delivery pending for next cycle
        delivery.update!(
          next_retry_at: Time.current + @interval_minutes.minutes,
          last_error: "Re-delivery returned #{response&.class || 'nil'}"
        )
        Rails.logger.warn(
          '[AutomyraBridge::RetryChecker] re-delivery failed for ' \
          "delivery #{delivery.delivery_id}: #{delivery.last_error}"
        )
      end
    rescue StandardError => e
      delivery.update!(
        next_retry_at: Time.current + @interval_minutes.minutes,
        last_error: "#{e.class}: #{e.message}"
      )
      Rails.logger.warn(
        '[AutomyraBridge::RetryChecker] re-delivery error for ' \
        "delivery #{delivery.delivery_id}: #{e.class}: #{e.message}"
      )
    end

    # --- Fallback comment replacement ---

    def replace_fallback_comment(delivery, journal)
      return unless delivery.fallback_journal_id.nil? || delivery.fallback_journal_id == journal.id

      attempt_number = delivery.retry_count + 2
      total_attempts = delivery.max_retries + 1
      placeholder = format(RETRY_PLACEHOLDER, attempt_number, total_attempts)

      journal.update_columns(notes: placeholder)
      delivery.update!(fallback_journal_id: journal.id)

      Rails.logger.info(
        '[AutomyraBridge::RetryChecker] replaced fallback comment ' \
        "journal #{journal.id} with retry placeholder (attempt #{attempt_number}/#{total_attempts})"
      )
    end

    # --- Exhaustion handling ---

    def mark_exhausted_and_notify(delivery, fallback_journal)
      delivery.mark_exhausted!(
        fallback_journal ? "Failed after #{delivery.retry_count + 1} attempts" : "Timed out after #{delivery.max_retries + 1} attempts"
      )

      # Replace the fallback comment (if any) with the exhaustion message
      if fallback_journal
        total_attempts = delivery.max_retries + 1
        fallback_journal.update_columns(notes: EXHAUSTED_MESSAGE.call(total_attempts))
      elsif delivery.fallback_journal_id
        # Previous fallback journal from an earlier retry
        j = Journal.find_by(id: delivery.fallback_journal_id)
        if j
          total_attempts = delivery.max_retries + 1
          j.update_columns(notes: EXHAUSTED_MESSAGE.call(total_attempts))
        end
      else
        # No fallback journal exists — post a new comment on the target issue
        post_exhaustion_comment(delivery)
      end

      Rails.logger.info(
        "[AutomyraBridge::RetryChecker] delivery #{delivery.delivery_id} exhausted " \
        "after #{delivery.retry_count + 1} attempts"
      )
    end

    def post_exhaustion_comment(delivery)
      return unless delivery.target_type == 'Issue' && delivery.target_id

      issue = Issue.find_by(id: delivery.target_id)
      return unless issue

      total_attempts = delivery.max_retries + 1
      issue.init_journal(@bot_user, EXHAUSTED_MESSAGE.call(total_attempts))
      issue.save!

      Rails.logger.info(
        "[AutomyraBridge::RetryChecker] posted exhaustion comment on issue ##{issue.id}"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[AutomyraBridge::RetryChecker] failed to post exhaustion comment: #{e.class}: #{e.message}"
      )
    end

    # --- Journal querying ---

    def bot_journals_for(delivery)
      return Journal.none unless @bot_user && delivery.target_type && delivery.target_id

      Journal.where(
        journalized_type: delivery.target_type,
        journalized_id: delivery.target_id,
        user_id: @bot_user.id
      ).where('created_on >= ?', delivery.created_at - 1.minute).order(:created_on)
    end

    # --- Failure detection ---

    def failure_response?(journal)
      notes = journal.notes.to_s
      return false unless notes.include?(STATUS_MARKER)

      FAILURE_PATTERNS.any? { |pattern| notes.match?(pattern) }
    end
  end
end

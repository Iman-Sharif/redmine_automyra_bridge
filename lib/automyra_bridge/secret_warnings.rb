# frozen_string_literal: true

module AutomyraBridge
  # Emits boot-time warnings for insecure secret configuration.
  # Warn-only by design: never raises, never blocks boot.
  module SecretWarnings
    ACTIVITY_LOG_PLACEHOLDER = 'change-me-in-production'

    module_function

    def warn_if_activity_log_secret_insecure
      secret = activity_log_secret
      return unless secret.blank? || secret == ACTIVITY_LOG_PLACEHOLDER

      Rails.logger.warn(
        '[automyra_bridge] activity_log_secret is blank or set to the placeholder ' \
        "'#{ACTIVITY_LOG_PLACEHOLDER}'. POST /automyra/activity_log rejects all requests " \
        'while blank; set a real secret in plugin settings before relying on it in production.'
      )
    rescue StandardError => e
      # Settings may not be loaded yet during early boot; never crash on a warning.
      Rails.logger.debug("[automyra_bridge] secret warning skipped: #{e.class}: #{e.message}") if Rails.logger
      nil
    end

    def activity_log_secret
      settings = Setting.plugin_redmine_automyra_bridge
      (settings || {})['activity_log_secret'].to_s
    end
  end
end

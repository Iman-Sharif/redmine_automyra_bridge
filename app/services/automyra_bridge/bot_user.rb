# frozen_string_literal: true

module AutomyraBridge
  # Centralized bot user lookup. Replaces hardcoded `User.where(login: 'Automyra')`
  # and the scattered `webhook_user` methods. Resolution order:
  #   1. settings['webhook_user_login'] → User.find_by(login:)
  #   2. User.find_by(login: 'Automyra')
  #   3. First active admin user
  class BotUser
    class << self
      def call(settings = Setting.plugin_redmine_automyra_bridge)
        from_setting(settings) || from_default_login || from_fallback_admin
      end

      private

      def from_setting(settings)
        login = settings.to_h['webhook_user_login'].to_s.presence
        return nil unless login

        User.active.find_by(login: login)
      end

      def from_default_login
        User.active.find_by(login: 'Automyra')
      end

      def from_fallback_admin
        User.active.where(admin: true).order(:id).first
      end
    end
  end
end

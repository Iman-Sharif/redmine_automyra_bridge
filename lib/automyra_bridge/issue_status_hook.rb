module AutomyraBridge
  module IssueStatusHook
    def self.install!
      return unless defined?(Journal)
      return if Journal.included_modules.include?(InstanceMethods)

      Journal.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_create :automyra_auto_close_on_status_change
      end

      private

      def automyra_auto_close_on_status_change
        return if Thread.current[:automyra_auto_close_in_progress]
        return unless Setting.plugin_redmine_automyra_bridge['auto_close_enabled'] == '1'

        status_change = details.detect { |d| d.property == 'attr' && d.prop_key == 'status_id' }
        return unless status_change

        new_status = IssueStatus.find_by(id: status_change.value.to_i)
        return unless new_status

        trigger_name = Setting.plugin_redmine_automyra_bridge['auto_close_trigger_status_name'].presence || 'Resolved'
        return unless new_status.name == trigger_name

        return if notes&.include?('<!-- automyra-auto-close-result -->')

        AutomyraBridge::AutoCloseDispatcher.dispatch(self)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::IssueStatusHook] Error: #{e.message}")
      end
    end
  end
end

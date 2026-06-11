module AutomyraBridge
  module JournalHook
    def self.install!
      return unless defined?(Journal)
      return if Journal.included_modules.include?(InstanceMethods)

      Journal.include InstanceMethods
    end

    module InstanceMethods
      extend ActiveSupport::Concern

      included do
        after_create :create_automyra_bridge_job_from_mention
      end

      private

      def create_automyra_bridge_job_from_mention
        AutomyraBridge::JobCreator.create_for_issue_journal(self)
      end
    end
  end
end

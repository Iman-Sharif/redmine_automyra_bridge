module AutomyraBridge
  module Governance
    class Scheduler
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(now: Time.current, project: nil)
        @now = now
        @project = project
      end

      def call
        scope.select { |policy| due?(policy) }
      end

      private

      def scope
        policies = AutomyraBridge::GovernancePolicy.enabled.order(:id)
        policies = policies.where(project_id: @project.id) if @project
        policies
      end

      def due?(policy)
        return false if policy.enabled == false
        return true if policy.last_run_at.blank? || policy.frequency_hours.blank?

        policy.last_run_at <= @now - policy.frequency_hours.to_i.hours
      end
    end
  end
end

module AutomyraBridge
  class GovernanceRunJob < ActiveJob::Base
    queue_as :default

    def perform(policy_id, mode = nil)
      policy = AutomyraBridge::GovernancePolicy.find(policy_id)
      AutomyraBridge::Governance::Runner.call(policy: policy, mode: mode)
    rescue StandardError => e
      run = AutomyraBridge::GovernanceRun.running.where(governance_policy_id: policy_id).order(:id).last
      run&.mark_failed!(error_message: e.message)
      raise e
    end
  end
end

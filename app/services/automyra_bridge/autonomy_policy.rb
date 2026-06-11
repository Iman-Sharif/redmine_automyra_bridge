module AutomyraBridge
  class AutonomyPolicy
    TRUSTED_IMAN_LOGINS = %w[iman.sharif].freeze

    Decision = Struct.new(:outcome, :reason, :skip_authorization, keyword_init: true) do
      def execute?
        outcome == 'execute'
      end
    end

    def self.decide(job:, proposal:, tool: nil, user: nil)
      new(job: job, proposal: proposal, tool: tool, user: user).decide
    end

    def initialize(job:, proposal:, tool: nil, user: nil)
      @job = job
      @proposal = proposal
      @tool = tool || AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)
      @user = user || job.user
      @setting = AutomyraBridgeProjectSetting.for_project(job.project)
    end

    def decide
      return decision('reject', 'Automyra is disabled for this project.') if @setting.disabled?
      return decision('readonly', 'Automyra is read-only for this project.') if @setting.read_only?
      return decision('reject', 'Automyra action is disabled for this project.') unless @setting.action_enabled?(@proposal.action_type)
      return decision('execute', 'Iman unrestricted autonomy policy.', true) if iman?
      if @setting.autonomous?
        return decision('execute', 'Project autonomous mode.', false) if tool_authorized?
        return decision('reject', 'User is not authorized for this tool.')
      end

      decision('confirm', 'Project requires approval.', false)
    end

    private

    def iman?
      TRUSTED_IMAN_LOGINS.include?(@user.login.to_s.downcase)
    end

    def tool_authorized?
      return true if @user.admin?
      return true if @tool.nil?

      @tool.authorized?(@job, @user)
    end

    def decision(outcome, reason, skip_authorization = false)
      Decision.new(outcome: outcome, reason: reason, skip_authorization: skip_authorization)
    end
  end
end

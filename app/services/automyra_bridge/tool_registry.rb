module AutomyraBridge
  class ToolRegistry
    TOOL_CLASSES = [
      Tools::TaskCreateTool,
      Tools::TaskUpdateTool,
      Tools::TaskCancelTool,
      Tools::TaskCompleteTool,
      Tools::TaskReopenTool,
      Tools::TaskAssignTool,
      Tools::TaskSetPriorityTool,
      Tools::TaskSetDueDateTool,
      Tools::TaskAddCommentTool,
      Tools::TaskLinkIssueTool,
      Tools::TaskPromoteTool,
      Tools::TaskHubCountMyOpenTasksTool,
      Tools::TaskHubGetMyOpenTasksTool,
      Tools::TaskHubSearchMyTasksTool,
      Tools::TaskSearchTool,
      Tools::IssueCreateTool,
      Tools::IssueUpdateTool,
      Tools::IssueAssignTool,
      Tools::IssueSetStatusTool,
      Tools::IssueSetPriorityTool,
      Tools::IssueSetDueDateTool,
      Tools::IssueLinkRelatedTool,
      Tools::IssueSearchTool,
      Tools::IssueSummarizeTool,
      Tools::IssueAssignToRequesterTool,
      Tools::IssueAddCommentTool,
      Tools::IssuesGetMyOpenIssuesTool,
      Tools::WikiReadTool,
      Tools::WikiSearchTool,
      Tools::WikiCreatePageTool,
      Tools::WikiUpdatePageTool,
      Tools::WikiCreateDraftTool,
      Tools::WikiSummarizeTool,
      Tools::WikiBacklinksTool,
      Tools::WikiRelatedPagesTool,
      Tools::ContextCurrentObjectTool,
      Tools::ContextCurrentPageTool,
      Tools::ContextCurrentThreadTool,
      Tools::ContextLinkedObjectsTool,
      Tools::ContextProjectSearchTool,
      Tools::ContextMemorySearchTool,
      Tools::ContextExpandTool,
      Tools::ProjectStatusSummaryTool
    ].freeze

    def self.all
      TOOL_CLASSES.map(&:new)
    end

    def self.find(name)
      all.find { |tool| tool.name == name.to_s }
    end

    def self.for_job(job)
      requested = Array(job&.payload&.dig('tools')).map(&:to_s).reject(&:blank?)
      tools = all.select { |tool| tool.available?(job) }
      requested.any? ? tools.select { |tool| requested.include?(tool.name) } : tools
    end

    def self.schemas_for_job(job)
      for_job(job).map(&:schema)
    end

    def self.validate_tool_classes!(logger: defined?(Rails) ? Rails.logger : nil)
      required_constants = %i[NAME DESCRIPTION INPUT_SCHEMA RISK_LEVEL LEGACY_ACTION_TYPE]
      warnings = TOOL_CLASSES.each_with_object([]) do |tool_class, missing|
        missing_constants = required_constants.reject { |constant| tool_class.const_defined?(constant, false) }
        missing << "#{tool_class.name} is missing #{missing_constants.join(', ')}" if missing_constants.any?
      end

      warnings.each { |warning| logger&.warn("AutomyraBridge tool registry validation: #{warning}") }
      warnings
    end

    def self.health_check(user: nil, project: nil)
      actor = user || User.active.where(admin: true).first || User.active.first || User.first
      project ||= Project.first
      job = Struct.new(:project, :project_id, :user, :user_id, :source_type, :source_id, :payload).new(
        project,
        project&.id,
        actor,
        actor&.id,
        'AutomyraBridgeDiagnostics',
        nil,
        {}
      )

      checks = all.select { |tool| tool.risk_level == 'read' }.map do |tool|
        begin
          if actor.nil? || project.nil?
            { name: tool.name, healthy: false, error: 'No user or project available for health check.' }
          elsif !tool.available?(job)
            { name: tool.name, healthy: false, error: 'Tool is unavailable.' }
          elsif !tool.authorized?(job, actor)
            { name: tool.name, healthy: false, error: 'Health check actor is not authorized.' }
          else
            tool.call(job, actor, {})
            { name: tool.name, healthy: true }
          end
        rescue StandardError => e
          { name: tool.name, healthy: false, error: e.message.to_s.truncate(160) }
        end
      end

      { total: checks.length, healthy: checks.count { |check| check[:healthy] }, checks: checks }
    end

    def self.find_by_legacy_action(action_type)
      all.find { |tool| tool.legacy_action_type == action_type.to_s }
    end
  end
end

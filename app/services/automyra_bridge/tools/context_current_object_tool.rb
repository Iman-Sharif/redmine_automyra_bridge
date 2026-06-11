module AutomyraBridge
  module Tools
    class ContextCurrentObjectTool < BaseTool
      NAME = 'context.current_object'.freeze
      LEGACY_ACTION_TYPE = 'context_current_object'.freeze
      DESCRIPTION = 'Read the current task or issue context snapshot.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze

      def required_permission = :use_automyra_bridge

      def call(job, user, _input)
        if job.source_type == 'TaskHub::TaskComment' && defined?(TaskHub::TaskComment)
          task = TaskHub::TaskComment.find(job.source_id).task
          { context: AutomyraBridge::ContextBuilder.for_task(task, user, tier: 1) }
        elsif job.source_type == 'Journal'
          issue = Journal.find(job.source_id).journalized
          { context: AutomyraBridge::ContextBuilder.for_issue(issue, user, tier: 1) }
        else
          { context: {} }
        end
      end
    end
  end
end

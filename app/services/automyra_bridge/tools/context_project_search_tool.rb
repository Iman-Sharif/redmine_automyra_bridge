module AutomyraBridge
  module Tools
    class ContextProjectSearchTool < BaseTool
      NAME = 'context.project_search'.freeze
      LEGACY_ACTION_TYPE = 'context_project_search'.freeze
      DESCRIPTION = 'Search visible tasks, issues, and wiki pages in the current Redmica project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } }, required: ['query'] }.freeze

      def required_permission = :use_automyra_bridge

      def call(job, user, input)
        { result: AutomyraBridge::ContextBuilder.new(user, 3).project_search(job.project, input['query'], limit: [input.fetch('limit', 5).to_i, 20].min) }
      end
    end
  end
end

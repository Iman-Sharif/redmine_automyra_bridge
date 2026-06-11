module AutomyraBridge
  module Tools
    class ContextMemorySearchTool < BaseTool
      NAME = 'context.memory_search'.freeze
      LEGACY_ACTION_TYPE = 'context_memory_search'.freeze
      DESCRIPTION = 'Search local Redmica Automyra memory events for the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } }, required: ['query'] }.freeze

      def call(job, _user, input)
        query = input['query'].to_s.downcase
        limit = [input.fetch('limit', 5).to_i, 20].min
        events = AutomyraBridgeMemoryEvent.where(project_id: job.project_id).order(id: :desc).limit(200).select do |event|
          [event.content, event.event_type].join(' ').downcase.include?(query)
        end.first(limit)
        { events: events.map { |event| { id: event.id, event_type: event.event_type, content: event.content, created_at: event.created_at } } }
      end
    end
  end
end

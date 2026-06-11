module AutomyraBridge
  module Tools
    class ContextLinkedObjectsTool < BaseTool
      NAME = 'context.linked_objects'.freeze
      LEGACY_ACTION_TYPE = 'context_linked_objects'.freeze
      DESCRIPTION = 'Read linked object hints for the current Redmica object.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze

      def call(job, user, _input)
        source = source_task(job) || source_issue(job)
        context = source.is_a?(Issue) ? AutomyraBridge::ContextBuilder.for_issue(source, user, tier: 2) : AutomyraBridge::ContextBuilder.for_task(source, user, tier: 2)
        { linked_objects: context[:linked_objects] || {} }
      end
    end
  end
end

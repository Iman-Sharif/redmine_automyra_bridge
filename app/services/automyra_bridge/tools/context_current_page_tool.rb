module AutomyraBridge
  module Tools
    class ContextCurrentPageTool < BaseTool
      include SemanticReadHelpers

      NAME = 'context.current_page'.freeze
      LEGACY_ACTION_TYPE = 'context_current_page'.freeze
      DESCRIPTION = 'Read the current page context snapshot.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {}, required: [] }.freeze

      def self.execute(user:, args: {}) = new.execute(user: user, args: args)

      def required_permission = :use_automyra_bridge

      def call(job, user, _input)
        return missing_user_error unless valid_user?(user)

        snapshot = job.payload['context_snapshot'] || job.payload.dig('context', 'context_snapshot') || {}
        { count: snapshot.present? ? 1 : 0, context: snapshot }
      end

      private

      def perform(_user, args)
        snapshot = args['context_snapshot'] || args[:context_snapshot] || args['current_page'] || args[:current_page] || {}
        { count: snapshot.present? ? 1 : 0, context: snapshot }
      end
    end
  end
end

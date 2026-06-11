module AutomyraBridge
  module Tools
    class ContextCurrentThreadTool < ContextCurrentObjectTool
      NAME = 'context.current_thread'.freeze
      LEGACY_ACTION_TYPE = 'context_current_thread'.freeze
      DESCRIPTION = 'Read the current Redmica conversation thread.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze
    end
  end
end

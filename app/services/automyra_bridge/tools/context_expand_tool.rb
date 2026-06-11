module AutomyraBridge
  module Tools
    class ContextExpandTool < ContextCurrentObjectTool
      NAME = 'context.expand'.freeze
      LEGACY_ACTION_TYPE = 'context_expand'.freeze
      DESCRIPTION = 'Read expanded current Redmica context.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: {} }.freeze
    end
  end
end

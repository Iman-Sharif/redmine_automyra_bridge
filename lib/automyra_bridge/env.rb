module AutomyraBridge
  # Lightweight wrapper around the `AUTOMYRA_BRIDGE_*` environment flags that
  # gate optional webhook hook behaviour. Centralising the read here keeps the
  # hook files free of scattered `ENV[...] == '1'` checks and gives future
  # tooling a single seam to mock or override feature flags in tests.
  #
  # Convention (matches the existing wiki / issue hook pattern):
  #   - flag is enabled iff its string value equals `'1'`.
  #   - any other value (`'0'`, `''`, `nil`) means disabled.
  #
  # Example:
  #   return unless AutomyraBridge::Env.enabled?('AUTOMYRA_BRIDGE_TASK_REVIEW')
  module Env
    def self.enabled?(flag_name)
      ENV[flag_name].to_s == '1'
    end
  end
end

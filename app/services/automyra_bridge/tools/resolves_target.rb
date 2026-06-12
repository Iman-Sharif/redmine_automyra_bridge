# frozen_string_literal: true

# ResolvesTarget — shared concern for issue/task tool pairs that resolve
# a source object from the job context (assign, set_due_date, set_priority,
# add_comment, update). Create tools are excluded because they build new
# records rather than resolving existing ones.
#
# Including classes set three class_attribute overrides:
#   - target_resolver   — :source_issue or :source_task (symbol, names the BaseTool method)
#   - target_name       — "Issue" or "Task" (used in "X is no longer available." messages)
#   - target_id_key     — :issue_id or :task_id (for result hash keys)
#
# Provides:
#   - available?(job)        — delegates to the named source resolver, returns truthy/falsy
#   - resolve_target!(job)   — calls the resolver, raises standard "X is no longer available." if nil
#
# PINNED DIVERGENCES (from Task 7 characterization) are preserved by keeping
# each tool's `call` method in the tool class, where per-tool output shapes
# and error types are maintained exactly as-is.
module AutomyraBridge
  module Tools
    module ResolvesTarget
      extend ActiveSupport::Concern

      included do
        class_attribute :target_resolver, instance_predicate: false
        class_attribute :target_name, instance_predicate: false
        class_attribute :target_id_key, instance_predicate: false
      end

      def available?(job)
        send(self.class.target_resolver, job).present?
      end

      def resolve_target!(job)
        target = send(self.class.target_resolver, job)
        raise "#{self.class.target_name} is no longer available." unless target

        target
      end
    end
  end
end

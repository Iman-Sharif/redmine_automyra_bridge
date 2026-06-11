module AutomyraBridge
  module Governance
    module Executors
      class TaskTitleExecutor < BaseExecutor
        def call
          task = TaskHub::Task.find_by(id: action.object_id) if defined?(TaskHub::Task)
          return fail_action!('Task is no longer available.') unless task

          ensure_permission!(:manage_task_hub_tasks, task.project)
          ensure_current_value!(task.title)
          rollback = { title: task.title, task_id: task.id }
          task.update!(title: finding.recommended_value)
          apply_success!(rollback)
        rescue StandardError => e
          fail_action!(e.message)
        end
      end
    end
  end
end

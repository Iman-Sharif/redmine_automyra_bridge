module AutomyraBridge
  module Governance
    module Executors
      class TaskRequirementLinkExecutor < BaseExecutor
        def call
          task = TaskHub::Task.find_by(id: action.object_id) if defined?(TaskHub::Task)
          return fail_action!('Task is no longer available.') unless task

          issue = requirement_issue
          return fail_action!('Requirement issue is no longer available.') unless issue

          ensure_permission!(:manage_task_hub_tasks, task.project || issue.project)
          return skip_duplicate! if task.issue_id.to_i == issue.id

          rollback = { existing_relation_ids: [task.issue_id].compact, task_id: task.id }
          task.update!(issue_id: issue.id, project_id: issue.project_id)
          apply_success!(rollback)
        rescue StandardError => e
          fail_action!(e.message)
        end

        private

        def skip_duplicate!
          action.update!(rollback_payload: { existing_relation_ids: [action.object_id] }.to_json)
          ApplyResult.new(status: 'skipped', message: 'Requirement link already exists.', action: action)
        end
      end
    end
  end
end

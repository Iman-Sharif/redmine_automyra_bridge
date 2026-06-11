module AutomyraBridge
  module Governance
    module Collectors
      class TaskCollector < BaseCollector
        CLOSED_STATUSES = %w[done cancelled].freeze

        def self.call(**kwargs)
          new(**kwargs).call
        end

        def call
          return [] unless (project || policy&.global?) && defined?(TaskHub::Task)

          scope = active_project_scope(TaskHub::Task.all, :task_hub_tasks)
          scope = scope.where.not(status: CLOSED_STATUSES) unless include_closed_tasks?
          scope.order(:id).limit(limit * 2).each_with_object([]) do |task, candidates|
            next if excluded?(task.title)

            candidates << candidate(task)
            break candidates if candidates.size >= limit
          end
        end

        private

        def include_closed_tasks?
          config['include_closed_tasks'] == true || %w[1 true yes on].include?(config['include_closed_tasks'].to_s.downcase)
        end

        def candidate(task)
          {
            object_type: 'TaskHub::Task',
            object_id: task.id,
            title: task.title,
            project_id: task.project_id,
            current_value: task.title
          }
        end
      end
    end
  end
end

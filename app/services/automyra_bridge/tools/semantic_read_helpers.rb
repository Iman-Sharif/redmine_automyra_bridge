module AutomyraBridge
  module Tools
    module SemanticReadHelpers
      DEFAULT_LIMIT = 25

      def execute(user:, args: {})
        return missing_user_error unless valid_user?(user)

        perform(user, (args || {}).with_indifferent_access)
      end

      def call(_job, user, input)
        execute(user: user, args: input || {})
      end

      private

      def valid_user?(user)
        user.present? && !user.anonymous?
      end

      def missing_user_error
        { error: 'missing_user', message: 'A signed-in user is required.' }
      end

      def compact_limit(args, default: DEFAULT_LIMIT, max: TaskHub::TaskQuery::BOUND)
        raw = args.respond_to?(:[]) ? args['limit'] || args[:limit] : nil
        value = raw.to_i.positive? ? raw.to_i : default
        [[value, 1].max, max].min
      end

      def task_url(task)
        if task.issue_id.present?
          "/issue_tasks/#{task.id}"
        else
          "/standalone_tasks/#{task.id}"
        end
      end

      def issue_url(issue)
        "/issues/#{issue.id}"
      end

      def compact_task(task)
        {
          id: task.id,
          title: task.title.to_s,
          status: task.status.to_s,
          priority: task_priority(task),
          project_name: task.project&.name,
          due_date: task.due_date&.to_s,
          url: task_url(task)
        }
      end

      def compact_issue(issue)
        {
          id: issue.id,
          subject: issue.subject.to_s,
          status: issue.status&.name,
          priority: issue.priority&.name,
          project_name: issue.project&.name,
          due_date: issue.due_date&.to_s,
          url: issue_url(issue)
        }
      end

      def task_priority(task)
        return task.priority_label.to_s.downcase if task.respond_to?(:priority_label)
        return task.priority.name.to_s.downcase if task.priority.respond_to?(:name)
        return TaskHub::Task::PRIORITIES[task.priority].to_s.downcase if defined?(TaskHub::Task::PRIORITIES)

        task.priority.to_s.presence
      end
    end
  end
end

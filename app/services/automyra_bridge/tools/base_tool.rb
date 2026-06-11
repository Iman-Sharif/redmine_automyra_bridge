module AutomyraBridge
  module Tools
    class BaseTool
      def description
        self.class::DESCRIPTION
      end

      def input_schema
        self.class::INPUT_SCHEMA
      end

      def legacy_action_type
        self.class::LEGACY_ACTION_TYPE
      end

      def name
        self.class::NAME
      end

      def risk_level
        self.class::RISK_LEVEL
      end

      def schema
        function_definition = {
          name: name,
          description: description,
          parameters: input_schema
        }

        {
          type: 'function',
          function: function_definition,
          name: name,
          description: description,
          parameters: input_schema,
          input_schema: input_schema,
          risk_level: risk_level,
          legacy_action_type: legacy_action_type
        }
      end

      def available?(_job)
        true
      end

      def authorized?(job, user)
        user.admin? || user.allowed_to?(required_permission, job.project)
      end

      def required_permission
        raise NotImplementedError
      end

      def call(_job, _user, _input)
        raise NotImplementedError
      end

      def verify!(_result, _input)
        true
      end

      def result_summary(result)
        "Executed #{name}: #{result.inspect}"
      end

      private

      def source_task(job, input = nil)
        explicit_task = task_from_input(job, input)
        return explicit_task if explicit_task
        return unless job.source_type == 'TaskHub::TaskComment'

        TaskHub::TaskComment.find_by(id: job.source_id)&.task
      end

      def task_from_input(job, input)
        return unless defined?(TaskHub::Task)

        task_id = input_task_id(input)
        return if task_id.blank?

        task = TaskHub::Task.visible_to(job.user).find_by(id: task_id)
        return unless task
        return unless job.user.admin? || job.user.allowed_to?(:manage_task_hub_tasks, task.project)

        task
      end

      def input_task_id(input)
        return unless input.respond_to?(:[])

        input['task_id'].presence || input[:task_id].presence || input.dig('target', 'task_id').presence || input.dig(:target, :task_id).presence || input.dig('task', 'id').presence || input.dig(:task, :id).presence
      end

      def source_issue(job)
        return Issue.find_by(id: job.payload['issue_id']) if job.payload['issue_id'].present?
        return unless job.source_type == 'Journal'

        Journal.find_by(id: job.source_id)&.journalized
      end

      def task_attributes(input)
        input.fetch('task', input).slice(*AutomyraBridge::ActionProposalExecutor::ALLOWED_ATTRIBUTES).compact
      end

      def issue_attributes(input)
        input.slice('subject', 'description', 'tracker_id', 'status_id', 'assigned_to_id', 'priority_id', 'due_date').compact
      end

      def project_wiki(job)
        job.project.wiki || job.project.create_wiki
      end

      def wiki_page(job, title)
        requested = title.to_s
        normalized = requested.tr(' ', '_')
        WikiPage.joins(:wiki)
                .where(wikis: { project_id: job.project_id })
                .where('LOWER(wiki_pages.title) IN (?)', [requested.downcase, normalized.downcase])
                .first
      end
    end
  end
end

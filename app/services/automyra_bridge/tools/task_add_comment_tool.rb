module AutomyraBridge
  module Tools
    class TaskAddCommentTool < BaseTool
      include ResolvesTarget

      NAME = 'task.add_comment'.freeze
      LEGACY_ACTION_TYPE = 'add_task_comment'.freeze
      DESCRIPTION = 'Add a comment to the current Task Hub task.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['comment'], properties: { comment: { type: 'object', required: ['body'], properties: { body: { type: 'string' } } } } }.freeze

      self.target_resolver = :source_task
      self.target_name = 'Task'
      self.target_id_key = :task_id

      def required_permission
        :manage_task_hub_tasks
      end

      def call(job, user, input)
        # PINNED DIVERGENCE (Task 7): task.add_comment returns :comment_id (not body String)
        task = resolve_target!(job)
        body = input.dig('comment', 'body').to_s.strip
        raise 'Comment body is blank.' if body.blank?

        comment = task.comments.create!(author: user, body: body)
        { task_id: task.id, comment_id: comment.id }
      end

      def verify!(result, _input)
        raise 'Task comment verification failed.' unless TaskHub::TaskComment.find_by(id: result[:comment_id])
      end
    end
  end
end

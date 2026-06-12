module AutomyraBridge
  module Tools
    class IssueUpdateTool < BaseTool
      include ResolvesTarget

      NAME = 'issue.update'.freeze
      LEGACY_ACTION_TYPE = 'update_issue'.freeze
      DESCRIPTION = 'Update fields on the current issue.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['issue'], properties: { issue: { type: 'object' } } }.freeze

      self.target_resolver = :source_issue
      self.target_name = 'Issue'
      self.target_id_key = :issue_id

      def required_permission
        :edit_issues
      end

      def call(job, _user, input)
        issue = resolve_target!(job)
        attrs = issue_attributes(input['issue'] || input)
        raise 'No issue fields supplied.' if attrs.empty?

        issue.update!(attrs)
        { issue_id: issue.id }
      end

      def verify!(result, input)
        issue = Issue.find_by(id: result[:issue_id])
        raise 'Issue update verification failed.' unless issue

        attrs = issue_attributes(input['issue'] || input)
        attrs.each do |key, value|
          next if value.blank? || !issue.respond_to?(key)
          raise "Issue update verification failed for #{key}." unless issue.public_send(key).to_s == value.to_s
        end
      end
    end
  end
end

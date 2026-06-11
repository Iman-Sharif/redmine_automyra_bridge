module AutomyraBridge
  module Tools
    class IssueSearchTool < BaseTool
      NAME = 'issue.search'.freeze
      LEGACY_ACTION_TYPE = 'search_issues'.freeze
      DESCRIPTION = 'Search visible issues in the current project.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { query: { type: 'string' }, limit: { type: 'integer' } } }.freeze

      def required_permission
        :view_issues
      end

      def call(job, user, input)
        query = input['query'].to_s.strip
        limit = [[input['limit'].to_i, 1].max, 10].min
        issues = Issue.visible(user).where(project_id: job.project_id).order(updated_on: :desc)
        issues = issues.where('LOWER(issues.subject) LIKE :q OR LOWER(issues.description) LIKE :q', q: "%#{query.downcase}%") if query.present?
        { issues: issues.limit(limit).map { |issue| { id: issue.id, subject: issue.subject, status: issue.status&.name } } }
      end
    end
  end
end

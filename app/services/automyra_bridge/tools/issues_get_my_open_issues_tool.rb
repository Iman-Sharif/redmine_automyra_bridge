module AutomyraBridge
  module Tools
    class IssuesGetMyOpenIssuesTool < BaseTool
      include SemanticReadHelpers

      NAME = 'issues.get_my_open_issues'.freeze
      LEGACY_ACTION_TYPE = 'issues_get_my_open_issues'.freeze
      DESCRIPTION = 'List my open assigned issues.'.freeze
      RISK_LEVEL = 'read'.freeze
      INPUT_SCHEMA = { type: 'object', properties: { limit: { type: 'integer' } }, required: [] }.freeze

      def self.execute(user:, args: {}) = new.execute(user: user, args: args)

      def required_permission = :view_issues

      private

      def perform(user, args)
        issues = Issue.visible(user).where(assigned_to_id: user.id).open.order(updated_on: :desc)
        total = issues.count
        issues = issues.limit(compact_limit(args, max: 50))
        { count: total, issues: issues.map { |issue| compact_issue(issue) } }
      end
    end
  end
end

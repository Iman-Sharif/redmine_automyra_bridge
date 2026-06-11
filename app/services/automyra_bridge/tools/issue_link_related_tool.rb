module AutomyraBridge
  module Tools
    class IssueLinkRelatedTool < BaseTool
      NAME = 'issue.link_related'.freeze
      LEGACY_ACTION_TYPE = 'link_related_issue'.freeze
      DESCRIPTION = 'Link the source issue to another issue as related.'.freeze
      RISK_LEVEL = 'write'.freeze
      INPUT_SCHEMA = { type: 'object', required: ['target'], properties: { target: { type: 'object', required: ['related_issue_id'], properties: { related_issue_id: { type: 'integer' } } } } }.freeze

      def required_permission
        :manage_issue_relations
      end

      def call(job, _user, input)
        source = source_issue(job) || raise('Source issue is not available.')
        target = Issue.find_by(id: input.dig('target', 'related_issue_id')) || raise('Related issue is not available.')
        relation = IssueRelation.find_or_create_by!(issue_from: source, issue_to: target, relation_type: IssueRelation::TYPE_RELATES)
        { issue_id: source.id, related_issue_id: target.id, relation_id: relation.id }
      end
    end
  end
end

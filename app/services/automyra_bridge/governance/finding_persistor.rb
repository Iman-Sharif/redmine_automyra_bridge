module AutomyraBridge
  module Governance
    class FindingPersistor
      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(run:, policy: nil, findings:, created_by: nil)
        @run = run
        @policy = policy || run.governance_policy
        @findings = Array(findings)
        @created_by = created_by || run.created_by
      end

      def call
        AutomyraBridge::GovernanceFinding.transaction do
          records = @findings.map { |finding| persist_finding(finding.deep_stringify_keys) }
          @run.update!(findings_count: @run.governance_findings.count)
          records
        end
      end

      private

      def persist_finding(finding)
        record = AutomyraBridge::GovernanceFinding.create!(
          governance_run: @run,
          governance_policy: @policy,
          object_type: finding['object_type'],
          object_id: finding['object_id'],
          finding_type: finding['finding_type'],
          current_value: finding['current_value'],
          recommended_value: finding['recommended_value'],
          confidence: finding['confidence'],
          rationale: finding['rationale'],
          status: 'pending',
          evaluator_error: finding['evaluator_error'],
          created_by: @created_by
        )
        invalid_finding?(finding) ? record.mark_invalid! : record.mark_valid!
        record
      end

      def invalid_finding?(finding)
        finding['valid'] == false || finding['status'].to_s == 'invalid' || finding['evaluator_error'].present?
      end
    end
  end
end

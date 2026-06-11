module AutomyraBridge
  module Governance
    class StructuredResponseValidator
      REQUIRED_FIELDS = %w[object_type object_id finding_type current_value recommended_value confidence rationale].freeze

      Result = Struct.new(:findings, :errors, keyword_init: true) do
        def valid?
          errors.empty?
        end
      end

      def self.call(response)
        new(response).call
      end

      def initialize(response)
        @response = response
        @errors = []
      end

      def call
        raw_findings = extract_findings
        findings = raw_findings.each_with_index.filter_map { |finding, index| validate_finding(finding, index) }
        Result.new(findings: findings, errors: @errors)
      end

      private

      def extract_findings
        return @response if @response.is_a?(Array)
        return @response['findings'] if @response.is_a?(Hash) && @response['findings'].is_a?(Array)

        @errors << 'response must be an array or an object with a findings array'
        []
      end

      def validate_finding(finding, index)
        unless finding.is_a?(Hash)
          @errors << "finding #{index} must be an object"
          return nil
        end

        normalized = finding.deep_stringify_keys
        normalized['finding_type'] = canonical_finding_type(normalized['finding_type'], normalized['object_type'])
        missing = REQUIRED_FIELDS.select { |field| normalized[field].blank? && normalized[field] != false }
        if missing.any?
          @errors << "finding #{index} missing required fields: #{missing.join(', ')}"
          return nil
        end

        unless normalized['object_id'].to_s.match?(/\A\d+\z/)
          @errors << "finding #{index} object_id must be an integer"
          return nil
        end

        begin
          Float(normalized['confidence'])
        rescue ArgumentError, TypeError
          @errors << "finding #{index} confidence must be numeric"
          return nil
        end

        if defined?(AutomyraBridge::GovernanceFinding) && !AutomyraBridge::GovernanceFinding::FINDING_TYPES.include?(normalized['finding_type'].to_s)
          @errors << "finding #{index} finding_type #{normalized['finding_type'].inspect} is not included in the list"
          return nil
        end

        normalized['object_id'] = normalized['object_id'].to_i
        normalized['confidence'] = normalized['confidence'].to_f
        normalized
      end

      def canonical_finding_type(finding_type, object_type = nil)
        value = finding_type.to_s
        return 'task_title' if value.include?('task_title')
        return 'wiki_title' if value.include?('wiki_title')
        return 'attachment_filename' if value.include?('attachment_filename')
        return 'attachment_filename' if value.include?('filename_noncom')
        return 'attachment_filename' if value.include?('filename_format')
        return 'attachment_filename' if value.include?('filename_violation')
        return canonical_requirement_link_finding_type(object_type) if value.include?('requirement_link')

        case value
        when 'summary_required', 'summary_missing', 'missing_summary', 'wiki_summary_required' then 'wiki_summary'
        when 'metadata_required', 'metadata_missing', 'missing_metadata', 'wiki_metadata_required' then 'wiki_metadata'
        when 'heading_structure', 'heading_structure_standard', 'heading_structure_issue', 'wiki_heading_standard' then 'wiki_heading_structure'
        else value
        end
      end

      def canonical_requirement_link_finding_type(object_type)
        case object_type.to_s
        when 'WikiHub::PageSnapshot' then 'wiki_requirement_link'
        when 'TaskHub::Task' then 'task_requirement_link'
        else 'missing_requirement_link'
        end
      end
    end
  end
end

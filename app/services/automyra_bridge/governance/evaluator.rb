require 'digest'
require 'net/http'

module AutomyraBridge
  module Governance
    class Evaluator
      SUPPORTED_ACTION_TYPES = %w[
        update_wiki_title update_task_title update_attachment_filename review_attachment_filename link_wiki_requirement link_task_requirement
        review_wiki_summary review_wiki_metadata review_wiki_heading_structure propose
      ].freeze
      APPROVED_WIKI_DOCUMENT_TYPES = [
        'Architecture', 'Standard', 'Runbook', 'Specification', 'SOP', 'WI', 'GL', 'Template', 'Decision Record', 'Learning Notes'
      ].freeze

      Result = Struct.new(:findings, :metadata, :errors, :notes, keyword_init: true) do
        def valid?
          errors.empty?
        end
      end

      ProviderClient = Struct.new(:settings, keyword_init: true) do
        def call(prompt:, model:, metadata: {})
          config = settings || Setting.plugin_redmine_automyra_bridge || {}
          endpoint = config['automyra_endpoint'].to_s.strip
          raise 'Automyra endpoint is not configured.' if endpoint.blank?

          uri = AutomyraBridge::UrlValidator.validate!(endpoint, config)
          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = 'application/json'
          request['Authorization'] = "Bearer #{config['automyra_token']}" if config['automyra_token'].present?
          request.body = { action: 'governance_evaluate', model: model, prompt: prompt, metadata: metadata }.to_json
          timeout = config['request_timeout_seconds'].to_i.clamp(1, 120)
          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', read_timeout: timeout, open_timeout: timeout) do |http|
            AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, config)
            http.request(request)
          end
          raise "Automyra adapter returned HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

          response.body.to_s
        end
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(policy:, candidate_batch:, provider: nil, config: nil, examples: [])
        @policy = policy
        @candidate_batch = candidate_batch
        @config = (config || PolicyLoader.normalize_policy_config(policy)).deep_stringify_keys
        @provider = provider || ProviderClient.new(settings: Setting.plugin_redmine_automyra_bridge)
        @examples = examples
        @errors = []
        @notes = []
      end

      def call
        prompt = build_prompt
        prompt_hash = Digest::SHA256.hexdigest(prompt)
        response_body = call_provider(prompt, prompt_hash)
        response_hash = Digest::SHA256.hexdigest(response_body.to_s)
        parsed = parse_response(response_body)
        findings = parsed ? validate_response(parsed) : []
        findings = enforce_policy_limits(findings)
        record_duplicate_notes(findings)

        Result.new(
          findings: findings,
          metadata: metadata(prompt_hash, response_hash),
          errors: @errors,
          notes: @notes
        )
      rescue StandardError => e
        @errors << e.message
        Result.new(findings: [], metadata: metadata(nil, nil), errors: @errors, notes: @notes)
      end

      def build_prompt
        JSON.pretty_generate(
          instruction: [
            'Evaluate Redmica governance candidates against the supplied applicable standards wiki page.',
            'Return ONLY JSON findings.',
            'For wiki title checks, read the standards wiki page, each candidate wiki page title and page text.',
            'Decide whether the title is appropriate under the standard.',
            'Recommend a replacement only when the title violates that standard.',
            'For wiki summary checks, read each candidate wiki page title and page text, then recommend a short one-sentence summary of the page content.',
            'For wiki metadata checks, read each candidate wiki page title and page text, then recommend concise metadata for the configured required fields.'
          ].join(' '),
          response_format: [
            'Array of objects with object_type, object_id, finding_type, current_value,',
            'recommended_value, confidence, rationale, optional action_type.'
          ].join(' '),
          policy: {
            name: @policy.name,
            mode: @config['mode'],
            title_rules: @config['title_rules'],
            summary_rules: @config['summary_rules'],
            metadata_rules: @config['metadata_rules'],
            required_fields: @config['required_fields'],
            standard_wiki_page: @config['standard_wiki_page'],
            attachment_filename_rules: @config['attachment_filename_rules'],
            requirement_linking: requirement_linking_policy,
            exclusions: @config['exclusions'],
            confidence_threshold: confidence_threshold,
            max_changes_per_run: max_changes_per_run
          }.compact,
          batch: @candidate_batch.metadata,
          candidates: @candidate_batch.candidates.map { |candidate| prompt_candidate(candidate) },
          requirement_candidates: requirement_candidates.map { |candidate| requirement_summary(candidate) },
          examples: @examples
        )
      end

      private

      def call_provider(prompt, prompt_hash)
        @provider.call(prompt: prompt, model: provider_model, metadata: @candidate_batch.metadata.merge(prompt_hash: prompt_hash))
      end

      def parse_response(response_body)
        unwrap_provider_response(JSON.parse(response_body.to_s))
      rescue JSON::ParserError => e
        @errors << "provider returned malformed JSON: #{e.message}"
        nil
      end

      def unwrap_provider_response(parsed)
        return parsed if parsed.is_a?(Array)
        return parsed if parsed.is_a?(Hash) && parsed['findings'].is_a?(Array)

        wrapped = parsed.is_a?(Hash) && %w[response content answer output text].map { |key| parsed[key] }.find(&:present?)
        return parsed unless wrapped.is_a?(String)

        JSON.parse(clean_wrapped_json(wrapped))
      rescue JSON::ParserError => e
        @errors << "provider returned malformed wrapped JSON: #{e.message}"
        nil
      end

      def clean_wrapped_json(str)
        str = str.sub(/\A[ \t]*`{3}json\s*/i, '')
        str = str.sub(/\s*`{3}\s*\z/, '')
        str.strip
      end

      def validate_response(parsed)
        result = StructuredResponseValidator.call(normalize_findings(parsed).then { |normalized| backfill_finding_current_values(normalized) })
        @errors.concat(result.errors)
        result.findings
      end

      def backfill_finding_current_values(parsed)
        backfill = lambda do |finding|
          normalized = finding.deep_stringify_keys
          candidate = candidate_lookup[[normalized['object_type'], normalized['object_id'].to_i]]
          normalized['current_value'] = candidate_current_value(candidate) if normalized['current_value'].blank? && candidate
          normalized
        end

        if parsed.is_a?(Array)
          parsed.map { |finding| backfill.call(finding) }
        elsif parsed.is_a?(Hash) && parsed['findings'].is_a?(Array)
          parsed.merge('findings' => parsed['findings'].map { |finding| backfill.call(finding) })
        else
          parsed
        end
      end

      def normalize_findings(parsed)
        findings = parsed.is_a?(Array) ? parsed : parsed['findings']
        normalized = Array(findings).map { |finding| normalize_finding(finding) }
        parsed.is_a?(Array) ? normalized : parsed.merge('findings' => normalized)
      end

      def normalize_finding(finding)
        return finding unless finding.respond_to?(:deep_stringify_keys)

        normalized = finding.deep_stringify_keys
        normalized['finding_type'] = canonical_finding_type(normalized['finding_type'], normalized['object_type'])
        if policy_finding_type.present?
          normalized['finding_type'] = policy_finding_type if mismatched_policy_finding_type?(normalized['finding_type'])
          normalized['action_type'] = default_action_type_for(policy_finding_type)
        elsif normalized['action_type'].present?
          normalized['action_type'] = canonical_action_type(normalized['action_type'], normalized['finding_type'])
        end
        normalized
      end

      def policy_finding_type
        @policy_finding_type ||= begin
          policy_name = @policy.name.to_s.downcase
          if policy_name.include?('summary')
            'wiki_summary'
          elsif policy_name.include?('metadata')
            'wiki_metadata'
          elsif policy_name.include?('heading')
            'wiki_heading_structure'
          elsif policy_name.include?('task title')
            'task_title'
          elsif policy_name.include?('wiki title')
            'wiki_title'
          end
        end
      end

      def mismatched_policy_finding_type?(finding_type)
        policy_finding_type.present? && finding_type.to_s != policy_finding_type
      end

      def canonical_finding_type(finding_type, object_type = nil)
        value = finding_type.to_s
        return 'task_title' if value.include?('task_title')
        return 'wiki_title' if value.include?('wiki_title')
        return 'attachment_filename' if value.include?('attachment_filename')
        return 'attachment_filename' if value.include?('filename_noncom')
        return 'attachment_filename' if value.include?('filename_format')
        return canonical_requirement_link_finding_type(object_type) if value.include?('requirement_link')

        case value
        when 'summary_required', 'summary_missing', 'missing_summary', 'wiki_summary_required' then 'wiki_summary'
        when 'metadata_required', 'metadata_missing', 'missing_metadata', 'wiki_metadata_required' then 'wiki_metadata'
        when 'heading_structure', 'heading_structure_standard', 'heading_structure_issue', 'wiki_heading_standard' then 'wiki_heading_structure'
        else inferred_finding_type(value)
        end
      end

      def canonical_requirement_link_finding_type(object_type)
        case object_type.to_s
        when 'WikiHub::PageSnapshot' then 'wiki_requirement_link'
        when 'TaskHub::Task' then 'task_requirement_link'
        else 'missing_requirement_link'
        end
      end

      def inferred_finding_type(value)
        policy_finding_type || value
      end

      def canonical_action_type(action_type, finding_type)
        value = action_type.to_s
        return value if SUPPORTED_ACTION_TYPES.include?(value)
        return 'review_wiki_summary' if %w[review_summary update_wiki_summary propose_wiki_summary].include?(value)
        return 'review_wiki_metadata' if %w[review_metadata update_wiki_metadata propose_wiki_metadata].include?(value)
        return 'review_wiki_heading_structure' if %w[review_heading_structure update_wiki_heading_structure propose_wiki_heading_structure].include?(value)

        default_action_type_for(finding_type) || value
      end

      def enforce_policy_limits(findings)
        valid = findings.filter_map { |finding| enforce_finding(finding) }
        max_changes_per_run ? valid.first(max_changes_per_run) : valid
      end

      def enforce_finding(finding)
        candidate = candidate_lookup[[finding['object_type'], finding['object_id'].to_i]]
        unless candidate
          @errors << "finding references unknown candidate #{finding['object_type']}##{finding['object_id']}"
          return nil
        end

        if finding['confidence'].to_f < confidence_threshold
          @errors << "finding #{finding['object_type']}##{finding['object_id']} confidence below threshold"
          return nil
        end

        finding = normalize_wiki_title_recommendation(finding, candidate)

        if finding['recommended_value'].to_s == candidate_current_value(candidate).to_s
          @errors << "finding #{finding['object_type']}##{finding['object_id']} recommended value is unchanged"
          return nil
        end

        action_type = finding['action_type'].to_s
        if action_type.present? && !SUPPORTED_ACTION_TYPES.include?(action_type)
          @errors << "finding #{finding['object_type']}##{finding['object_id']} action_type is unsupported"
          return nil
        end

        return nil if requirement_link_finding?(finding) && !valid_requirement_link?(finding)

        if finding['finding_type'].to_s == 'wiki_summary' && plain_title_recommendation?(finding, candidate)
          @errors << "finding #{finding['object_type']}##{finding['object_id']} summary recommendation is not a page summary"
          return nil
        end

        finding = normalize_wiki_metadata_recommendation(finding)

        finding.merge('current_value' => candidate_current_value(candidate), 'provider_model_used' => provider_model)
      end

      def normalize_wiki_metadata_recommendation(finding)
        return finding unless finding['finding_type'].to_s == 'wiki_metadata'

        finding.merge('recommended_value' => normalize_metadata_value(finding['recommended_value']))
      end

      def normalize_metadata_value(value)
        parsed = value.is_a?(String) ? parse_metadata_json(value) : value
        return parsed.to_json if parsed.is_a?(Hash) || parsed.is_a?(Array)

        value.to_s
      end

      def parse_metadata_json(value)
        JSON.parse(clean_wrapped_json(value))
      rescue JSON::ParserError
        nil
      end

      def plain_title_recommendation?(finding, candidate)
        normalized_recommendation = finding['recommended_value'].to_s.gsub(/[^a-z0-9]+/i, '').downcase
        normalized_titles = [finding['current_value'], candidate_current_value(candidate)].map do |value|
          value.to_s.gsub(/[^a-z0-9]+/i, '').downcase
        end
        normalized_recommendation.present? && normalized_titles.include?(normalized_recommendation)
      end

      def normalize_wiki_title_recommendation(finding, candidate)
        return finding unless finding['finding_type'].to_s == 'wiki_title'

        canonical = canonical_wiki_title(candidate_current_value(candidate))
        return finding if canonical.blank?

        finding.merge('recommended_value' => canonical)
      end

      def canonical_wiki_title(title)
        parts = wiki_title_parts(title)
        return nil if parts.size < 3

        domain = title_part(parts.first)
        document_type = approved_document_type(parts.second)
        subject = sentence_case_subject(parts.drop(2).join(' '))
        return nil if domain.blank? || document_type.blank? || subject.blank?

        [domain, document_type, subject].join(' - ')
      end

      def wiki_title_parts(title)
        title.to_s
             .gsub(/_+-+_+/, ' - ')
             .split(/\s+-\s+|_/)
             .map(&:squish)
             .reject(&:blank?)
      end

      def title_part(value)
        value.to_s.split.map { |word| word[0].to_s.upcase + word[1..].to_s }.join(' ')
      end

      def approved_document_type(value)
        normalized = title_part(value)
        APPROVED_WIKI_DOCUMENT_TYPES.find { |type| type.casecmp?(normalized) } || normalized
      end

      def sentence_case_subject(value)
        value.to_s.split.map(&:downcase).join(' ')
      end

      def review_action_type_for(finding_type)
        case finding_type.to_s
        when 'wiki_summary' then 'review_wiki_summary'
        when 'wiki_metadata' then 'review_wiki_metadata'
        when 'wiki_heading_structure' then 'review_wiki_heading_structure'
        end
      end

      def default_action_type_for(finding_type)
        case finding_type.to_s
        when 'wiki_title' then 'update_wiki_title'
        when 'task_title' then 'update_task_title'
        when 'attachment_filename' then attachment_filename_action_type
        when 'wiki_requirement_link' then 'link_wiki_requirement'
        when 'task_requirement_link' then 'link_task_requirement'
        else review_action_type_for(finding_type)
        end
      end

      def attachment_filename_action_type
        @config['mode'].to_s == 'apply_after_validation' ? 'update_attachment_filename' : 'review_attachment_filename'
      end

      def valid_requirement_link?(finding)
        requirement = requirement_issue_lookup[recommended_requirement_id(finding).to_i]
        unless requirement
          @errors << "finding #{finding['object_type']}##{finding['object_id']} references unknown requirement #{finding['recommended_value']}"
          return false
        end

        expected_type = effective_action_type(finding) == 'link_wiki_requirement' ? 'WikiHub::PageSnapshot' : 'TaskHub::Task'
        if finding['object_type'].to_s != expected_type
          @errors << "finding #{finding['object_type']}##{finding['object_id']} action_type target is invalid"
          return false
        end

        true
      end

      def recommended_requirement_id(finding)
        finding['recommended_requirement_id'].presence || finding['recommended_value'].to_s[/\d+/]
      end

      def requirement_link_finding?(finding)
        %w[link_wiki_requirement link_task_requirement].include?(effective_action_type(finding)) || %w[wiki_requirement_link task_requirement_link].include?(finding['finding_type'].to_s)
      end

      def effective_action_type(finding)
        finding['action_type'].presence || default_action_type_for(finding['finding_type'])
      end

      def record_duplicate_notes(findings)
        duplicates = findings.group_by { |finding| finding['recommended_value'].to_s }.select { |_value, group| group.size > 1 }
        duplicates.each_key { |value| @notes << "duplicate recommended value allowed: #{value}" }
      end

      def metadata(prompt_hash, response_hash)
        {
          provider_model_used: provider_model,
          prompt_hash: prompt_hash,
          response_hash: response_hash,
          evaluator_error: @errors.join('; ').presence,
          batch_id: @candidate_batch.batch_id
        }
      end

      def candidate_lookup
        @candidate_lookup ||= @candidate_batch.candidates.index_by do |candidate|
          [candidate[:object_type] || candidate['object_type'], (candidate[:object_id] || candidate['object_id']).to_i]
        end
      end

      def candidate_current_value(candidate)
        candidate[:current_value] || candidate['current_value'] || candidate[:title] || candidate['title'] || candidate[:subject] || candidate['subject']
      end

      def prompt_candidate(candidate)
        {
          object_type: candidate[:object_type] || candidate['object_type'],
          object_id: candidate[:object_id] || candidate['object_id'],
          title: candidate[:title] || candidate['title'] || candidate[:subject] || candidate['subject'],
          filename: candidate[:filename] || candidate['filename'],
          container_type: candidate[:container_type] || candidate['container_type'],
          container_id: candidate[:container_id] || candidate['container_id'],
          current_value: candidate_current_value(candidate),
          page_text: prompt_page_text(candidate),
          tracker: candidate[:tracker] || candidate['tracker'],
          status: candidate[:status] || candidate['status']
        }.compact
      end

      def prompt_page_text(candidate)
        text = candidate[:page_text] || candidate['page_text']
        return text unless requirement_link_prompt?

        text.to_s.first(1_500)
      end

      def requirement_candidates
        @requirement_candidates ||= @candidate_batch.candidates.select { |candidate| (candidate[:object_type] || candidate['object_type']).to_s == 'Issue' }
      end

      def requirement_issue_lookup
        @requirement_issue_lookup ||= requirement_candidates.index_by { |candidate| (candidate[:object_id] || candidate['object_id']).to_i }
      end

      def requirement_summary(candidate)
        {
          issue_id: candidate[:object_id] || candidate['object_id'],
          subject: candidate[:subject] || candidate['subject'],
          tracker: candidate[:tracker] || candidate['tracker'],
          status: candidate[:status] || candidate['status'],
          project_id: candidate[:project_id] || candidate['project_id']
        }.compact
      end

      def requirement_linking_policy
        @config.slice('requirement_tracker_ids', 'requirement_tracker_names', 'requirement_status_ids', 'requirement_status_names', 'requirement_custom_field_id', 'requirement_custom_field_name', 'requirement_custom_field_values')
      end

      def requirement_link_prompt?
        truthy?(@config['scope_requirement_links']) || truthy?(@config['scope_wiki_requirement_links']) || truthy?(@config['scope_task_requirement_links'])
      end

      def confidence_threshold
        @config['confidence_threshold'].present? ? @config['confidence_threshold'].to_f : 0.0
      end

      def max_changes_per_run
        value = @config['max_changes_per_run']
        value.present? ? value.to_i : nil
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.downcase)
      end

      def provider_model
        @config['provider_model'].presence || @policy.provider_model.presence || 'manifest/auto'
      end
    end
  end
end

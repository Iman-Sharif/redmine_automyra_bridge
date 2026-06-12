require 'digest'

module AutomyraBridge
  module Governance
    class ReviewStateTracker
      def self.filter_candidates(policy:, config:, candidates:)
        new(policy: policy, config: config).filter_candidates(candidates)
      end

      def self.mark_reviewed!(policy:, config:, run:, candidates:)
        new(policy: policy, config: config, run: run).mark_reviewed!(candidates)
      end

      def initialize(policy:, config:, run: nil)
        @policy = policy
        @config = (config || PolicyLoader.normalize_policy_config(policy)).deep_stringify_keys
        @run = run
      end

      def filter_candidates(candidates)
        Array(candidates).reject { |candidate| unchanged?(candidate) }
      end

      def mark_reviewed!(candidates)
        Array(candidates).each do |candidate|
          AutomyraBridge::GovernanceReviewState.upsert(
            review_state_attributes(candidate),
            unique_by: :idx_automyra_gov_review_states_lookup
          )
        end
      end

      def review_state_attributes(candidate)
        {
          governance_policy_id: @policy.id,
          governance_run_id: @run&.id,
          object_type: candidate[:object_type] || candidate['object_type'],
          object_id: (candidate[:object_id] || candidate['object_id']).to_i,
          review_domain: review_domain(candidate),
          content_fingerprint: fingerprint_for(candidate),
          policy_source_hash: policy_source_hash,
          last_reviewed_at: Time.current,
          updated_at: Time.current,
          created_at: Time.current
        }
      end

      def fingerprint_for(candidate)
        Digest::SHA256.hexdigest(fingerprint_source(candidate).to_json)
      end

      private

      def unchanged?(candidate)
        state = AutomyraBridge::GovernanceReviewState.find_by(
          governance_policy_id: @policy.id,
          object_type: candidate[:object_type] || candidate['object_type'],
          object_id: (candidate[:object_id] || candidate['object_id']).to_i,
          review_domain: review_domain(candidate)
        )
        return false unless state

        state.policy_source_hash == policy_source_hash && state.content_fingerprint == fingerprint_for(candidate)
      end

      def policy_source_hash
        @policy_source_hash ||= PolicySourceSnapshot.hash(policy: @policy, config: @config)
      end

      def review_domain(candidate)
        candidate = candidate.deep_stringify_keys
        object_type = candidate['object_type'].to_s
        policy_name = @policy.name.to_s.downcase

        return 'attachment_filename' if object_type == 'Attachment' || truthy?(@config['scope_attachments'])
        return 'wiki_requirement_link' if object_type == 'WikiHub::PageSnapshot' && requirement_link_scope?
        return 'task_requirement_link' if object_type == 'TaskHub::Task' && requirement_link_scope?

        return 'task_title' if object_type == 'TaskHub::Task'

        return 'wiki_summary' if policy_name.include?('summary')
        return 'wiki_metadata' if policy_name.include?('metadata')
        return 'wiki_heading_structure' if policy_name.include?('heading')

        'wiki_title'
      end

      def fingerprint_source(candidate)
        candidate = candidate.deep_stringify_keys
        case review_domain(candidate)
        when 'wiki_title'
          { title: candidate['title'].to_s }
        when 'wiki_summary', 'wiki_metadata', 'wiki_heading_structure'
          { title: candidate['title'].to_s, page_text: candidate['page_text'].to_s }
        when 'task_title'
          { title: candidate['title'].to_s }
        when 'attachment_filename'
          {
            filename: candidate['filename'].to_s,
            container_type: candidate['container_type'].to_s,
            container_id: candidate['container_id'].to_i
          }
        when 'wiki_requirement_link', 'task_requirement_link'
          {
            title: candidate['title'].to_s,
            current_value: candidate['current_value'].to_s,
            object_type: candidate['object_type'].to_s,
            object_id: candidate['object_id'].to_i
          }
        else
          candidate.slice('current_value', 'title', 'page_text', 'filename')
        end
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.downcase)
      end

      def requirement_link_scope?
        truthy?(@config['scope_wiki_requirement_links']) || truthy?(@config['scope_task_requirement_links']) || truthy?(@config['scope_requirement_links'])
      end
    end
  end
end

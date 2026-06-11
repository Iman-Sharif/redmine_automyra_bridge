module AutomyraBridge
  module Governance
    class Runner
      STALE_RUN_THRESHOLD = 30.minutes

      Result = Struct.new(:run, :status, :message, keyword_init: true) do
        def skipped?
          status.to_s == 'skipped'
        end
      end

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(policy:, mode: nil, provider: nil, created_by: nil)
        @policy = policy
        @mode = mode
        @provider = provider
        @created_by = created_by || policy.created_by || User.current
        @run = nil
      end

      def call
        recover_stale_runs!
        return skipped_result if active_run?

        start_run!
        execute_run!
      rescue StandardError => e
        fail_run!(e)
      ensure
        @policy.mark_ran! if @run && !@run.running?
      end

      private

      def active_run?
        @policy.with_lock do
          AutomyraBridge::GovernanceRun.active.where(governance_policy_id: @policy.id).exists?
        end
      end

      def skipped_result
        Result.new(run: nil, status: 'skipped', message: "Governance policy #{@policy.id} already has an active run.")
      end

      def start_run!
        @policy.with_lock do
          recover_stale_runs!
          raise "Governance policy #{@policy.id} already has an active run." if AutomyraBridge::GovernanceRun.active.where(governance_policy_id: @policy.id).exists?

          @run = AutomyraBridge::GovernanceRun.create!(
            governance_policy: @policy,
            created_by: @created_by,
            status: 'queued',
            policy_source_hash: PolicySourceSnapshot.hash(policy: @policy, config: config),
            max_changes_allowed: config['max_changes_per_run']
          )
          @run.mark_running!
        end
      end

      def execute_run!
        candidates = ReviewStateTracker.filter_candidates(policy: @policy, config: config, candidates: collect_candidates)
        batch = Collectors::CandidateBatch.new(candidates: candidates, project_id: @policy.project_id, scope: 'governance')
        if batch.candidates.empty?
          @run.mark_completed!(findings_count: 0, actions_count: 0, applied_count: 0, error_message: nil)
          return Result.new(run: @run, status: 'completed', message: 'completed')
        end

        evaluation = Evaluator.call(policy: @policy, candidate_batch: batch, provider: @provider, config: config)
        @run.update!(evaluation.metadata.slice(:provider_model_used, :prompt_hash, :response_hash).merge(error_message: evaluation.metadata[:evaluator_error]))
        raise evaluation.errors.join('; ') if evaluation.errors.any? && evaluation.findings.empty?

        execution = ModeExecutor.call(run: @run, policy: @policy, findings: evaluation.findings, config: config, created_by: @created_by)
        ReviewStateTracker.mark_reviewed!(policy: @policy, config: config, run: @run, candidates: batch.candidates)
        @run.mark_completed!(
          findings_count: @run.governance_findings.count,
          actions_count: @run.governance_actions.count,
          applied_count: execution.applied_count,
          error_message: evaluation.metadata[:evaluator_error]
        )
        Result.new(run: @run, status: 'completed', message: 'completed')
      end

      def fail_run!(error)
        if @run
          @run.mark_failed!(error_message: error.message, findings_count: @run.governance_findings.count, actions_count: @run.governance_actions.count, applied_count: @run.applied_count.to_i)
          Result.new(run: @run, status: 'failed', message: error.message)
        else
          Result.new(run: nil, status: 'failed', message: error.message)
        end
      end

      def recover_stale_runs!
        stale_runs.find_each do |run|
          run.mark_failed!(error_message: 'Governance run was interrupted while queued or running and was automatically marked failed.')
        end
      end

      def stale_runs
        AutomyraBridge::GovernanceRun.active
                                   .where(governance_policy_id: @policy.id)
                                   .where('COALESCE(started_at, created_at) < ?', STALE_RUN_THRESHOLD.ago)
      end

      def collect_candidates
        candidates = []
        candidates.concat(Collectors::WikiPageCollector.call(policy: @policy, limit: batch_size)) if truthy?(config['scope_wiki_pages']) || truthy?(config['scope_wiki_requirement_links']) || truthy?(config['scope_requirement_links'])
        candidates.concat(Collectors::TaskCollector.call(policy: @policy, limit: batch_size)) if truthy?(config['scope_tasks']) || truthy?(config['scope_task_requirement_links']) || truthy?(config['scope_requirement_links'])
        candidates.concat(Collectors::AttachmentCollector.call(policy: @policy, limit: batch_size)) if truthy?(config['scope_attachments'])
        if truthy?(config['scope_requirement_links']) || truthy?(config['scope_wiki_requirement_links']) || truthy?(config['scope_task_requirement_links'])
          candidates.concat(Collectors::RequirementCollector.call(policy: @policy, limit: batch_size))
        end
        candidates
      end

      def config
        @config ||= PolicyLoader.normalize_policy_config(@policy).merge(@mode.present? ? { 'mode' => @mode } : {})
      end

      def batch_size
        (config['batch_size'].presence || config['max_changes_per_run'].presence || 100).to_i
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.downcase)
      end
    end
  end
end

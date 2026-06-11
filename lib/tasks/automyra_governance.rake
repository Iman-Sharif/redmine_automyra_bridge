namespace :automyra do
  namespace :governance do
    desc 'Run all due Automyra governance policies'
    task run: :environment do
      policies = AutomyraBridge::Governance::Scheduler.call
      policies.each { |policy| AutomyraBridge::Governance::Runner.call(policy: policy) }
      puts "Ran #{policies.size} Automyra governance policy/policies."
    end

    desc 'Run one Automyra governance policy: rake automyra:governance:run_policy[policy_id,mode]'
    task :run_policy, %i[policy_id mode] => :environment do |_task, args|
      policy = AutomyraBridge::GovernancePolicy.find(args[:policy_id])
      result = AutomyraBridge::Governance::Runner.call(policy: policy, mode: args[:mode])
      puts "Governance policy #{policy.id}: #{result.status} #{result.message}"
    end

    desc 'Dry-run one Automyra governance policy in report_only mode: rake automyra:governance:dry_run[policy_id]'
    task :dry_run, [:policy_id] => :environment do |_task, args|
      policy = AutomyraBridge::GovernancePolicy.find(args[:policy_id])
      result = AutomyraBridge::Governance::Runner.call(policy: policy, mode: 'report_only')
      puts "Governance dry run #{policy.id}: #{result.status} #{result.message}"
    end

    desc 'Print Automyra governance healthcheck counts'
    task healthcheck: :environment do
      puts "policies=#{AutomyraBridge::GovernancePolicy.count}"
      puts "runs=#{AutomyraBridge::GovernanceRun.count}"
      puts "findings=#{AutomyraBridge::GovernanceFinding.count}"
      puts "actions=#{AutomyraBridge::GovernanceAction.count}"
      puts "proposals=#{defined?(AutomyraBridgeActionProposal) ? AutomyraBridgeActionProposal.count : 0}"
      puts "locked_policies=#{AutomyraBridge::GovernanceRun.running.select(:governance_policy_id).distinct.count}"
    end
  end
end

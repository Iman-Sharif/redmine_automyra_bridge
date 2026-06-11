namespace :automyra_bridge do
  desc 'Process queued Automyra bridge jobs'
  task process_queue: :environment do
    processed = 0
    AutomyraBridge::RecoverStaleJobs.call

    AutomyraBridgeJob.ready_to_process.order(:created_at, :id).find_each do |job|
      AutomyraBridge::JobProcessor.new.process(job)
      processed += 1
    end
    puts "Processed #{processed} Automyra bridge job(s)."
  end

  desc 'Recover Automyra bridge jobs stuck in running for more than 10 minutes'
  task recover_stale_jobs: :environment do
    recovered = AutomyraBridge::RecoverStaleJobs.call
    puts "Recovered #{recovered} stale Automyra bridge job(s)."
  end

  desc 'Run a minimal Automyra chat queue smoke test'
  task chat_smoke_test: :environment do
    wait_seconds = ENV.fetch('WAIT_SECONDS', '30').to_i.clamp(1, 300)
    user = User.active.first || User.first
    project = Project.visible(user).first || Project.first
    raise 'Smoke test requires a user and project.' unless user && project

    thread = AutomyraBridgeChatThread.global_for(user).first || AutomyraBridgeChatThread.create!(user: user, project: project, thread_kind: 'global', page_type: 'global', page_id: 0, page_key: "global:#{user.id}")
    message = AutomyraBridge::ChatMessageCreator.create_user_message!(user, thread, 'Hey, how many open tasks do I have?', context: { project_id: project.id, thread_kind: 'global' })
    job = AutomyraBridge::ChatJobCreator.create_job_from_message(message, thread, { project_id: project.id, thread_kind: 'global' })
    raise 'Smoke test did not queue a job.' unless job && %w[queued pending].include?(job.status)

    run = AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id) if defined?(AutomyraBridgeRun)
    puts "Queued Automyra chat smoke test job_id=#{job.id} run_id=#{run&.id || '-'} wait_seconds=#{wait_seconds}."

    AutomyraBridge::JobProcessor.process_single_job(job)
    deadline = Time.current + wait_seconds.seconds
    sleep 1 while Time.current < deadline && !%w[succeeded failed cancelled].include?(job.reload.status)

    run&.reload
    puts "Automyra chat smoke test final job_id=#{job.id} run_id=#{run&.id || '-'} job_status=#{job.status} run_status=#{run&.status || '-'}."
    abort "Smoke test failed: #{job.error_message.presence || job.status}" unless job.status == 'succeeded'
  end
end

require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceCollectorsTest < ActiveSupport::TestCase
  fixtures :users, :projects, :trackers, :issue_statuses, :enumerations

  setup do
    WikiHub::PageSnapshot.delete_all if defined?(WikiHub::PageSnapshot)
    TaskHub::Task.delete_all if defined?(TaskHub::Task)
    Issue.where("subject LIKE 'Governance collector %'").delete_all
    AutomyraBridge::GovernancePolicy.delete_all

    @user = User.find(2)
    @project = Project.find(1)
    @other_project = Project.find(2)
    @project.update!(status: Project::STATUS_ACTIVE)
    @other_project.update!(status: Project::STATUS_ACTIVE)
    @policy = create_policy(@project)
  end

  test 'wiki page collector scopes to active policy project and applies wildcard exclusions' do
    keep = create_snapshot(@project, 'Alpha Standard')
    excluded = create_snapshot(@project, 'Draft Standard')
    other = create_snapshot(@other_project, 'Other Standard')

    candidates = AutomyraBridge::Governance::Collectors::WikiPageCollector.call(
      policy: @policy,
      exclusions: ['Draft*']
    )

    assert_equal([keep.id], candidates.map { |candidate| candidate[:object_id] })
    assert_not_includes candidates.map { |candidate| candidate[:object_id] }, excluded.id
    assert_not_includes candidates.map { |candidate| candidate[:object_id] }, other.id
    assert_equal 'WikiHub::PageSnapshot', candidates.first[:object_type]
    assert_equal 'Alpha Standard', candidates.first[:current_value]
    assert_equal keep.wiki_page_id, candidates.first[:wiki_page_id]
    assert_equal 'Alpha Standard', candidates.first[:page_text]
  end

  test 'wiki page collector omits pages from archived project' do
    @project.update!(status: Project::STATUS_ARCHIVED)
    create_snapshot(@project, 'Archived Standard')

    candidates = AutomyraBridge::Governance::Collectors::WikiPageCollector.call(policy: @policy)

    assert_empty candidates
  end

  test 'task collector excludes closed statuses by default and respects limits and ordering' do
    first = create_task(@project, 'Alpha Task', 'todo')
    create_task(@project, 'Done Task', 'done')
    second = create_task(@project, 'Beta Task', 'in_progress')
    create_task(@project, 'Cancelled Task', 'cancelled')
    create_task(@other_project, 'Other Task', 'todo')

    candidates = AutomyraBridge::Governance::Collectors::TaskCollector.call(policy: @policy, limit: 2)

    assert_equal([first.id, second.id], candidates.map { |candidate| candidate[:object_id] })
    assert_equal(['Alpha Task', 'Beta Task'], candidates.map { |candidate| candidate[:title] })
  end

  test 'task collector supports wildcard exclusions and include closed config' do
    @policy.update!(config: { include_closed_tasks: true }.to_json)
    create_task(@project, 'Skip Task', 'todo')
    done = create_task(@project, 'Done Task', 'done')

    candidates = AutomyraBridge::Governance::Collectors::TaskCollector.call(policy: @policy, exclusions: ['Skip*'])

    assert_equal([done.id], candidates.map { |candidate| candidate[:object_id] })
  end

  test 'requirement collector filters by configured tracker and status' do
    tracker = Tracker.first
    status = IssueStatus.where(is_closed: false).first || IssueStatus.first
    other_status = IssueStatus.where.not(id: status.id).first || status
    keep = create_issue(@project, 'Governance collector requirement', tracker, status)
    create_issue(@project, 'Governance collector wrong status', tracker, other_status)
    create_issue(@other_project, 'Governance collector other project', tracker, status)
    @policy.update!(config: {
      requirement_tracker_ids: [tracker.id],
      requirement_status_ids: [status.id]
    }.to_json)

    candidates = AutomyraBridge::Governance::Collectors::RequirementCollector.call(policy: @policy)

    created_ids = [keep.id]
    result_ids = candidates.map { |candidate| candidate[:object_id] }

    assert_includes result_ids, keep.id
    assert_not_includes result_ids, Issue.find_by(subject: 'Governance collector wrong status').id
    assert_not_includes result_ids, Issue.find_by(subject: 'Governance collector other project').id
    assert_equal 'Issue', candidates.first[:object_type]
    assert_equal created_ids, result_ids & created_ids
  end

  test 'requirement collector supports named tracker and status policy schema deterministically' do
    tracker = Tracker.first
    status = IssueStatus.where(is_closed: false).first || IssueStatus.first
    keep = create_issue(@project, 'Governance collector named requirement', tracker, status)
    @policy.update!(config: {
      requirement_tracker_names: [tracker.name],
      requirement_status_names: [status.name]
    }.to_json)

    candidates = AutomyraBridge::Governance::Collectors::RequirementCollector.call(policy: @policy)

    assert_includes candidates.map { |candidate| candidate[:object_id] }, keep.id
    assert_equal(candidates.map { |candidate| candidate[:object_id] }.sort, candidates.map { |candidate| candidate[:object_id] })
    assert_equal tracker.name, candidates.detect { |candidate| candidate[:object_id] == keep.id }[:tracker]
  end

  test 'requirement collector omits issues from closed projects' do
    tracker = Tracker.first
    status = IssueStatus.where(is_closed: false).first || IssueStatus.first
    @project.update!(status: Project::STATUS_CLOSED)
    create_issue(@project, 'Governance collector closed project', tracker, status)
    @policy.update!(config: { requirement_tracker_ids: [tracker.id], requirement_status_ids: [status.id] }.to_json)

    candidates = AutomyraBridge::Governance::Collectors::RequirementCollector.call(policy: @policy)

    assert_empty candidates
  end

  test 'candidate batch metadata is deterministic from sorted ids and scope' do
    first = { object_id: 20 }
    second = { object_id: 10 }

    batch = AutomyraBridge::Governance::Collectors::CandidateBatch.new(
      candidates: [first, second],
      project_id: @project.id,
      scope: 'wiki_pages'
    )
    reordered = AutomyraBridge::Governance::Collectors::CandidateBatch.new(
      candidates: [second, first],
      project_id: @project.id,
      scope: 'wiki_pages'
    )

    assert_equal 2, batch.count
    assert_equal batch.batch_id, reordered.batch_id
    assert_equal({ batch_id: batch.batch_id, count: 2, project_id: @project.id, scope: 'wiki_pages' }, batch.metadata)
  end

  private

  def create_policy(project)
    AutomyraBridge::GovernancePolicy.create!(
      name: 'Collector policy',
      project: project,
      created_by: @user,
      mode: 'report_only',
      provider_model: 'manifest/auto',
      config: { batch_size: 100 }.to_json
    )
  end

  def create_snapshot(project, title)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: unique_id,
      project_id: project.id,
      title: title,
      searchable_text: title
    )
  end

  def create_task(project, title, status)
    TaskHub::Task.create!(
      title: title,
      user: @user,
      author: @user,
      project: project,
      status: status,
      priority: 2
    )
  end

  def create_issue(project, subject, tracker, status)
    Issue.create!(
      project: project,
      tracker: tracker,
      status: status,
      subject: subject,
      author: @user,
      priority: IssuePriority.default || IssuePriority.first
    )
  end

  def unique_id
    @unique_id ||= 991_000
    @unique_id += 1
  end
end

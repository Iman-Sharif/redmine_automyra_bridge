require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernancePolicyServicesTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    WikiHub::PageProfile.delete_all if defined?(WikiHub::PageProfile)
    WikiHub::PageSnapshot.delete_all if defined?(WikiHub::PageSnapshot)
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all

    @user = User.find(2)
    @project = Project.find(1)
    @other_project = Project.find(2)
    @policy = create_policy(@project, 'Project policy')
  end

  test 'policy loader loads enabled policies by id with normalized config' do
    loaded = AutomyraBridge::Governance::PolicyLoader.call(project: @project, policy_id: @policy.id)

    assert_equal 1, loaded.size
    assert_equal @policy, loaded.first.policy
    assert_equal 'propose', loaded.first.config['mode']
    assert_equal 'manifest/auto', loaded.first.config['provider_model']
    assert_equal 'sentence case', loaded.first.config['title_rules']
  end

  test 'policy loader merges wiki parsed config over database config without mutating policy' do
    profile = WikiHub::PageProfile.create!(wiki_page_id: 990_002, page_kind: 'standard', featured: false)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: 990_002,
      project_id: @project.id,
      title: 'Governance Overrides',
      searchable_text: <<~TEXT
        ```yaml
        automyra_governance:
          title_rules: wiki override
          mode: report_only
          max_changes_per_run: 1
        ```
      TEXT
    )
    @policy.update!(policy_page_id: profile.id)

    loaded = AutomyraBridge::Governance::PolicyLoader.call(project: @project, policy_id: @policy.id).first

    assert_equal 'wiki override', loaded.config['title_rules']
    assert_equal 'report_only', loaded.config['mode']
    assert_equal 'propose', @policy.reload.mode
    assert_equal({ 'title_rules' => 'sentence case' }, JSON.parse(@policy.config))
  end

  test 'policy loader loads project policies and due policies' do
    other = create_policy(@other_project, 'Other project')
    future = create_policy(@project, 'Not due', frequency_hours: 24, last_run_at: 1.hour.ago)

    project_policies = AutomyraBridge::Governance::PolicyLoader.call(project: @project).map(&:policy)
    due_policies = AutomyraBridge::Governance::PolicyLoader.call(project: @project, due: true).map(&:policy)

    assert_includes project_policies, @policy
    assert_includes project_policies, future
    assert_not_includes project_policies, other
    assert_includes due_policies, @policy
    assert_not_includes due_policies, future
  end

  test 'wiki policy loader returns raw page snapshot text by profile id and project title' do
    profile = WikiHub::PageProfile.create!(wiki_page_id: 990_001, page_kind: 'standard', featured: false)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: 990_001,
      project_id: @project.id,
      title: 'Governance Policy',
      searchable_text: 'raw governance policy text'
    )

    assert_equal 'raw governance policy text', AutomyraBridge::Governance::WikiPolicyLoader.call(page_profile_id: profile.id)
    assert_equal({ wiki_page_id: 990_001, page_snapshot_id: WikiHub::PageSnapshot.find_by(wiki_page_id: 990_001).id, title: 'Governance Policy', text: 'raw governance policy text' }, AutomyraBridge::Governance::WikiPolicyLoader.context(page_profile_id: profile.id))
    assert_equal 'raw governance policy text', AutomyraBridge::Governance::WikiPolicyLoader.call(project: @project, title: 'Governance Policy')
    assert_nil AutomyraBridge::Governance::WikiPolicyLoader.call(project: @project, title: 'Missing')
  end

  test 'wiki policy parser extracts fenced yaml governance block' do
    parsed = AutomyraBridge::Governance::WikiPolicyParser.parse(<<~TEXT)
      Intro
      ```yaml
      automyra_governance:
        title_rules: Use sentence case
        frequency_hours: 12
        max_changes_per_run: 4
        confidence_threshold: 0.82
        mode: report_only
        exclusions:
          - Draft*
        provider_model: manifest/auto
      ```
    TEXT

    assert_equal 'Use sentence case', parsed['title_rules']
    assert_equal 12, parsed['frequency_hours']
    assert_equal 4, parsed['max_changes_per_run']
    assert_in_delta 0.82, parsed['confidence_threshold'], 0.001
    assert_equal 'report_only', parsed['mode']
  end

  test 'wiki policy parser extracts fallback heading rules and ignores malformed yaml' do
    parsed = AutomyraBridge::Governance::WikiPolicyParser.parse(<<~TEXT)
      ```yaml
      automyra_governance: [
      ```
      ## Title Standard
      Use active voice and sentence case.

      ## Frequency
      frequency_hours: 6
      max_changes_per_run: 2
      confidence_threshold: 0.9
      mode: propose
      provider_model: manifest/auto
    TEXT

    assert_equal 'Use active voice and sentence case.', parsed['title_rules']
    assert_equal 6, parsed['frequency_hours']
    assert_equal 2, parsed['max_changes_per_run']
    assert_in_delta 0.9, parsed['confidence_threshold'], 0.001
    assert_equal 'propose', parsed['mode']
  end

  test 'policy validator catches invalid mode and missing scopes' do
    config = AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(@policy).merge(
      'mode' => 'invalid',
      'scope_wiki_pages' => false,
      'scope_tasks' => false,
      'scope_attachments' => false,
      'scope_requirement_links' => false,
      'scope_wiki_requirement_links' => false,
      'scope_task_requirement_links' => false
    )

    result = AutomyraBridge::Governance::PolicyValidator.call(policy: @policy, config: config)

    assert_not result.valid?
    assert_includes result.errors, 'mode is not included in the list'
    assert_includes result.errors, 'at least one governance scope must be enabled'
  end

  test 'policy loader and validator include attachment scope' do
    @policy.update!(scope_wiki_pages: false, scope_attachments: true, config: { scope_attachments: true, attachment_filename_rules: 'Use lowercase hyphenated filenames' }.to_json)

    loaded = AutomyraBridge::Governance::PolicyLoader.call(project: @project, policy_id: @policy.id).first
    result = AutomyraBridge::Governance::PolicyValidator.call(policy: @policy, config: loaded.config)

    assert_equal true, loaded.config['scope_attachments']
    assert_equal 'Use lowercase hyphenated filenames', loaded.config['attachment_filename_rules']
    assert result.valid?
  end

  test 'attachment collector returns governable attachment filename candidates' do
    attachment = Attachment.create!(container: @project, author: @user, filename: 'Bad File Name.pdf', disk_filename: 'bad_file_name.pdf', filesize: 12, content_type: 'application/pdf')
    @policy.update!(scope_wiki_pages: false, scope_attachments: true, config: { attachment_container_types: ['Project'] }.to_json)

    candidates = AutomyraBridge::Governance::Collectors::AttachmentCollector.call(policy: @policy, limit: 10)
    candidate = candidates.detect { |entry| entry[:object_id] == attachment.id }

    assert candidate
    assert_equal 'Attachment', candidate[:object_type]
    assert_equal 'Bad File Name.pdf', candidate[:current_value]
    assert_equal @project.id, candidate[:project_id]
  end

  test 'policy source snapshot hash is deterministic and changes with config' do
    config = { 'b' => 2, 'a' => { 'z' => 1, 'm' => [3, 2, 1] } }
    reordered = { 'a' => { 'm' => [3, 2, 1], 'z' => 1 }, 'b' => 2 }

    first = AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: @policy, config: config)
    second = AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: @policy, config: reordered)
    changed = AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: @policy, config: reordered.merge('b' => 3))

    assert_equal first, second
    assert_not_equal first, changed
  end

  private

  def create_policy(project, name, attrs = {})
    AutomyraBridge::GovernancePolicy.create!({
      name: name,
      project: project,
      created_by: @user,
      config: { title_rules: 'sentence case' }.to_json,
      mode: 'propose',
      provider_model: 'manifest/auto',
      frequency_hours: 1,
      last_run_at: 2.hours.ago,
      max_changes_per_run: 3,
      confidence_threshold: 0.75,
      scope_wiki_pages: true,
      scope_tasks: false,
      scope_requirement_links: false,
      scope_wiki_requirement_links: false,
      scope_task_requirement_links: false
    }.merge(attrs))
  end
end

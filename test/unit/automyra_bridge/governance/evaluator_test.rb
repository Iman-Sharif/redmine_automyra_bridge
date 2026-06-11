require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceEvaluatorTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernancePolicy.delete_all
    @user = User.find(2)
    @project = Project.find(1)
    @policy = AutomyraBridge::GovernancePolicy.create!(
      name: 'Evaluator policy',
      project: @project,
      created_by: @user,
      mode: 'report_only',
      provider_model: 'manifest/auto',
      config: {
        title_rules: 'Use sentence case',
        summary_rules: 'Every Wiki Hub page must have a concise 1-3 sentence summary suitable for list views, search results, and quick triage.',
        standard_wiki_page: {
          title: 'Automyra - Standard - Wiki Title Format',
          text: '[Domain] - [Document Type] - [Specific Subject]'
        },
        metadata_rules: 'Every Wiki Hub page should have an appropriate category and tags.',
        required_fields: %w[category tags],
        confidence_threshold: 0.8,
        max_changes_per_run: 5,
        exclusions: ['Draft*']
      }.to_json
    )
    @batch = AutomyraBridge::Governance::Collectors::CandidateBatch.new(
      candidates: [
        { object_type: 'WikiHub::PageSnapshot', object_id: 101, title: 'Bad TITLE', project_id: @project.id, current_value: 'Bad TITLE', page_text: 'Bad TITLE\n\nBody under review.' },
        { object_type: 'TaskHub::Task', object_id: 202, title: 'messy task', project_id: @project.id, current_value: 'messy task' },
        { object_type: 'Attachment', object_id: 404, filename: 'Bad File Name.pdf', project_id: @project.id, current_value: 'Bad File Name.pdf' },
        { object_type: 'Issue', object_id: 303, subject: 'Requirement alpha', tracker: 'Requirement', status: 'New', project_id: @project.id, current_value: 'Requirement alpha' }
      ],
      project_id: @project.id,
      scope: 'mixed'
    )
  end

  test 'evaluator builds prompt with policy and candidates' do
    evaluator = AutomyraBridge::Governance::Evaluator.new(policy: @policy, candidate_batch: @batch, provider: fake_provider([]))
    prompt = evaluator.build_prompt

    assert_includes prompt, 'Use sentence case'
    assert_includes prompt, 'one-sentence summary'
    assert_includes prompt, 'quick triage'
    assert_includes prompt, 'concise metadata'
    assert_includes prompt, 'category and tags'
    assert_includes prompt, 'Automyra - Standard - Wiki Title Format'
    assert_includes prompt, '[Domain] - [Document Type] - [Specific Subject]'
    assert_includes prompt, 'Draft*'
    assert_includes prompt, 'WikiHub::PageSnapshot'
    assert_includes prompt, 'Bad TITLE'
    assert_includes prompt, 'Body under review.'
    assert_includes prompt, 'Bad File Name.pdf'
    assert_includes prompt, 'requirement_candidates'
    assert_includes prompt, 'Requirement alpha'
    assert_includes prompt, @batch.batch_id
  end

  test 'fake provider returns response by batch id' do
    provider = AutomyraBridge::Governance::FakeProvider.new(@batch.batch_id => [{ object_id: 1 }])

    assert_equal [{ 'object_id' => 1 }], JSON.parse(provider.call(prompt: 'anything', model: 'manifest/auto', metadata: @batch.metadata))
  end

  test 'valid findings pass all evaluator checks and hashes are stored' do
    result = evaluate_with([
      finding(object_id: 101, recommended_value: 'Bad title', confidence: 0.95, action_type: 'update_wiki_title'),
      finding(object_type: 'TaskHub::Task', object_id: 202, current_value: 'messy task', recommended_value: 'Messy task', confidence: 0.9, action_type: 'update_task_title'),
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'attachment_filename', current_value: 'Bad File Name.pdf', recommended_value: 'bad-file-name.pdf', confidence: 0.9, action_type: 'review_attachment_filename')
    ])

    assert_empty result.errors
    assert_equal 3, result.findings.size
    assert_equal 'manifest/auto', result.metadata[:provider_model_used]
    assert_match(/\A[0-9a-f]{64}\z/, result.metadata[:prompt_hash])
    assert_match(/\A[0-9a-f]{64}\z/, result.metadata[:response_hash])
    assert_nil result.metadata[:evaluator_error]
  end

  test 'hallucinated object ids are rejected' do
    result = evaluate_with([finding(object_id: 999, recommended_value: 'Unknown title', confidence: 0.95)])

    assert_empty result.findings
    assert result.errors.any? { |error| error.include?('unknown candidate') }
  end

  test 'low confidence findings are rejected' do
    result = evaluate_with([finding(object_id: 101, recommended_value: 'Bad title', confidence: 0.2)])

    assert_empty result.findings
    assert result.errors.any? { |error| error.include?('confidence below threshold') }
  end

  test 'duplicate recommended values are allowed but noted' do
    result = evaluate_with([
      finding(object_id: 101, recommended_value: 'Shared title', confidence: 0.95),
      finding(object_type: 'TaskHub::Task', object_id: 202, current_value: 'messy task', recommended_value: 'Shared title', confidence: 0.95)
    ])

    assert_equal 2, result.findings.size
    assert result.notes.any? { |note| note.include?('duplicate recommended value allowed') }
  end

  test 'malformed json response is handled gracefully' do
    provider = AutomyraBridge::Governance::FakeProvider.new('default' => '{not-json')
    result = AutomyraBridge::Governance::Evaluator.call(policy: @policy, candidate_batch: @batch, provider: provider)

    assert_empty result.findings
    assert result.errors.any? { |error| error.include?('malformed JSON') }
    assert_match(/\A[0-9a-f]{64}\z/, result.metadata[:response_hash])
  end

  test 'provider response wrapper is unwrapped before validation' do
    provider = AutomyraBridge::Governance::FakeProvider.new('default' => { response: [finding].to_json })

    result = AutomyraBridge::Governance::Evaluator.call(policy: @policy, candidate_batch: @batch, provider: provider)

    assert_empty result.errors
    assert_equal 1, result.findings.size
  end

  test 'wiki governance finding variants normalize to supported review findings' do
    result = evaluate_with([
      finding(finding_type: 'summary_required', recommended_value: 'Add a concise summary.', action_type: 'review_summary'),
      finding(finding_type: 'metadata_missing', recommended_value: 'Add category and tags.', action_type: 'review_metadata'),
      finding(finding_type: 'heading_structure', recommended_value: 'Use one H1 followed by H2 sections.', action_type: 'review_heading_structure')
    ])

    assert_empty result.errors
    assert_equal %w[wiki_summary wiki_metadata wiki_heading_structure], result.findings.map { |entry| entry['finding_type'] }
    assert_equal %w[review_wiki_summary review_wiki_metadata review_wiki_heading_structure], result.findings.map { |entry| entry['action_type'] }
  end

  test 'attachment filename finding variants normalize to attachment_filename' do
    result = evaluate_with([
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'attachment_filename_noncompliant', recommended_value: 'bad-file-name.pdf', action_type: 'update_attachment_filename'),
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'attachment_filename_standard_violation', recommended_value: 'bad_file_name.pdf', action_type: 'update_attachment_filename'),
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'filename_noncompliance', recommended_value: 'bad-file-name-v2.pdf', action_type: 'update_attachment_filename'),
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'filename_noncompliant', recommended_value: 'bad-file-name-v3.pdf', action_type: 'update_attachment_filename'),
      finding(object_type: 'Attachment', object_id: 404, finding_type: 'filename_violation', recommended_value: 'bad-file-name-v4.pdf', action_type: 'update_attachment_filename')
    ])

    assert_empty result.errors
    assert_equal %w[attachment_filename attachment_filename attachment_filename attachment_filename attachment_filename], result.findings.map { |entry| entry['finding_type'] }
  end

  test 'missing requirement link variants normalize by object type' do
    result = evaluate_with([
      finding(object_id: 101, object_type: 'WikiHub::PageSnapshot', finding_type: 'missing_requirement_link', recommended_value: 'Requirement #303', action_type: 'link_wiki_requirement'),
      finding(object_id: 202, object_type: 'TaskHub::Task', current_value: 'messy task', finding_type: 'missing_requirement_link', recommended_value: 'Requirement #303', action_type: 'link_task_requirement')
    ])

    assert_empty result.errors
    assert_equal %w[wiki_requirement_link task_requirement_link], result.findings.map { |entry| entry['finding_type'] }
    assert_equal %w[link_wiki_requirement link_task_requirement], result.findings.map { |entry| entry['action_type'] }
  end

  test 'unsupported finding type falls back to policy specific finding type' do
    @policy.update!(name: 'Global Wiki Metadata Required')

    result = evaluate_with([finding(finding_type: 'policy_violation', recommended_value: 'Add category metadata.', action_type: 'propose')])

    assert_empty result.errors
    assert_equal ['wiki_metadata'], result.findings.map { |entry| entry['finding_type'] }
  end

  test 'metadata policy forces review metadata action and backfills current value' do
    @policy.update!(name: 'Global Wiki Metadata Required')

    result = evaluate_with([
      finding(
        finding_type: 'wiki_requirement_link',
        current_value: nil,
        recommended_value: { category: 'Architecture', tags: %w[automyra memory] }.to_json,
        action_type: 'link_wiki_requirement'
      )
    ])

    assert_empty result.errors
    assert_equal 'wiki_metadata', result.findings.first['finding_type']
    assert_equal 'review_wiki_metadata', result.findings.first['action_type']
    assert_equal 'Bad TITLE', result.findings.first['current_value']
    assert_equal({ 'category' => 'Architecture', 'tags' => %w[automyra memory] }, JSON.parse(result.findings.first['recommended_value']))
  end

  test 'unsupported action type falls back to action for normalized finding type' do
    result = evaluate_with([finding(finding_type: 'wiki_title_standard', recommended_value: 'Better title', action_type: 'rename')])

    assert_empty result.errors
    assert_equal 'wiki_title', result.findings.first['finding_type']
    assert_equal 'update_wiki_title', result.findings.first['action_type']
  end

  test 'summary policy rejects title-only recommendations' do
    @policy.update!(name: 'Global Wiki Summary Required')

    result = evaluate_with([
      finding(
        finding_type: 'wiki_title',
        current_value: 'Automyra_Architecture_Long-Term_Memory_Strategy',
        recommended_value: 'Automyra - Architecture - long-term memory strategy',
        action_type: 'update_wiki_title'
      )
    ])

    assert_empty result.findings
    assert result.errors.any? { |error| error.include?('summary recommendation is not a page summary') }
  end

  test 'summary policy accepts one sentence page summary' do
    @policy.update!(name: 'Global Wiki Summary Required')

    result = evaluate_with([
      finding(
        finding_type: 'wiki_title',
        recommended_value: 'This page explains the long-term memory architecture used by Automyra for durable agent context.',
        action_type: 'update_wiki_title'
      )
    ])

    assert_empty result.errors
    assert_equal 'wiki_summary', result.findings.first['finding_type']
    assert_equal 'review_wiki_summary', result.findings.first['action_type']
    assert_equal 'This page explains the long-term memory architecture used by Automyra for durable agent context.', result.findings.first['recommended_value']
  end

  test 'summary policy backfills missing current value from candidate' do
    @policy.update!(name: 'Global Wiki Summary Required')

    result = evaluate_with([
      finding(
        finding_type: 'summary_required',
        current_value: nil,
        recommended_value: 'This page explains the long-term memory architecture used by Automyra for durable agent context.',
        action_type: 'review_summary'
      )
    ])

    assert_empty result.errors
    assert_equal 'wiki_summary', result.findings.first['finding_type']
    assert_equal 'Bad TITLE', result.findings.first['current_value']
  end

  test 'wiki title recommendations use canonical standard format' do
    batch = AutomyraBridge::Governance::Collectors::CandidateBatch.new(
      candidates: [
        {
          object_type: 'WikiHub::PageSnapshot',
          object_id: 505,
          title: 'Automyra_Architecture_Long-Term_Memory_Strategy',
          project_id: @project.id,
          current_value: 'Automyra_Architecture_Long-Term_Memory_Strategy'
        }
      ],
      project_id: @project.id,
      scope: 'mixed'
    )

    result = AutomyraBridge::Governance::Evaluator.call(
      policy: @policy,
      candidate_batch: batch,
      provider: fake_provider([
        finding(
          object_id: 505,
          current_value: 'Automyra_Architecture_Long-Term_Memory_Strategy',
          recommended_value: 'Automyra Architecture Long-Term Memory Strategy'
        )
      ])
    )

    assert_empty result.errors
    assert_equal 'Automyra - Architecture - long-term memory strategy', result.findings.first['recommended_value']
  end

  test 'requirement link recommendations must reference visible requirement candidates' do
    valid = evaluate_with([finding(finding_type: 'wiki_requirement_link', action_type: 'link_wiki_requirement', recommended_value: 'Requirement #303')])
    invalid = evaluate_with([finding(finding_type: 'wiki_requirement_link', action_type: 'link_wiki_requirement', recommended_value: 'Requirement #999')])

    assert_equal 1, valid.findings.size
    assert_empty invalid.findings
    assert invalid.errors.any? { |error| error.include?('references unknown requirement') }
  end

  test 'structured response validator rejects missing fields and invalid types' do
    result = AutomyraBridge::Governance::StructuredResponseValidator.call([
      { object_type: 'WikiHub::PageSnapshot', object_id: 'abc' },
      { object_type: 'WikiHub::PageSnapshot', object_id: 101, finding_type: 'wiki_title', current_value: 'A', recommended_value: 'B', confidence: 'nope', rationale: 'Because' }
    ])

    assert_empty result.findings
    assert result.errors.any? { |error| error.include?('missing required fields') }
    assert result.errors.any? { |error| error.include?('confidence must be numeric') }
  end

  private

  def evaluate_with(findings)
    AutomyraBridge::Governance::Evaluator.call(
      policy: @policy,
      candidate_batch: @batch,
      provider: fake_provider(findings)
    )
  end

  def fake_provider(response)
    AutomyraBridge::Governance::FakeProvider.new('default' => response)
  end

  def finding(attrs = {})
    {
      object_type: attrs.fetch(:object_type, 'WikiHub::PageSnapshot'),
      object_id: attrs.fetch(:object_id, 101),
      finding_type: attrs.fetch(:finding_type, 'wiki_title'),
      current_value: attrs.fetch(:current_value, 'Bad TITLE'),
      recommended_value: attrs.fetch(:recommended_value, 'Bad title'),
      confidence: attrs.fetch(:confidence, 0.95),
      rationale: attrs.fetch(:rationale, 'Matches title standard.'),
      action_type: attrs.fetch(:action_type, 'update_wiki_title')
    }
  end
end

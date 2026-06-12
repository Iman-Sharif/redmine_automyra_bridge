require_relative '../test_helper'

class AutomyraBridgeActivityLogTest < ActiveSupport::TestCase
  fixtures :users, :projects

  def setup
    @user = users(:users_001)
    @project = projects(:projects_001)
    @log = AutomyraBridgeActivityLog.new(
      action_type: 'note_created',
      source: 'trilium',
      session_id: 'session-123',
      target_type: 'TriliumNote',
      target_id: 'note-abc123',
      project: @project,
      user: @user,
      summary: 'Created note from Trilium sync',
      details: { 'note_title' => 'Test Note', 'notebook' => 'Projects' },
      idempotency_key: 'unique-key-123',
      occurred_at: Time.current
    )
  end

  def teardown
    AutomyraBridgeActivityLog.delete_all
  end

  # Validations

  def test_valid_log
    assert @log.valid?, "Log should be valid: #{@log.errors.full_messages.join(', ')}"
  end

  def test_requires_action_type
    @log.action_type = nil
    assert_not @log.valid?
    assert_includes @log.errors[:action_type], 'cannot be blank'
  end

  def test_requires_source
    @log.source = nil
    assert_not @log.valid?
    assert_includes @log.errors[:source], 'cannot be blank'
  end

  def test_requires_summary
    @log.summary = nil
    assert_not @log.valid?
    assert_includes @log.errors[:summary], 'cannot be blank'
  end

  def test_requires_idempotency_key
    @log.idempotency_key = nil
    assert_not @log.valid?
    assert_includes @log.errors[:idempotency_key], 'cannot be blank'
  end

  def test_requires_occurred_at
    @log.occurred_at = nil
    assert_not @log.valid?
    assert_includes @log.errors[:occurred_at], 'cannot be blank'
  end

  def test_idempotency_key_must_be_unique
    @log.save!
    
    duplicate = AutomyraBridgeActivityLog.new(
      action_type: 'note_updated',
      source: 'trilium',
      summary: 'Another action',
      idempotency_key: 'unique-key-123',
      occurred_at: Time.current
    )
    
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idempotency_key], 'has already been taken'
  end

  def test_optional_fields_can_be_blank
    @log.session_id = nil
    @log.target_type = nil
    @log.target_id = nil
    @log.project_id = nil
    @log.user_id = nil
    @log.details = nil
    
    assert @log.valid?
  end

  # Associations

  def test_belongs_to_project
    @log.save!
    assert_equal @project, @log.project
  end

  def test_belongs_to_user
    @log.save!
    assert_equal @user, @log.user
  end

  def test_project_is_optional
    @log.project = nil
    assert @log.valid?
  end

  def test_user_is_optional
    @log.user = nil
    assert @log.valid?
  end

  # Scopes

  def test_for_date_scope
    today = Date.current
    yesterday = today - 1.day
    
    @log.update!(occurred_at: today.noon)
    
    yesterday_log = AutomyraBridgeActivityLog.create!(
      action_type: 'note_deleted',
      source: 'trilium',
      summary: 'Yesterday action',
      idempotency_key: 'yesterday-key',
      occurred_at: yesterday.noon
    )
    
    today_logs = AutomyraBridgeActivityLog.for_date(today)
    assert_includes today_logs, @log
    assert_not_includes today_logs, yesterday_log
  end

  def test_for_project_scope
    other_project = Project.create!(
      name: 'Other Project',
      identifier: 'other-project-test'
    )
    
    @log.save!
    
    other_log = AutomyraBridgeActivityLog.create!(
      action_type: 'note_created',
      source: 'trilium',
      project: other_project,
      summary: 'Other project action',
      idempotency_key: 'other-project-key',
      occurred_at: Time.current
    )
    
    project_logs = AutomyraBridgeActivityLog.for_project(@project)
    assert_includes project_logs, @log
    assert_not_includes project_logs, other_log
    
    other_project.destroy
  end

  def test_by_action_type_scope
    @log.save!
    
    other_log = AutomyraBridgeActivityLog.create!(
      action_type: 'issue_created',
      source: 'redmine',
      summary: 'Issue created',
      idempotency_key: 'issue-key',
      occurred_at: Time.current
    )
    
    note_logs = AutomyraBridgeActivityLog.by_action_type('note_created')
    assert_includes note_logs, @log
    assert_not_includes note_logs, other_log
  end

  def test_recent_scope
    older_log = AutomyraBridgeActivityLog.create!(
      action_type: 'note_created',
      source: 'trilium',
      summary: 'Older action',
      idempotency_key: 'older-key',
      occurred_at: 2.days.ago
    )
    
    @log.update!(occurred_at: 1.hour.ago)
    
    newer_log = AutomyraBridgeActivityLog.create!(
      action_type: 'note_created',
      source: 'trilium',
      summary: 'Newer action',
      idempotency_key: 'newer-key',
      occurred_at: 30.minutes.ago
    )
    
    recent_logs = AutomyraBridgeActivityLog.recent(2)
    
    assert_equal 2, recent_logs.count
    assert_includes recent_logs, newer_log
    assert_includes recent_logs, @log
    assert_not_includes recent_logs, older_log
  end

  # Details jsonb

  def test_details_stores_json
    @log.details = { 'key' => 'value', 'nested' => { 'data' => 123 } }
    @log.save!
    
    reloaded = AutomyraBridgeActivityLog.find(@log.id)
    assert_equal 'value', reloaded.details['key']
    assert_equal 123, reloaded.details['nested']['data']
  end

  # Target ID as string

  def test_target_id_stores_string
    @log.target_id = 'trilium-note-uuid-abc123'
    @log.save!
    
    reloaded = AutomyraBridgeActivityLog.find(@log.id)
    assert_equal 'trilium-note-uuid-abc123', reloaded.target_id
  end
end

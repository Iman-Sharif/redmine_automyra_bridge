class AutomyraBridgeChatThread < ActiveRecord::Base
  belongs_to :user, class_name: 'User'
  belongs_to :project, class_name: 'Project', optional: true
  has_many :chat_messages,
           class_name: 'AutomyraBridgeChatMessage',
           foreign_key: 'chat_thread_id',
           dependent: :destroy

  validates :user_id, :thread_kind, :page_key, presence: true
  validates :page_type, presence: true, if: -> { thread_kind == 'page' }
  validates :page_id, presence: true, if: -> { thread_kind == 'page' }
  validates :page_key, uniqueness: { scope: :user_id }
  validates :channel_key, uniqueness: { scope: :user_id, allow_blank: true }, if: -> { column_names.include?('channel_key') }

  scope :for_page, lambda { |user, page_type, page_id, project_id: nil, url_path: nil|
    normalized_page_type = AutomyraBridge::ChatThreadChannelResolver.page_type(page_type)
    canonical_project_id = project_id.presence || (normalized_page_type == 'project' ? page_id : nil)
    canonical_key = AutomyraBridge::ChatThreadChannelResolver.channel_key(
      user: user,
      thread_kind: 'page',
      page_type: normalized_page_type,
      page_id: page_id,
      project_id: canonical_project_id,
      url_path: url_path
    )

    channel_predicate = column_names.include?('channel_key') ? ' OR (channel_key = :canonical_key)' : ''

    where(user: user, thread_kind: 'page').where(
      "(page_key = :canonical_key)#{channel_predicate} OR (page_type = :page_type AND page_id = :page_id)",
      canonical_key: canonical_key,
      page_type: normalized_page_type,
      page_id: page_id.to_i
    )
  }
  scope :global_for, lambda { |user|
    canonical_key = AutomyraBridge::ChatThreadChannelResolver.channel_key(user: user, thread_kind: 'global')
    scope = where(user: user, thread_kind: 'global')
    if column_names.include?('channel_key')
      scope.where('(page_key IN (:keys)) OR (channel_key = :canonical_key)', keys: [canonical_key, 'global'], canonical_key: canonical_key)
    else
      scope.where(page_key: [canonical_key, 'global'])
    end
  }
  scope :active, -> { where(status: 'active') }
  scope :with_unread, -> { where('unread_count > 0') }

  def mark_read!
    update!(unread_count: 0, last_message_at: chat_messages.maximum(:created_at) || updated_at)
  end

  def increment_unread!(sender_user_id, sender_type: nil)
    return if sender_user_id == user_id && sender_type != 'assistant' && sender_type != 'system'
    increment!(:unread_count)
  end

  def last_message
    chat_messages.order(created_at: :desc).first
  end

  def title_display
    title.presence || page_key.presence || "Chat"
  end

  def canonical_channel_key
    AutomyraBridge::ChatThreadChannelResolver.channel_key(
      user: user_id,
      thread_kind: thread_kind,
      page_type: page_type,
      page_id: page_id,
      project_id: project_id,
      url_path: url_path
    )
  end

  def channel_key
    if has_attribute?(:channel_key)
      self[:channel_key].presence || canonical_channel_key
    else
      canonical_channel_key
    end
  end

  def channel_label
    scope, value = channel_key.to_s.split(':')
    case scope.to_s
    when 'global'
      user&.name.presence || value.to_s
    when 'issue'
      "Issue ##{value}"
    when 'project'
      "Project #{value}"
    when 'wiki_page'
      value.to_s
    when 'task_hub_task'
      "Task ##{value}"
    else
      channel_key.to_s
    end
  end

  def channel_description
    case AutomyraBridge::ChatThreadChannelResolver.page_type(page_type)
    when 'global'
      'Global chat for this user'
    when 'project'
      'Project chat channel'
    when 'issue'
      'Issue chat channel'
    when 'wiki_page'
      'Wiki page chat channel'
    when 'task_hub_task'
      'Task Hub task chat channel'
    else
      'Page chat channel'
    end
  end

  def channel_description
    case AutomyraBridge::ChatThreadChannelResolver.page_type(page_type)
    when 'global'
      'Global chat for this user'
    when 'project'
      'Project chat channel'
    when 'issue'
      'Issue chat channel'
    when 'wiki_page'
      'Wiki page chat channel'
    when 'task_hub_task'
      'Task Hub task chat channel'
    else
      'Page chat channel'
    end
  end

  def self.generate_page_key(page_type, page_id)
    AutomyraBridge::ChatThreadChannelResolver.channel_key(
      thread_kind: page_type.to_s == 'global' ? 'global' : 'page',
      page_type: page_type,
      page_id: page_id,
      project_id: page_type.to_s == 'project' ? page_id : nil
    )
  end

  before_validation :set_page_key_defaults, on: :create

  private

  def set_page_key_defaults
    self.page_type = 'global' if thread_kind == 'global'
    self.page_id = 0 if thread_kind == 'global'
    canonical_key = canonical_channel_key
    self.page_key = canonical_key if page_key.blank?
    self.channel_key = canonical_key if has_attribute?(:channel_key) && self[:channel_key].blank?
  end
end

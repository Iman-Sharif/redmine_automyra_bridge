class AutomyraBridgeActivityLog < ActiveRecord::Base
  self.table_name = 'automyra_activity_logs'

  belongs_to :project, optional: true
  belongs_to :user, optional: true

  validates :action_type, presence: true
  validates :source, presence: true
  validates :summary, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :occurred_at, presence: true

  scope :for_date, ->(date) { where(occurred_at: date.beginning_of_day..date.end_of_day) }
  scope :for_project, ->(project) { where(project_id: project.id) }
  scope :by_action_type, ->(type) { where(action_type: type) }
  scope :recent, ->(limit) { order(occurred_at: :desc).limit(limit) }
end

class AutomyraBridgeRunEvent < ApplicationRecord
  belongs_to :run,
             class_name: 'AutomyraBridgeRun',
             foreign_key: 'automyra_bridge_run_id'
  belongs_to :created_by,
             class_name: 'User',
             optional: true

  validates :automyra_bridge_run_id, :event_type, presence: true

  scope :by_run, ->(run_id) { where(automyra_bridge_run_id: run_id) }
  scope :by_sequence, -> { order(:sequence) }
  scope :visible, -> { where(visible_to_user: true) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end

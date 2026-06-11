class AutomyraBridgeAuditEvent < ActiveRecord::Base
  belongs_to :user
  belongs_to :project, optional: true

  validates :action, :correlation_id, :idempotency_key, :status, presence: true
end

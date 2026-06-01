module WikiHub
  class IndexRun < ActiveRecord::Base
    self.table_name = 'wiki_hub_index_runs'

    STATUSES = %w[pending running completed failed].freeze

    scope :completed_successfully, -> { where(status: 'completed') }
    scope :recent_first, -> { order(started_at: :desc, id: :desc) }

    validates :started_at, :status, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :pages_processed, numericality: { greater_than_or_equal_to: 0 }
  end
end

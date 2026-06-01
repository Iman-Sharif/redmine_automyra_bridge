module WikiHub
  class PageSnapshot < ActiveRecord::Base
    self.table_name = 'wiki_hub_page_snapshots'

    belongs_to :wiki_page, class_name: 'WikiPage'
    belongs_to :project, class_name: 'Project'
    belongs_to :current_version, class_name: 'WikiContentVersion', optional: true

    has_one :wiki_page_profile, class_name: 'WikiHub::PageProfile', foreign_key: 'wiki_page_id', primary_key: 'wiki_page_id'

    validates :wiki_page_id, :project_id, :title, :searchable_text, presence: true
    validates :wiki_page_id, uniqueness: true
  end
end

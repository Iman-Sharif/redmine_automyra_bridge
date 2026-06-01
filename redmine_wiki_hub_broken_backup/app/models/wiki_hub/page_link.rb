module WikiHub
  class PageLink < ActiveRecord::Base
    self.table_name = 'wiki_hub_page_links'

    belongs_to :source_page, class_name: 'WikiPage', foreign_key: :source_page_id
    belongs_to :target_page, class_name: 'WikiPage', foreign_key: :target_page_id, optional: true
    belongs_to :target_project, class_name: 'Project', foreign_key: :target_project_id, optional: true

    validates :source_page_id, :target_title, :link_type, presence: true
    validates :resolved, inclusion: { in: [true, false] }
  end
end

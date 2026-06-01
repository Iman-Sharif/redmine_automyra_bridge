module WikiHub
  class Tagging < ActiveRecord::Base
    self.table_name = 'wiki_hub_taggings'

    belongs_to :wiki_page, class_name: 'WikiPage'
    belongs_to :tag, class_name: 'WikiHub::Tag', inverse_of: :taggings

    validates :wiki_page_id, :tag_id, presence: true
    validates :wiki_page_id, uniqueness: { scope: :tag_id }
  end
end

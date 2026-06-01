module WikiHub
  class Tag < ActiveRecord::Base
    self.table_name = 'wiki_hub_tags'

    has_many :taggings, class_name: 'WikiHub::Tagging', foreign_key: :tag_id, inverse_of: :tag, dependent: :delete_all
    has_many :wiki_pages, through: :taggings, source: :wiki_page

    validates :name, presence: true, uniqueness: { case_sensitive: false }
  end
end

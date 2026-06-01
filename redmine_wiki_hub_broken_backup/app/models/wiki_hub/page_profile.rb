module WikiHub
  class PageProfile < ActiveRecord::Base
    self.table_name = 'wiki_hub_page_profiles'

    enum :page_kind, {
      standard: 'standard',
      template: 'template',
      lesson_learned: 'lesson_learned'
    }

    belongs_to :wiki_page, class_name: 'WikiPage'

    validates :wiki_page_id, :page_kind, presence: true
    validates :wiki_page_id, uniqueness: true
    validates :page_kind, inclusion: { in: page_kinds.keys }
    validates :featured, inclusion: { in: [true, false] }

    # Conditional validation: lesson_learned pages require lesson_date
    validates :lesson_date, presence: true, if: :lesson_learned?

    private

    def lesson_learned?
      page_kind == 'lesson_learned'
    end
  end
end

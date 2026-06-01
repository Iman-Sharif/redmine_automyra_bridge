module WikiHub
  class UserPreference < ActiveRecord::Base
    self.table_name = 'wiki_hub_user_preferences'

    belongs_to :user, class_name: 'User'

    validates :user_id, presence: true, uniqueness: true
    validates :homepage_enabled, inclusion: { in: [true, false] }
  end
end

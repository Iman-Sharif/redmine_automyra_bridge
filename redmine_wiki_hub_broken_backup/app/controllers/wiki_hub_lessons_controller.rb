class WikiHubLessonsController < ApplicationController
  before_action :require_login

  def index
    visible_pages = WikiHub::PageUniverseService.new(User.current).visible_pages
    @lessons = visible_pages
               .joins('INNER JOIN wiki_hub_page_profiles ON wiki_hub_page_profiles.wiki_page_id = wiki_hub_page_snapshots.wiki_page_id')
               .where(wiki_hub_page_profiles: { page_kind: 'lesson_learned' })
               .select('wiki_hub_page_snapshots.*', 'wiki_hub_page_profiles.lesson_date AS lesson_date')
               .order(Arel.sql('wiki_hub_page_profiles.lesson_date DESC NULLS LAST, wiki_hub_page_snapshots.updated_at DESC'))
  end
end

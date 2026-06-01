require File.expand_path('../test_helper', __dir__)

class PageUniverseServiceTest < RedmineWikiHub::TestCase
  setup do
    seed_snapshots!
  end

  test 'hub_reader_a sees agreements and procurement-kb but not process-docs' do
    user = User.find_by!(login: 'hub_reader_a')
    service = WikiHub::PageUniverseService.new(user)

    assert_equal ['Contract Boilerplate', 'Lessons 2026-04', 'Master Playbook'], service.visible_pages.pluck(:title).sort
    assert_not_includes service.visible_pages.pluck(:title), 'Supplier Onboarding'
  end

  test 'hub_reader_b sees process-docs only' do
    user = User.find_by!(login: 'hub_reader_b')
    service = WikiHub::PageUniverseService.new(user)

    assert_equal ['Supplier Onboarding'], service.visible_pages.pluck(:title).sort
  end

  test 'hub_no_wiki sees nothing' do
    user = User.find_by!(login: 'hub_no_wiki')
    service = WikiHub::PageUniverseService.new(user)

    assert_equal 0, service.visible_pages.count
  end

  private

  def seed_snapshots!
    WikiHub::PageSnapshot.delete_all

    create_snapshot(6401, 6201, 'Master Playbook', 'Canonical policy and operating controls.')
    create_snapshot(6402, 6203, 'Supplier Onboarding', 'Intake and approval lifecycle.')
    create_snapshot(6403, 6202, 'Contract Boilerplate', 'Standard legal clauses and fallback terms.')
    create_snapshot(6404, 6201, 'Lessons 2026-04', 'Incident and remediation notes for April 2026.')
  end

  def create_snapshot(wiki_page_id, project_id, title, searchable_text)
    WikiHub::PageSnapshot.create!(
      wiki_page_id: wiki_page_id,
      project_id: project_id,
      title: title,
      searchable_text: searchable_text,
      current_version_id: nil
    )
  end
end

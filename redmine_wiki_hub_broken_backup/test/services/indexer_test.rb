require File.expand_path('../test_helper', __dir__)
require 'rake'

class IndexerTest < RedmineWikiHub::TestCase
  setup do
    WikiHub::PageSnapshot.delete_all
    WikiHub::PageLink.delete_all
    WikiHub::PageProfile.delete_all
    WikiHub::IndexRun.delete_all
  end

  test 'wiki save hook creates and updates snapshot and links' do
    page = WikiPage.find(6401)
    page.content.text = "h1. Master Playbook\n\nSee [[Lessons 2026-04]] and [[@procurement-kb/Contract Boilerplate]] and [[Missing Page]]."
    page.content.save!

    Redmine::Hook.call_hook(:controller_wiki_edit_after_save, page: page)

    snapshot = WikiHub::PageSnapshot.find_by!(wiki_page_id: page.id)
    assert_equal page.wiki.project_id, snapshot.project_id
    assert_includes snapshot.searchable_text, 'See [[Lessons 2026-04]]'

    links = WikiHub::PageLink.where(source_page_id: page.id).order(:target_title)
    assert_equal 3, links.count
    assert_equal 2, links.where(resolved: true).count
    assert links.exists?(target_title: 'Lessons 2026-04', target_project_id: 6201, resolved: true)
    assert links.exists?(target_title: 'Contract Boilerplate', target_project_id: 6202, resolved: true)
    assert links.exists?(target_title: 'Missing Page', target_project_id: 6201, resolved: false)
  end

  test 'rebuild_all refreshes snapshots, removes stale rows, and records completed index run' do
    WikiHub::PageSnapshot.create!(wiki_page_id: 999_999, project_id: 6201, title: 'Stale', searchable_text: 'stale')
    WikiHub::PageProfile.create!(wiki_page_id: 999_999, page_kind: 'standard', featured: false)
    WikiHub::PageLink.create!(
      source_page_id: 999_999,
      target_project_id: 6201,
      target_title: 'Ghost',
      resolved: false,
      link_type: 'wiki'
    )

    result = WikiHub::Indexer.rebuild_all(batch_size: 2)

    assert_equal WikiPage.count, result[:pages_processed]
    assert_equal 0, WikiHub::PageSnapshot.where(wiki_page_id: 999_999).count
    assert_equal 0, WikiHub::PageProfile.where(wiki_page_id: 999_999).count
    assert_equal 0, WikiHub::PageLink.where(source_page_id: 999_999).count

    index_run = WikiHub::IndexRun.find(result[:index_run_id])
    assert_equal 'completed', index_run.status
    assert_equal WikiPage.count, index_run.pages_processed
    assert_not_nil index_run.completed_at
  end

  test 'rebuild_all converges across repeated runs without duplicate snapshots or links' do
    page = WikiPage.find(6401)
    page.content.text = '[[Lessons 2026-04]] [[@procurement-kb/Contract Boilerplate]]'
    page.content.save!

    first = WikiHub::Indexer.rebuild_all(batch_size: 1)
    first_snapshot_signature = WikiHub::PageSnapshot.order(:wiki_page_id).pluck(:wiki_page_id, :project_id, :title, :current_version_id)
    first_link_signature = WikiHub::PageLink.order(:source_page_id, :target_project_id, :target_title).pluck(:source_page_id, :target_page_id, :target_project_id, :target_title, :resolved)

    second = WikiHub::Indexer.rebuild_all(batch_size: 1)

    assert_equal WikiPage.count, first[:pages_processed]
    assert_equal WikiPage.count, second[:pages_processed]
    assert_equal first_snapshot_signature, WikiHub::PageSnapshot.order(:wiki_page_id).pluck(:wiki_page_id, :project_id, :title, :current_version_id)
    assert_equal first_link_signature, WikiHub::PageLink.order(:source_page_id, :target_project_id, :target_title).pluck(:source_page_id, :target_page_id, :target_project_id, :target_title, :resolved)
    assert_equal({}, WikiHub::PageSnapshot.group(:wiki_page_id).having('COUNT(*) > 1').count)
    assert_equal({}, WikiHub::PageLink.group(:source_page_id, :target_project_id, :target_title, :link_type).having('COUNT(*) > 1').count)
  end

  test 'rebuild_all deduplicates repeated link targets for a page' do
    page = WikiPage.find(6401)
    page.content.text = '[[Lessons 2026-04]] [[Lessons 2026-04]] [[@procurement-kb/Contract Boilerplate]] [[@procurement-kb/Contract Boilerplate]]'
    page.content.save!

    2.times { WikiHub::Indexer.rebuild_all(batch_size: 1) }

    links = WikiHub::PageLink.where(source_page_id: page.id).order(:target_project_id, :target_title)
    assert_equal 2, links.count
    assert_equal ['Contract Boilerplate', 'Lessons 2026-04'], links.pluck(:target_title)
    assert_equal({}, links.group(:target_project_id, :target_title, :link_type).having('COUNT(*) > 1').count)
  end

  test 'rebuild_all removes stale snapshots profiles and source links and unreferences dead targets' do
    WikiHub::PageSnapshot.create!(wiki_page_id: 999_991, project_id: 999_992, title: 'Ghost', searchable_text: 'ghost')
    WikiHub::PageProfile.create!(wiki_page_id: 999_991, page_kind: 'standard', featured: false)
    WikiHub::PageLink.create!(source_page_id: 999_991, target_page_id: nil, target_project_id: 999_992, target_title: 'Ghost', resolved: false, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 999_991, target_project_id: 999_992, target_title: 'Ghost', resolved: true, link_type: 'wiki')

    WikiHub::Indexer.rebuild_all(batch_size: 2)

    assert_equal 0, WikiHub::PageSnapshot.where(wiki_page_id: 999_991).count
    assert_equal 0, WikiHub::PageProfile.where(wiki_page_id: 999_991).count
    assert_equal 0, WikiHub::PageLink.where(source_page_id: 999_991).count

    inbound_link = WikiHub::PageLink.find_by!(source_page_id: 6401, target_title: 'Ghost')
    assert_nil inbound_link.target_page_id
    assert_not inbound_link.resolved
  end

  test 'rebuild_all removes stale artifacts for pages that are no longer indexable' do
    orphan_page = WikiPage.find(6401)
    WikiHub::PageSnapshot.create!(wiki_page_id: orphan_page.id, project_id: orphan_page.wiki.project_id, title: orphan_page.title, searchable_text: orphan_page.title)
    WikiHub::PageProfile.create!(wiki_page_id: orphan_page.id, page_kind: 'standard', featured: false)
    WikiHub::PageLink.create!(source_page_id: orphan_page.id, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')
    WikiHub::PageLink.create!(source_page_id: 6404, target_page_id: orphan_page.id, target_project_id: orphan_page.wiki.project_id, target_title: orphan_page.title, resolved: true, link_type: 'wiki')

    original_indexable_page = WikiHub::Indexer.method(:indexable_page?)

    result = WikiHub::Indexer.stub(:indexable_page?, lambda { |wiki_page|
      wiki_page.id != orphan_page.id && original_indexable_page.call(wiki_page)
    }) do
      WikiHub::Indexer.rebuild_all(batch_size: 1)
    end

    assert_equal WikiPage.count - 1, result[:pages_processed]
    assert_equal 0, WikiHub::PageSnapshot.where(wiki_page_id: orphan_page.id).count
    assert_equal 0, WikiHub::PageProfile.where(wiki_page_id: orphan_page.id).count
    assert_equal 0, WikiHub::PageLink.where(source_page_id: orphan_page.id).count

    inbound_link = WikiHub::PageLink.find_by!(source_page_id: 6404, target_title: orphan_page.title)
    assert_nil inbound_link.target_page_id
    assert_not inbound_link.resolved
  end

  test 'rake wiki_hub:rebuild runs and healthcheck reports ok' do
    Rake::Task.define_task(:environment)
    load File.expand_path('../../lib/tasks/wiki_hub.rake', __dir__)

    task = Rake::Task['wiki_hub:rebuild']
    task.reenable
    task.invoke

    assert_equal 'ok', WikiHub::Healthcheck.call[:status]
  end

  test 'reindex_page returns default result for nil page' do
    result = WikiHub::Indexer.reindex_page(nil)

    assert_equal 0, result[:pages_processed]
    assert_equal 0, result[:links_found]
    assert_equal [], result[:errors]
  end

  test 'reindex_page stores latest content version id when present' do
    page = WikiPage.find(6401)
    page.content.text = "h1. Master Playbook\n\nCurrent body"
    page.content.save!

    WikiHub::Indexer.reindex_page(page)

    snapshot = WikiHub::PageSnapshot.find_by!(wiki_page_id: page.id)
    assert_not_nil snapshot.current_version_id
    assert_equal page.content.versions.reorder(version: :desc).first.id, snapshot.current_version_id
  end

  test 'reindex_page rewrites links rather than appending duplicates' do
    page = WikiPage.find(6401)
    page.content.text = '[[Lessons 2026-04]] [[@procurement-kb/Contract Boilerplate]]'
    page.content.save!
    WikiHub::Indexer.reindex_page(page)

    page.content.text = '[[Lessons 2026-04]]'
    page.content.save!
    WikiHub::Indexer.reindex_page(page)

    links = WikiHub::PageLink.where(source_page_id: page.id)
    assert_equal 1, links.count
    assert_equal ['Lessons 2026-04'], links.pluck(:target_title)
  end

  test 'remove_page deletes snapshot profile and source links' do
    WikiHub::PageSnapshot.create!(wiki_page_id: 6401, project_id: 6201, title: 'Master Playbook', searchable_text: 'text')
    WikiHub::PageProfile.create!(wiki_page_id: 6401, page_kind: 'standard', featured: false)
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')

    WikiHub::Indexer.remove_page(6401)

    assert_equal 0, WikiHub::PageSnapshot.where(wiki_page_id: 6401).count
    assert_equal 0, WikiHub::PageProfile.where(wiki_page_id: 6401).count
    assert_equal 0, WikiHub::PageLink.where(source_page_id: 6401).count
  end

  test 'remove_page turns inbound resolved links into unresolved orphans' do
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: 6403, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: true, link_type: 'wiki')

    WikiHub::Indexer.remove_page(6403)

    link = WikiHub::PageLink.find_by!(source_page_id: 6401)
    assert_nil link.target_page_id
    assert_not link.resolved
  end

  test 'rebuild_all clears stale links whose source pages no longer exist' do
    WikiHub::PageLink.create!(source_page_id: 999_998, target_page_id: nil, target_project_id: 6201, target_title: 'Ghost', resolved: false, link_type: 'wiki')

    WikiHub::Indexer.rebuild_all(batch_size: 2)

    assert_equal 0, WikiHub::PageLink.where(source_page_id: 999_998).count
  end

  test 'rebuild_all with small batch size still completes successfully' do
    result = WikiHub::Indexer.rebuild_all(batch_size: 1)

    run = WikiHub::IndexRun.find(result[:index_run_id])
    assert_equal 'completed', run.status
    assert_equal WikiPage.count, run.pages_processed
  end

  test 'rebuild_all supports alternate batch size parameter' do
    result = WikiHub::Indexer.rebuild_all(batch_size: 3)

    assert_equal WikiPage.count, result[:pages_processed]
    assert_equal 0, result[:errors].size
  end

  test 'partial rebuild failures mark the run failed and healthcheck does not report success' do
    failing_page = WikiPage.find(6401)
    original_reindex_page = WikiHub::Indexer.method(:reindex_page)

    result = WikiHub::Indexer.stub(:reindex_page, lambda { |wiki_page|
      raise StandardError, 'forced boom' if wiki_page.id == failing_page.id

      original_reindex_page.call(wiki_page)
    }) do
      WikiHub::Indexer.rebuild_all(batch_size: 1)
    end

    run = WikiHub::IndexRun.find(result[:index_run_id])
    health = WikiHub::Healthcheck.call

    assert_equal 'failed', run.status
    assert_equal 1, result[:errors].size
    assert_match(/wiki_page_id=#{failing_page.id} StandardError: forced boom/, result[:errors].first)
    assert_equal 'error', health.fetch(:status)
    assert_equal 'failed', health.fetch(:details).fetch(:latest_index_run_status)
    assert_match(/forced boom/, health.fetch(:details).fetch(:latest_index_run_error))
    assert_nil health.fetch(:details).fetch(:recent_successful_index_run_at)
  end

  test 'rebuild_all surfaces page-level error payloads as failed runs' do
    flagged_page = WikiPage.find(6401)
    original_reindex_page = WikiHub::Indexer.method(:reindex_page)

    result = WikiHub::Indexer.stub(:reindex_page, lambda { |wiki_page|
      next({ pages_processed: 1, links_found: 0, errors: ['custom validation failed'] }) if wiki_page.id == flagged_page.id

      original_reindex_page.call(wiki_page)
    }) do
      WikiHub::Indexer.rebuild_all(batch_size: 1)
    end

    run = WikiHub::IndexRun.find(result[:index_run_id])

    assert_equal ['wiki_page_id=6401 custom validation failed'], result[:errors]
    assert_equal 'failed', run.status
    assert_match(/custom validation failed/, run.error_message)
  end

  test 'rake wiki_hub:rebuild raises when rebuild returns indexing errors' do
    Rake::Task.clear
    Rake::Task.define_task(:environment)
    load File.expand_path('../../lib/tasks/wiki_hub.rake', __dir__)

    task = Rake::Task['wiki_hub:rebuild']
    task.reenable

    error = assert_raises(RuntimeError) do
      WikiHub::Indexer.stub(:rebuild_all, { index_run_id: 1, pages_total: 3, pages_processed: 2, links_found: 1, errors: ['boom'] }) do
        task.invoke
      end
    end

    assert_match(/1 indexing error/, error.message)
  end

  test 'rebuild_all reconciles unresolved links when target exists' do
    WikiHub::PageLink.create!(source_page_id: 6401, target_page_id: nil, target_project_id: 6202, target_title: 'Contract Boilerplate', resolved: false, link_type: 'wiki')

    WikiHub::Indexer.send(:reconcile_unresolved_links!)

    link = WikiHub::PageLink.find_by!(source_page_id: 6401, target_title: 'Contract Boilerplate')
    assert link.resolved
    assert_equal 6403, link.target_page_id
  end

  test 'reindex_page uses page title and content in searchable text' do
    page = WikiPage.find(6401)
    page.content.text = 'Updated content body'
    page.content.save!

    WikiHub::Indexer.reindex_page(page)

    snapshot = WikiHub::PageSnapshot.find_by!(wiki_page_id: page.id)
    assert_includes snapshot.searchable_text, page.title
    assert_includes snapshot.searchable_text, 'Updated content body'
  end
end

require File.expand_path('../test_helper', __dir__)

class HooksTest < RedmineWikiHub::TestCase
  FakePage = Struct.new(:id, :title, keyword_init: true)
  FakeLogger = Struct.new(:messages) do
    def error(message)
      messages << message
    end
  end

  class RenameBridgeHarness
    prepend WikiHub::WikiControllerLifecycleBridge

    def initialize(page:, renamed_title:)
      @page = page
      @renamed_title = renamed_title
    end

    def rename
      @page.title = @renamed_title
      :renamed
    end
  end

  class DestroyBridgeHarness
    prepend WikiHub::WikiControllerLifecycleBridge

    def initialize(page:)
      @page = page
    end

    def destroy
      @page = nil
      :destroyed
    end
  end

  test 'wiki save hook logs and tolerates reindexing failures' do
    page = WikiPage.find(6401)
    failure = StandardError.new('forced save failure')
    logger = FakeLogger.new([])

    Rails.stub(:logger, logger) do
      WikiHub::Indexer.stub(:reindex_page, ->(*) { raise failure }) do
        Redmine::Hook.call_hook(:controller_wiki_edit_after_save, page: page)
      end
    end

    assert_equal 1, logger.messages.size
    assert_match(/wiki save reindex failed/, logger.messages.first)
    assert_match(/page_id=#{page.id}/, logger.messages.first)
    assert_match(/StandardError: forced save failure/, logger.messages.first)
  end

  test 'rename lifecycle bridge logs and tolerates reindexing failures' do
    page = FakePage.new(id: 6401, title: 'Before Rename')
    failure = StandardError.new('forced rename failure')
    logger = FakeLogger.new([])

    result = nil
    Rails.stub(:logger, logger) do
      WikiHub::Indexer.stub(:reindex_page, ->(*) { raise failure }) do
        result = RenameBridgeHarness.new(page: page, renamed_title: 'After Rename').rename
      end
    end

    assert_equal :renamed, result
    assert_equal 1, logger.messages.size
    assert_match(/wiki rename reindex failed/, logger.messages.first)
    assert_match(/page_id=6401/, logger.messages.first)
    assert_match(/StandardError: forced rename failure/, logger.messages.first)
  end

  test 'destroy lifecycle bridge logs and tolerates cleanup failures' do
    page = FakePage.new(id: 6401, title: 'Disposable Page')
    failure = StandardError.new('forced destroy failure')
    logger = FakeLogger.new([])

    result = nil
    Rails.stub(:logger, logger) do
      WikiHub::Indexer.stub(:remove_page, ->(*) { raise failure }) do
        WikiPage.stub(:exists?, false) do
          result = DestroyBridgeHarness.new(page: page).destroy
        end
      end
    end

    assert_equal :destroyed, result
    assert_equal 1, logger.messages.size
    assert_match(/wiki destroy cleanup failed/, logger.messages.first)
    assert_match(/page_id=6401/, logger.messages.first)
    assert_match(/StandardError: forced destroy failure/, logger.messages.first)
  end
end

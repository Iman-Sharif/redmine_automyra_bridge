require File.expand_path('../test_helper', __dir__)

class LinkParserTest < RedmineWikiHub::TestCase
  test 'parses same-project and cross-project wiki links' do
    text = <<~TEXT
      Links: [[Lessons 2026-04]], [[@procurement-kb/Contract Boilerplate]], [[Missing Page]].
    TEXT

    parsed = WikiHub::LinkParser.parse(text, source_project_id: 6201)

    assert_equal 3, parsed.size

    same_project = parsed.find { |entry| entry[:target_title] == 'Lessons 2026-04' }
    assert_equal 6201, same_project[:target_project_id]

    cross_project = parsed.find { |entry| entry[:target_title] == 'Contract Boilerplate' }
    assert_equal 6202, cross_project[:target_project_id]

    unresolved_project = parsed.find { |entry| entry[:target_title] == 'Missing Page' }
    assert_equal 6201, unresolved_project[:target_project_id]
  end

  test 'skips malformed links gracefully' do
    text = 'Noise [[ ]] [[@/bad]] [[@unknown/ ]] [[Still Good]]'

    parsed = WikiHub::LinkParser.parse(text, source_project_id: 6203)

    assert_equal 1, parsed.size
    assert_equal 'Still Good', parsed.first[:target_title]
    assert_equal 6203, parsed.first[:target_project_id]
  end
end

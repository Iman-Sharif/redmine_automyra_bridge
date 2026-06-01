require File.expand_path('../test_helper', __dir__)

class TemplateVariableServiceTest < RedmineWikiHub::TestCase
  test 'extract_variables returns unique variables with defaults and required flags' do
    variables = WikiHub::TemplateVariableService.extract_variables(<<~TEXT)
      Owner: {{owner}}
      Owner again: {{owner}}
      Due: {{due_date: "2026-04-30"}}
    TEXT

    assert_equal [
      { name: 'owner', default: nil, required: true },
      { name: 'due_date', default: '2026-04-30', required: false }
    ], variables
  end

  test 'process_template preserves placeholders when required values are missing' do
    content = 'Owner: {{owner}} / Due: {{due_date: "2026-04-30"}}'

    rendered = WikiHub::TemplateVariableService.process_template(content, 'owner' => '')

    assert_equal 'Owner: {{owner}} / Due: 2026-04-30', rendered
  end

  test 'process_template accepts stringified controller params style hashes' do
    content = 'Owner: {{owner}} / Body: {{body_text: "draft"}}'

    rendered = WikiHub::TemplateVariableService.process_template(content, { 'owner' => 'Legal Ops', 'body_text' => 'Ready' })

    assert_equal 'Owner: Legal Ops / Body: Ready', rendered
  end

  test 'validate_variables reports missing required keys only' do
    validation = WikiHub::TemplateVariableService.validate_variables(
      'Owner: {{owner}} / Link: {{doc_link: "https://example.test"}}',
      'owner' => 'Legal'
    )

    assert_equal true, validation.fetch(:valid)
    assert_equal [], validation.fetch(:missing)
    assert_equal ['owner', 'doc_link'], validation.fetch(:all_variables)
  end

  test 'variable_form_fields infers field types from variable names' do
    fields = WikiHub::TemplateVariableService.variable_form_fields(
      '{{review_date}} {{owner_email}} {{doc_link}} {{summary_text}} {{owner}}'
    )

    assert_equal %w[date email url textarea text], fields.map { |field| field.fetch(:type) }
  end

  test 'oversized content is rejected by all public entry points' do
    oversized = 'a' * (WikiHub::TemplateVariableService::MAX_CONTENT_LENGTH + 1)

    assert_raises(ArgumentError) { WikiHub::TemplateVariableService.extract_variables(oversized) }
    assert_raises(ArgumentError) { WikiHub::TemplateVariableService.process_template(oversized, {}) }
    assert_raises(ArgumentError) { WikiHub::TemplateVariableService.validate_variables(oversized, {}) }
    assert_raises(ArgumentError) { WikiHub::TemplateVariableService.variable_form_fields(oversized) }
  end
end

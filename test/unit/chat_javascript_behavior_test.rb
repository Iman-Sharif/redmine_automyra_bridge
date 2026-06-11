# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class ChatJavascriptBehaviorTest < ActiveSupport::TestCase
  JAVASCRIPT_PATH = File.expand_path('../../assets/javascripts/automyra_chat.js', __dir__)

  test 'send button is disabled while message is loading' do
    source = File.read(JAVASCRIPT_PATH)

    assert_includes source, 'if (this.isLoading) return;'
    assert_includes source, 'this.setLoading(true);'
    assert_includes source, 'this.setLoading(false);'
    assert_includes source, 'sendBtn.disabled = this.isLoading;'
    assert_includes source, "sendBtn.textContent = this.isLoading ? 'Sending…'"
  end

  test 'mark read sends thread id and polling requires open panel' do
    source = File.read(JAVASCRIPT_PATH)

    assert_includes source, 'if (!thread.id) return;'
    assert_includes source, 'thread_id: thread.id'
    assert_includes source, 'if (!this.panelOpen) return;'
    assert_includes source, 'if (!this.panelOpen) return;'
    assert_includes source, 'this.panelOpen === true'
  end
end

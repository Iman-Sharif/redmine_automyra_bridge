class AddKindToAutomyraBridgeChatMessages < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:automyra_bridge_chat_messages)

    add_column :automyra_bridge_chat_messages, :kind, :string, default: 'message', null: false unless column_exists?(:automyra_bridge_chat_messages, :kind)
    add_index :automyra_bridge_chat_messages, %i[chat_thread_id kind], name: 'index_chat_messages_on_thread_and_kind' unless index_exists?(:automyra_bridge_chat_messages, %i[chat_thread_id kind], name: 'index_chat_messages_on_thread_and_kind')
  end

  def down
    return unless table_exists?(:automyra_bridge_chat_messages)

    remove_index :automyra_bridge_chat_messages, name: 'index_chat_messages_on_thread_and_kind' if index_exists?(:automyra_bridge_chat_messages, name: 'index_chat_messages_on_thread_and_kind')
    remove_column :automyra_bridge_chat_messages, :kind if column_exists?(:automyra_bridge_chat_messages, :kind)
  end
end

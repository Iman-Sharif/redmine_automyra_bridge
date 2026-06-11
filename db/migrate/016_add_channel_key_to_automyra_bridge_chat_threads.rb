class AddChannelKeyToAutomyraBridgeChatThreads < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:automyra_bridge_chat_threads)
    return if column_exists?(:automyra_bridge_chat_threads, :channel_key)

    add_column :automyra_bridge_chat_threads, :channel_key, :string
    add_index :automyra_bridge_chat_threads, :channel_key
    add_index :automyra_bridge_chat_threads, [:user_id, :channel_key], unique: true, name: 'index_chat_threads_on_user_and_channel_key'
  end

  def down
    return unless table_exists?(:automyra_bridge_chat_threads)
    return unless column_exists?(:automyra_bridge_chat_threads, :channel_key)

    remove_index :automyra_bridge_chat_threads, name: 'index_chat_threads_on_user_and_channel_key' if index_exists?(:automyra_bridge_chat_threads, [:user_id, :channel_key], name: 'index_chat_threads_on_user_and_channel_key')
    remove_index :automyra_bridge_chat_threads, :channel_key if index_exists?(:automyra_bridge_chat_threads, :channel_key)
    remove_column :automyra_bridge_chat_threads, :channel_key
  end
end

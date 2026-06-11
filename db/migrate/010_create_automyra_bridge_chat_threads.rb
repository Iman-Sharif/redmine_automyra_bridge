class CreateAutomyraBridgeChatThreads < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_chat_threads)

    create_table :automyra_bridge_chat_threads do |t|
      t.integer :user_id, null: false
      t.integer :project_id
      t.string :page_type, null: false, default: ''
      t.integer :page_id
      t.string :page_key, null: false, default: ''
      t.string :url_path
      t.string :title
      t.string :thread_kind, null: false, default: 'page'
      t.string :status, null: false, default: 'active'
      t.integer :unread_count, null: false, default: 0
      t.datetime :last_message_at
      t.timestamps
    end

    add_index :automyra_bridge_chat_threads, :user_id
    add_index :automyra_bridge_chat_threads, :project_id
    add_index :automyra_bridge_chat_threads, :page_key
    add_index :automyra_bridge_chat_threads, [:user_id, :page_key], unique: true, name: 'index_chat_threads_on_user_and_page_key'
  end

  def down
    drop_table :automyra_bridge_chat_threads if table_exists?(:automyra_bridge_chat_threads)
  end
end

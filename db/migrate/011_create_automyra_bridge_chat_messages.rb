class CreateAutomyraBridgeChatMessages < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:automyra_bridge_chat_messages)

    create_table :automyra_bridge_chat_messages do |t|
      t.integer :chat_thread_id, null: false
      t.integer :user_id, null: false
      t.string :role, null: false, default: 'user'
      t.text :content, null: false, default: ''
      t.string :status, null: false, default: 'pending'
      t.integer :job_id
      t.integer :proposal_id
      t.timestamps
    end

    add_index :automyra_bridge_chat_messages, :chat_thread_id
    add_index :automyra_bridge_chat_messages, %i[chat_thread_id created_at], name: 'index_chat_messages_on_thread_and_created'
    add_index :automyra_bridge_chat_messages, :user_id
    add_index :automyra_bridge_chat_messages, %i[user_id created_at], name: 'index_chat_messages_on_user_and_created'
    add_index :automyra_bridge_chat_messages, :job_id
    add_index :automyra_bridge_chat_messages, :proposal_id
  end

  def down
    drop_table :automyra_bridge_chat_messages if table_exists?(:automyra_bridge_chat_messages)
  end
end

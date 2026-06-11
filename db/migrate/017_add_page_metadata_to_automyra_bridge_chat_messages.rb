class AddPageMetadataToAutomyraBridgeChatMessages < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:automyra_bridge_chat_messages)

    add_column :automyra_bridge_chat_messages, :page_type, :string unless column_exists?(:automyra_bridge_chat_messages, :page_type)
    add_column :automyra_bridge_chat_messages, :page_id, :integer unless column_exists?(:automyra_bridge_chat_messages, :page_id)
    add_column :automyra_bridge_chat_messages, :project_id, :integer unless column_exists?(:automyra_bridge_chat_messages, :project_id)
    add_column :automyra_bridge_chat_messages, :url_path, :string unless column_exists?(:automyra_bridge_chat_messages, :url_path)
    add_column :automyra_bridge_chat_messages, :page_title, :string unless column_exists?(:automyra_bridge_chat_messages, :page_title)
    add_column :automyra_bridge_chat_messages, :snapshot_reference, :string unless column_exists?(:automyra_bridge_chat_messages, :snapshot_reference)
    add_index :automyra_bridge_chat_messages, :project_id unless index_exists?(:automyra_bridge_chat_messages, :project_id)
  end

  def down
    return unless table_exists?(:automyra_bridge_chat_messages)

    remove_index :automyra_bridge_chat_messages, :project_id if index_exists?(:automyra_bridge_chat_messages, :project_id)
    %i[snapshot_reference page_title url_path project_id page_id page_type].each do |column|
      remove_column :automyra_bridge_chat_messages, column if column_exists?(:automyra_bridge_chat_messages, column)
    end
  end
end

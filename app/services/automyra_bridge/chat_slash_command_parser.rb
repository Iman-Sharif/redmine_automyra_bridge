module AutomyraBridge
  class ChatSlashCommandParser
    def self.parse(content)
      new.parse(content)
    end

    def parse(content)
      raw = content.to_s.strip
      return nil unless raw.start_with?('/')

      command, *args = raw.split(/\s+/)
      command = command.to_s.delete_prefix('/').downcase
      return nil if command.blank?

      { command: command, args: args, raw: raw }
    end
  end
end

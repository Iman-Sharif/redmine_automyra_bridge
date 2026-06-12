module AutomyraBridgeChatHelper
  def markdown_to_html(text)
    return '' if text.blank?

    # Try to use Redmine's formatter if available
    return sanitize(Redmine::WikiFormatting.to_html(:markdown, text)).html_safe if defined?(Redmine::WikiFormatting) && Redmine::WikiFormatting.respond_to?(:to_html)

    # Fallback: simple safe regex-based markdown
    html = text.dup

    # Escape HTML first
    html = ERB::Util.html_escape(html)

    # Code blocks (```lang\n...\n```)
    html.gsub!(/```(?:[A-Za-z0-9_-]{1,32}){0,1}\n(.*?)\n```/m, '<pre><code>\1</code></pre>')

    # Inline code
    html.gsub!(/`([^`]+)`/, '<code>\1</code>')

    # Bold
    html.gsub!(/\*\*([^*]+)\*\*/, '<strong>\1</strong>')
    html.gsub!(/__([^_]+)__/, '<strong>\1</strong>')

    # Italic
    html.gsub!(/\*([^*]+)\*/, '<em>\1</em>')
    html.gsub!(/_([^_]+)_/, '<em>\1</em>')

    # Links [text](url)
    html.gsub!(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2" target="_blank" rel="noopener noreferrer">\1</a>')

    # Unordered lists
    html.gsub!(/^\s*[-*]\s+(.+)$/, '<li>\1</li>')

    # Ordered lists
    html.gsub!(/^\s*\d+\.\s+(.+)$/, '<li>\1</li>')

    # Paragraphs (split on double newlines, wrap each in <p>)
    paragraphs = html.split(/\n{2,}/).map(&:strip)
    paragraphs = paragraphs.map do |p|
      if p.start_with?('<pre>', '<li>')
        p
      else
        "<p>#{p.gsub(/\n/, '<br>')}</p>"
      end
    end

    html = paragraphs.join("\n")

    # Wrap lists
    html.gsub!(%r{(<li>.*?</li>\n*)+}) do |m|
      items = m.scan(%r{<li>(.*?)</li>}).flatten.join('</li><li>')
      "<ul><li>#{items}</li></ul>"
    end

    sanitize(html).html_safe
  end
end

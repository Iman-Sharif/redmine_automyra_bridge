require 'redmine'
require_relative 'lib/wiki_hub/link_parser'
require_relative 'lib/wiki_hub/indexer'
require_relative 'lib/wiki_hub/healthcheck'
require_relative 'lib/wiki_hub/hooks'

Redmine::Plugin.register :redmine_wiki_hub do
  name 'Wiki Hub'
  author 'OpenCode'
  description 'Unified wiki hub for global and project knowledge entry points.'
  version '0.1.0'

  # Runtime support is pinned by the Redmica-first compatibility gate; keep
  # plugin metadata narrow so it does not imply broad Redmine parity.
  requires_redmine version: '6.0'

  settings default: {}, partial: nil

  menu :top_menu,
       :wiki_hub,
       { controller: 'wiki_hub', action: 'index' },
       caption: 'Wiki Hub'
end

if defined?(Rails) && Rails.configuration
  Rails.configuration.to_prepare do
    WikiHub::Hooks.install_lifecycle_bridge!
  end
end

class AutomyraBridgeProjectSetting < ActiveRecord::Base
  self.table_name = 'automyra_bridge_project_settings'

  ACTIONS = AutomyraBridgeActionProposal::ACTION_TYPES.reject { |action| action == 'unsupported_action' }.freeze
  RISK_TIERS = %w[autonomous approval_required read_only disabled].freeze

  belongs_to :project

  validates :project, presence: true
  validates :risk_tier, inclusion: { in: RISK_TIERS }

  def enabled_action_list
    enabled_actions.to_s.split(',').map(&:strip).select { |action| ACTIONS.include?(action) }
  end

  def enabled_action_list=(actions)
    self.enabled_actions = Array(actions).map(&:to_s).select { |action| ACTIONS.include?(action) }.uniq.join(',')
  end

  def action_enabled?(action)
    %w[autonomous approval_required].include?(risk_tier) && enabled_action_list.include?(action.to_s)
  end

  def autonomous?
    risk_tier == 'autonomous'
  end

  def disabled?
    risk_tier == 'disabled'
  end

  def read_only?
    risk_tier == 'read_only'
  end

  def enable_sse?
    ActiveModel::Type::Boolean.new.cast(enable_sse)
  end

  def self.for_project(project)
    find_or_create_by!(project: project) do |setting|
      setting.enabled_action_list = AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES
      setting.risk_tier = 'approval_required'
      setting.enable_sse = false if setting.respond_to?(:enable_sse=)
    end
  end
end

class WikiHubHomepageController < ApplicationController
  before_action :require_login

  def show
    @preference = preference
  end

  def update
    @preference = preference
    @preference.update!(homepage_enabled: to_boolean(preference_params[:homepage_enabled]))

    render json: {
      status: 'ok',
      homepage_enabled: @preference.homepage_enabled
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { status: 'error', errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def preference
    WikiHub::UserPreference.find_or_create_by!(user_id: User.current.id) do |pref|
      pref.homepage_enabled = false
    end
  end

  def to_boolean(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def preference_params
    params.fetch(:preference, {}).permit(:homepage_enabled)
  end
end

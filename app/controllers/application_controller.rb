class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :require_organization

  private

  def require_organization
    return if Current.user.nil? # Not authenticated yet
    return if Current.organization.present?
    return if self.class.module_parent == Admin || is_a?(Admin::BaseController)

    redirect_to admin_vendor_rates_path
  end

  VALID_PERIODS = %w[7d 30d 90d].freeze

  def resolve_period
    if params[:period].present?
      session[:selected_period] = VALID_PERIODS.include?(params[:period]) ? params[:period] : nil
    end

    @selected_period = session[:selected_period] || "all"
    @period = parse_period(@selected_period)
  end

  def parse_period(period_param)
    case period_param
    when "7d"  then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    when "90d" then 90.days.ago..Time.current
    else nil
    end
  end
end

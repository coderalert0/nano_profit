class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

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

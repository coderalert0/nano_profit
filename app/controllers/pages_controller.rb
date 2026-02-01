class PagesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_organization

  layout "landing"

  def home
    redirect_to dashboard_path if authenticated?
  end
end

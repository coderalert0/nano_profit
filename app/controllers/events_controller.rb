class EventsController < ApplicationController
  PER_PAGE = 50

  def index
    @page = [params[:page].to_i, 1].max
    @events = Current.organization.usage_telemetry_events
      .processed
      .recent
      .includes(:customer, :cost_entries)
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE + 1)

    @has_next_page = @events.size > PER_PAGE
    @events = @events.first(PER_PAGE)
  end
end

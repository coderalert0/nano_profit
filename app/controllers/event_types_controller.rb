class EventTypesController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"
    all_margins = MarginCalculator.event_type_margins(Current.organization, @period)
      .sort_by { |etm| etm[:margin].margin_bps }
    @total_count = all_margins.size
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @event_type_margins = all_margins.slice((@page - 1) * PER_PAGE, PER_PAGE) || []

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { event_type_margins: @event_type_margins, page: @page, total_pages: @total_pages }, layout: false
    end
  end

  private

  def parse_period(period_param)
    case period_param
    when "7d"  then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    when "90d" then 90.days.ago..Time.current
    else nil
    end
  end
end

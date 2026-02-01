class EventTypesController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    @selected_event_types = Array(params[:event_type]).reject(&:blank?)
    resolve_period
    all_sorted = MarginCalculator.event_type_margins(Current.organization, @period)
      .sort_by { |etm| etm[:margin].margin_bps }
    @all_event_type_names = all_sorted.map { |etm| etm[:event_type] }.sort
    if @selected_event_types.any?
      all_sorted = all_sorted.select { |etm| @selected_event_types.include?(etm[:event_type]) }
    end
    @total_count = all_sorted.size
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @event_type_margins = all_sorted.slice((@page - 1) * PER_PAGE, PER_PAGE) || []

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { event_type_margins: @event_type_margins, page: @page, total_pages: @total_pages }, layout: false
    end
  end
end

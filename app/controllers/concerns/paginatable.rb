module Paginatable
  PER_PAGE = 20

  def paginate(scope)
    @page = [params[:page].to_i, 1].max
    @total_count = scope.is_a?(Array) ? scope.size : scope.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil

    if scope.is_a?(Array)
      scope.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    else
      scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end
  end

  def infinite_scroll_request?
    request.headers["Turbo-Frame"] == "infinite-scroll-rows"
  end
end

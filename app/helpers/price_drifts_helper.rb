module PriceDriftsHelper
  def price_drift_sort_link(label, column)
    current = @sort_column == column
    next_direction = (current && @sort_direction == "asc") ? "desc" : "asc"
    arrow = current ? (@sort_direction == "asc" ? " \u25B2" : " \u25BC") : ""

    link_to "#{label}#{arrow}".html_safe,
      admin_price_drifts_path(sort: column, direction: next_direction),
      class: "hover:text-gray-900 #{current ? 'text-gray-900 font-semibold' : 'text-gray-500'}"
  end
end

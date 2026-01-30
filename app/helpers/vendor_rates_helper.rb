module VendorRatesHelper
  def vendor_rate_sort_link(label, column, extra_class: "")
    current = @sort_column == column
    next_direction = (current && @sort_direction == "asc") ? "desc" : "asc"
    arrow = current ? (@sort_direction == "asc" ? " \u25B2" : " \u25BC") : ""

    link_to "#{label}#{arrow}".html_safe,
      admin_vendor_rates_path(sort: column, direction: next_direction, vendor: params[:vendor], model: params[:model]),
      class: "hover:text-gray-900 #{current ? 'text-gray-900 font-semibold' : 'text-gray-500'} #{extra_class}"
  end
end

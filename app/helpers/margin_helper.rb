module MarginHelper
  def format_cents(cents)
    return "$0.00" if cents.nil?
    number_to_currency(cents / 100.0)
  end

  def format_bps(bps)
    return "0.00%" if bps.nil? || bps == 0
    "#{(bps / 100.0).round(2)}%"
  end

  def margin_color_class(margin_in_cents)
    if margin_in_cents.nil? || margin_in_cents == 0
      "text-gray-600"
    elsif margin_in_cents > 0
      "text-green-600"
    else
      "text-red-600"
    end
  end

  def margin_bg_class(margin_in_cents)
    if margin_in_cents.nil? || margin_in_cents == 0
      "bg-gray-50"
    elsif margin_in_cents > 0
      "bg-green-50"
    else
      "bg-red-50"
    end
  end
end

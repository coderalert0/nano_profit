module ApplicationHelper
  def format_time(time)
    return "-" if time.nil?
    tag.time(
      time.strftime("%b %-d, %Y %H:%M:%S UTC"),
      datetime: time.iso8601,
      data: { controller: "local-time" }
    )
  end
end

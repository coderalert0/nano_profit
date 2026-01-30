module ApplicationHelper
  def format_time(time, millis: true)
    return "-" if time.nil?
    fmt = millis ? "%b %-d, %Y %H:%M:%S.%L UTC" : "%b %-d, %Y %H:%M:%S UTC"
    tag.time(
      time.strftime(fmt),
      datetime: time.iso8601(3),
      data: { controller: "local-time", local_time_millis_value: millis }
    )
  end
end

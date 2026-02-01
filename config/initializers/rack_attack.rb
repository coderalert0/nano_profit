Rack::Attack.throttle("api/events", limit: 1000, period: 60) do |request|
  if request.path == "/api/v1/events" && request.post?
    request.env["HTTP_AUTHORIZATION"]&.remove("Bearer ")
  end
end

Rack::Attack.throttle("api/events/ip", limit: 100, period: 60) do |request|
  if request.path == "/api/v1/events" && request.post?
    request.ip
  end
end

Rack::Attack.throttle("password_resets", limit: 5, period: 1.hour) do |request|
  if request.path == "/passwords" && request.post?
    request.ip
  end
end

Rack::Attack.throttled_responder = lambda do |_request|
  body = { error: "Rate limit exceeded. Retry later." }.to_json
  [ 429, { "Content-Type" => "application/json" }, [ body ] ]
end

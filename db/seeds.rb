# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding..."

# Organization
org = Organization.find_or_create_by!(name: "Demo Corp") do |o|
  o.margin_alert_threshold_bps = 1000 # 10%
end

# User
user = User.find_or_create_by!(email_address: "demo@example.com") do |u|
  u.password = "password"
  u.organization = org
  u.admin = true
end
user.update!(admin: true) unless user.admin?

# Customers
company_names = [
  "Acme Corp", "Globex Industries", "Initech Solutions", "Umbrella Labs", "Stark Technologies",
  "Wayne Enterprises", "Oscorp Systems", "Cyberdyne Analytics", "Tyrell Corp", "Soylent AI",
  "Massive Dynamic", "Weyland-Yutani", "Aperture Science", "Black Mesa Research", "Vault-Tec",
  "Abstergo Industries", "Hanso Foundation", "Dharma Initiative", "Veidt Enterprises", "LexCorp",
  "Wonka Industries", "Gekko & Co", "Nakatomi Trading", "Rekall Inc", "Omni Consumer Products",
  "Cyberdyne Systems", "InGen Biotech", "Soylent Corp", "Ellingson Mineral", "Encom International",
  "Spacely Sprockets", "Cogswell Cogs", "Dunder Mifflin", "Pied Piper", "Hooli",
  "Raviga Capital", "Bachmanity", "Piedmont Tech", "Nucleus AI", "Bream-Hall",
  "Sterling Cooper", "Bluth Company", "Prestige Worldwide", "Vandelay Industries", "Kramerica",
  "Planet Express", "MomCorp", "Buy n Large", "Monsters Inc", "Axiom Micro",
  "Nova Analytics", "Zenith Data", "Apex Cloud", "Summit AI", "Frontier Labs",
  "Pinnacle Systems", "Crestview Tech", "Meridian Software", "Horizon Digital", "Catalyst AI",
  "Quantum Logic", "Nebula Computing", "Radiant Solutions", "Prism Analytics", "Echo Systems",
  "Vertex AI", "Orbital Data", "Flux Computing", "Synapse Tech", "Beacon Analytics",
  "Stratos Cloud", "Ember AI", "Pulsar Systems", "Drift Analytics", "Vantage Data",
  "Cipher Labs", "Helix Computing", "Mosaic AI", "Forge Analytics", "Lattice Systems",
  "Ridge Computing", "Aether AI", "Cobalt Analytics", "Onyx Systems", "Jade Computing",
  "Opal AI", "Slate Analytics", "Flint Systems", "Coral Computing", "Birch AI",
  "Cedar Analytics", "Elm Systems", "Maple Computing", "Oak AI", "Pine Analytics",
  "Spruce Systems", "Aspen Computing", "Willow AI", "Hazel Analytics", "Ivy Systems"
]

customers = company_names.first(100).each_with_index.map do |name, i|
  Customer.find_or_create_by!(organization: org, external_id: "cust_#{i + 1}") do |c|
    c.name = name
  end
end

puts "Created #{customers.size} customers"

# Vendor Rates (Global) — synced from LiteLLM community pricing data
result = Pricing::SyncService.new.perform
puts "Pricing sync: #{result.inspect}"

# Enterprise Override Example (uncomment and set a real org ID):
#
# enterprise_org = Organization.find(<ID>)
# VendorRate.find_or_create_by!(vendor_name: "openai", ai_model_name: "gpt-4o", organization: enterprise_org) do |vr|
#   vr.input_rate_per_1k  = 0.0020   # negotiated discount
#   vr.output_rate_per_1k = 0.0080
#   vr.unit_type = "tokens"
#   vr.active = true
# end

# Events
event_types = %w[ai_analysis ai_completion ai_embedding image_generation speech_to_text text_to_speech document_parse vector_search moderation translation]
vendor_models = {
  "openai" => %w[gpt-4 gpt-4o gpt-4o-mini],
  "anthropic" => %w[claude-3.5-sonnet claude-3-opus claude-3-haiku],
  "aws" => %w[titan-text-express titan-embed],
  "google" => %w[gemini-pro gemini-flash],
  "cohere" => %w[command-r command-r-plus],
  "mistral" => %w[mistral-large mistral-small],
  "replicate" => %w[llama-3-70b llama-3-8b],
  "huggingface" => %w[zephyr-7b mixtral-8x7b],
  "pinecone" => %w[pinecone-embed],
  "deepgram" => %w[nova-2 whisper-large]
}
vendors = vendor_models.keys

loss_event_types = %w[image_generation speech_to_text text_to_speech]

event_count = 0
customers.each do |customer|
  num_events = rand(5..20)
  num_events.times do
    token = "req_#{customer.external_id}_#{SecureRandom.hex(8)}"
    next if Event.exists?(unique_request_token: token)

    event_type = event_types.sample
    revenue = rand(50..5000)

    num_vendors = rand(1..3)
    chosen_vendors = vendors.sample(num_vendors)
    total_cost = 0
    vendor_costs = chosen_vendors.map do |v|
      cost = if loss_event_types.include?(event_type)
        rand((revenue * 0.8).to_i.clamp(10, 5000)..(revenue * 2.5).to_i.clamp(20, 10000))
      else
        rand(10..(revenue * 0.9).to_i.clamp(10, 5000))
      end
      total_cost += cost
      { vendor_name: v, ai_model_name: vendor_models[v].sample, amount_in_cents: cost, unit_count: rand(100..50000), unit_type: %w[tokens api_calls characters images seconds].sample }
    end

    margin = revenue - total_cost
    occurred = rand(1..90).days.ago + rand(0..82800).seconds

    event = Event.create!(
      organization: org,
      customer: customer,
      unique_request_token: token,
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: event_type,
      revenue_amount_in_cents: revenue,
      total_cost_in_cents: total_cost,
      margin_in_cents: margin,
      vendor_costs_raw: vendor_costs,
      metadata: { model: %w[gpt-4 gpt-4o claude-3.5 claude-opus gemini-pro mistral-large command-r llama-3].sample },
      occurred_at: occurred,
      status: "processed"
    )

    vendor_costs.each do |vc|
      CostEntry.create!(
        event: event,
        vendor_name: vc[:vendor_name],
        amount_in_cents: vc[:amount_in_cents],
        unit_count: vc[:unit_count],
        unit_type: vc[:unit_type],
        metadata: { "ai_model_name" => vc[:ai_model_name] }
      )
    end

    event_count += 1
  end
end

puts "Created #{event_count} events"

# Alerts
MarginAlert.where(organization: org).delete_all
alert_count = 0

# Customer-dimension alerts
customers.sample(30).each do |customer|
  alert_type = %w[negative_margin below_threshold].sample
  message = if alert_type == "negative_margin"
    "Negative margin on customer \"#{customer.name}\": #{rand(-5000..-100)} cents"
  else
    bps = rand(50..900)
    "Margin #{bps} bps on customer \"#{customer.name}\" (threshold: #{org.margin_alert_threshold_bps} bps)"
  end

  MarginAlert.create!(
    organization: org,
    dimension: "customer",
    dimension_value: customer.id.to_s,
    alert_type: alert_type,
    message: message,
    acknowledged_at: [nil, nil, nil, Time.current - rand(90).days].sample,
    created_at: rand(90).days.ago + rand(86400).seconds
  )
  alert_count += 1
end

# Event-type-dimension alerts
event_types.sample(6).each do |et|
  alert_type = %w[negative_margin below_threshold].sample
  message = if alert_type == "negative_margin"
    "Negative margin on event type \"#{et}\": #{rand(-3000..-50)} cents"
  else
    bps = rand(50..900)
    "Margin #{bps} bps on event type \"#{et}\" (threshold: #{org.margin_alert_threshold_bps} bps)"
  end

  MarginAlert.create!(
    organization: org,
    dimension: "event_type",
    dimension_value: et,
    alert_type: alert_type,
    message: message,
    acknowledged_at: [nil, nil, nil, Time.current - rand(90).days].sample,
    created_at: rand(90).days.ago + rand(86400).seconds
  )
  alert_count += 1
end

puts "Created #{alert_count} alerts"
puts "Done! Login with demo@example.com / password"

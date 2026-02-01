class EventProcessor
  class RateNotFoundError < StandardError; end

  def initialize(event)
    @event = event
  end

  def call
    return [] if @event.vendor_costs_raw.blank?

    preload_rates

    @event.vendor_costs_raw.map do |vc|
      create_cost_entry(vc)
    end
  end

  private

  def preload_rates
    org = @event.organization
    @rates_cache = VendorRate
      .where(organization_id: [nil, org.id])
      .to_a
      .group_by { |r| [r.vendor_name, r.ai_model_name] }
  end

  def find_cached_rate(vendor_name, ai_model_name)
    candidates = @rates_cache[[vendor_name, ai_model_name]] || []
    candidates.min_by do |r|
      [r.active? ? 0 : 1, r.organization_id == @event.organization_id ? 0 : 1]
    end
  end

  def create_cost_entry(vc)
    vendor_name = vc["vendor_name"]
    ai_model_name = vc["ai_model_name"]
    input_tokens = BigDecimal(vc.fetch("input_tokens", 0).to_s)
    output_tokens = BigDecimal(vc.fetch("output_tokens", 0).to_s)

    rate = find_cached_rate(vendor_name, ai_model_name.to_s)

    unless rate
      Rails.logger.warn("No vendor rate found for vendor '#{vendor_name}', ai_model_name '#{ai_model_name}' — creating zero-cost entry")
      return @event.cost_entries.create!(
        vendor_name: vendor_name,
        amount_in_cents: 0,
        unit_count: BigDecimal(vc.fetch("unit_count", 0).to_s),
        unit_type: vc["unit_type"].presence || "tokens",
        ai_model_name: ai_model_name,
        metadata: {
          "rate_source" => "missing_rate",
          "ai_model_name" => ai_model_name
        }
      )
    end

    amount = (input_tokens * rate.input_rate_per_1k / 1000) +
             (output_tokens * rate.output_rate_per_1k / 1000)

    @event.cost_entries.create!(
      vendor_name: vendor_name,
      amount_in_cents: amount,
      unit_count: BigDecimal(vc.fetch("unit_count", 0).to_s),
      unit_type: vc["unit_type"].presence || rate.unit_type,
      ai_model_name: ai_model_name,
      metadata: {
        "rate_source" => "vendor_rate",
        "ai_model_name" => ai_model_name,
        "input_rate_per_1k" => rate.input_rate_per_1k.to_s,
        "output_rate_per_1k" => rate.output_rate_per_1k.to_s
      }
    )
  end
end

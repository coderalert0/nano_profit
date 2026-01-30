class EventProcessor
  def initialize(event)
    @event = event
  end

  def call
    return [] if @event.vendor_costs_raw.blank?

    @event.vendor_costs_raw.map do |vc|
      create_cost_entry(vc)
    end
  end

  private

  def create_cost_entry(vc)
    vendor_name = vc["vendor_name"]
    ai_model_name = vc["ai_model_name"]
    input_tokens = BigDecimal(vc.fetch("input_tokens", 0).to_s)
    output_tokens = BigDecimal(vc.fetch("output_tokens", 0).to_s)

    rate = VendorRate.find_rate_for_processing(
      vendor_name: vendor_name,
      ai_model_name: ai_model_name.to_s,
      organization: @event.organization
    )

    raise "No vendor rate found for vendor '#{vendor_name}', ai_model_name '#{ai_model_name}'" unless rate

    amount = (input_tokens * rate.input_rate_per_1k / 1000) +
             (output_tokens * rate.output_rate_per_1k / 1000)

    @event.cost_entries.create!(
      vendor_name: vendor_name,
      amount_in_cents: amount,
      unit_count: BigDecimal(vc.fetch("unit_count", 0).to_s),
      unit_type: vc["unit_type"] || rate.unit_type,
      metadata: {
        "rate_source" => "vendor_rate",
        "ai_model_name" => ai_model_name,
        "input_rate_per_1k" => rate.input_rate_per_1k.to_s,
        "output_rate_per_1k" => rate.output_rate_per_1k.to_s
      }
    )
  end
end

module Telemetry
  class Processor
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
      model_name = vc["ai_model_name"] || @event.metadata&.dig("ai_model_name")
      input_tokens = BigDecimal(vc.fetch("input_tokens", 0).to_s)
      output_tokens = BigDecimal(vc.fetch("output_tokens", 0).to_s)

      rate = VendorRate.find_rate(
        vendor_name: vendor_name,
        ai_model_name: model_name.to_s,
        organization: @event.organization
      ) if model_name.present?

      if rate
        amount = (input_tokens * rate.input_rate_per_1k / 1000) +
                 (output_tokens * rate.output_rate_per_1k / 1000)

        @event.cost_entries.create!(
          vendor_name: vendor_name,
          amount_in_cents: amount,
          unit_count: BigDecimal(vc["unit_count"].to_s),
          unit_type: vc["unit_type"] || rate.unit_type,
          metadata: { "rate_source" => "vendor_rate", "ai_model_name" => model_name }
        )
      elsif vc["amount_in_cents"].present?
        @event.cost_entries.create!(
          vendor_name: vendor_name,
          amount_in_cents: BigDecimal(vc["amount_in_cents"].to_s),
          unit_count: BigDecimal(vc["unit_count"].to_s),
          unit_type: vc["unit_type"],
          metadata: { "rate_source" => "raw_fallback" }
        )
      else
        @event.cost_entries.create!(
          vendor_name: vendor_name,
          amount_in_cents: BigDecimal("0"),
          unit_count: BigDecimal(vc["unit_count"].to_s),
          unit_type: vc["unit_type"],
          metadata: { "rate_source" => "no_rate_or_amount" }
        )
      end
    end
  end
end

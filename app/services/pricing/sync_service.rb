require "net/http"
require "json"

module Pricing
  class SyncService
    SOURCE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    SUPPORTED_PREFIXES = %w[openai/ anthropic/ vertex_ai/].freeze
    DEFAULT_DRIFT_THRESHOLD = "0.0001".to_d

    def initialize(pricing_data: nil)
      @pricing_data = pricing_data
    end

    def perform
      data = @pricing_data || fetch_pricing_data
      models = filter_models(data)
      models = reject_deprecated(models)

      counts = { created: 0, unchanged: 0, drifts_detected: 0, skipped: 0 }

      models.each do |key, entry|
        vendor, model = parse_key(key)
        input_rate = normalize_rate(entry, :input)
        output_rate = normalize_rate(entry, :output)

        if input_rate.nil? || output_rate.nil?
          counts[:skipped] += 1
          next
        end

        existing = VendorRate.find_by(
          vendor_name: vendor,
          ai_model_name: model,
          organization_id: nil
        )

        if existing.nil?
          VendorRate.create!(
            vendor_name: vendor,
            ai_model_name: model,
            input_rate_per_1k: input_rate,
            output_rate_per_1k: output_rate,
            unit_type: "tokens",
            active: true
          )
          counts[:created] += 1
        elsif rate_drifted?(existing, input_rate, output_rate)
          PriceDrift.create!(
            vendor_name: vendor,
            ai_model_name: model,
            old_input_rate: existing.input_rate_per_1k,
            new_input_rate: input_rate,
            old_output_rate: existing.output_rate_per_1k,
            new_output_rate: output_rate,
            status: :pending
          )
          counts[:drifts_detected] += 1
        else
          counts[:unchanged] += 1
        end
      end

      counts
    end

    private

    def fetch_pricing_data
      uri = URI(SOURCE_URL)
      response = Net::HTTP.get(uri)
      JSON.parse(response)
    end

    def filter_models(data)
      data.select { |key, _| SUPPORTED_PREFIXES.any? { |prefix| key.start_with?(prefix) } }
    end

    def reject_deprecated(models)
      models.reject do |_, entry|
        deprecation = entry["deprecation_date"]
        deprecation.present? && Date.parse(deprecation) < Date.current
      end
    end

    def parse_key(key)
      vendor, *model_parts = key.split("/")
      [ vendor, model_parts.join("/") ]
    end

    def normalize_rate(entry, direction)
      token_key = "#{direction}_cost_per_token"
      char_key = "#{direction}_cost_per_character"

      if entry[token_key].present?
        entry[token_key].to_d * 1000
      elsif entry[char_key].present?
        entry[char_key].to_d * 4 * 1000
      end
    end

    def drift_threshold
      @drift_threshold ||= PlatformSetting.drift_threshold
    end

    def rate_drifted?(existing, new_input, new_output)
      (existing.input_rate_per_1k - new_input).abs > drift_threshold ||
        (existing.output_rate_per_1k - new_output).abs > drift_threshold
    end
  end
end

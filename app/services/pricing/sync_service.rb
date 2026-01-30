require "net/http"
require "json"
require "shellwords"

module Pricing
  class SyncService
    SOURCE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    SUPPORTED_PROVIDERS = %w[openai anthropic vertex_ai].freeze
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
        vendor, model = parse_key(key, entry)
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
          unless PriceDrift.exists?(vendor_name: vendor, ai_model_name: model, status: :pending)
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
          end
        else
          counts[:unchanged] += 1
        end
      end

      counts
    end

    private

    def fetch_pricing_data
      body = fetch_via_net_http
      JSON.parse(body)
    rescue OpenSSL::SSL::SSLError
      body = `curl -sS #{SOURCE_URL.shellescape}`
      raise "curl fetch failed (exit #{$?.exitstatus})" unless $?.success?
      JSON.parse(body)
    end

    def fetch_via_net_http
      uri = URI(SOURCE_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      http.get(uri.request_uri).body
    end

    def filter_models(data)
      data.select do |_, entry|
        match_provider(entry["litellm_provider"]).present?
      end
    end

    def reject_deprecated(models)
      models.reject do |_, entry|
        deprecation = entry["deprecation_date"]
        deprecation.present? && Date.parse(deprecation) < Date.current
      end
    end

    def parse_key(key, entry)
      vendor = match_provider(entry["litellm_provider"])

      # For prefixed keys like "vertex_ai/gemini-pro", strip the prefix
      model = if key.start_with?("#{vendor}/")
                key.delete_prefix("#{vendor}/")
              else
                key
              end

      [ vendor, model ]
    end

    def match_provider(provider)
      SUPPORTED_PROVIDERS.find { |p| provider == p || provider&.start_with?("#{p}/", "#{p}-") }
    end

    def normalize_rate(entry, direction)
      token_key = "#{direction}_cost_per_token"
      char_key = "#{direction}_cost_per_character"

      if entry[token_key].present?
        entry[token_key].to_d * 100_000  # dollars/token → cents/1K tokens
      elsif entry[char_key].present?
        entry[char_key].to_d * 4 * 100_000  # dollars/char → cents/1K tokens (×4 chars/token)
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

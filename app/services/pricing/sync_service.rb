require "net/http"
require "json"
require "shellwords"

module Pricing
  class SyncService
    SOURCE_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    SUPPORTED_PROVIDERS = %w[openai anthropic gemini groq azure bedrock].freeze
    CHARS_PER_TOKEN = 4

    def initialize(pricing_data: nil)
      @pricing_data = pricing_data
    end

    def perform
      data = @pricing_data || fetch_pricing_data
      models = filter_models(data)
      models = reject_deprecated(models)

      counts = { created: 0, unchanged: 0, drifts_detected: 0, skipped: 0, deactivated: 0 }
      seen_pairs = Set.new

      models.each do |key, entry|
        vendor, model = parse_key(key, entry)
        input_rate = normalize_rate(entry, :input)
        output_rate = normalize_rate(entry, :output)

        if input_rate.nil? || output_rate.nil?
          counts[:skipped] += 1
          next
        end

        seen_pairs.add([ vendor, model ])

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
          begin
            existing_drift = PriceDrift.find_by(vendor_name: vendor, ai_model_name: model, status: :pending)
            if existing_drift
              existing_drift.update!(new_input_rate: input_rate, new_output_rate: output_rate)
            else
              PriceDrift.create!(
                vendor_name: vendor,
                ai_model_name: model,
                old_input_rate: existing.input_rate_per_1k,
                new_input_rate: input_rate,
                old_output_rate: existing.output_rate_per_1k,
                new_output_rate: output_rate,
                status: :pending
              )
            end
            counts[:drifts_detected] += 1
          rescue ActiveRecord::RecordNotUnique
            # Lost race — another process already created the pending drift
          end
        else
          counts[:unchanged] += 1
        end
      end

      # Deactivate global rates no longer present in upstream data
      VendorRate.where(organization_id: nil, active: true).find_each do |rate|
        unless seen_pairs.include?([ rate.vendor_name, rate.ai_model_name ])
          rate.update!(active: false)
          counts[:deactivated] += 1
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
      response = http.get(uri.request_uri)
      raise "HTTP #{response.code} from pricing source" unless response.is_a?(Net::HTTPSuccess)
      response.body
    end

    def filter_models(data)
      data.select do |_, entry|
        match_provider(entry["litellm_provider"]).present?
      end
    end

    def reject_deprecated(models)
      models.reject do |_, entry|
        deprecation = entry["deprecation_date"]
        next false if deprecation.blank?
        Date.parse(deprecation) < Date.current
      rescue ArgumentError
        false
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
        entry[char_key].to_d * CHARS_PER_TOKEN * 100_000  # dollars/char → cents/1K tokens
      end
    end

    def drift_threshold
      @drift_threshold ||= PlatformSetting.drift_threshold
    end

    def rate_drifted?(existing, new_input, new_output)
      input_pct = percentage_change(existing.input_rate_per_1k, new_input)
      output_pct = percentage_change(existing.output_rate_per_1k, new_output)

      input_pct > drift_threshold || output_pct > drift_threshold
    end

    def percentage_change(old_val, new_val)
      return BigDecimal("0") if old_val.zero? && new_val.zero?
      return BigDecimal("Infinity") if old_val.zero?
      ((new_val - old_val) / old_val).abs
    end
  end
end

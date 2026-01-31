class VendorResponseParser
  class ParseError < StandardError; end

  OPENAI_COMPATIBLE = %w[openai groq azure together fireworks mistral].freeze
  ANTHROPIC_COMPATIBLE = %w[anthropic bedrock].freeze
  GOOGLE_COMPATIBLE = %w[google gemini].freeze

  ALL_VENDORS = (OPENAI_COMPATIBLE + ANTHROPIC_COMPATIBLE + GOOGLE_COMPATIBLE).freeze

  def self.call(vendor_name:, raw_response:)
    new(vendor_name, raw_response).call
  end

  def initialize(vendor_name, raw_response)
    @vendor_name = vendor_name.to_s.downcase
    @response = (raw_response || {}).with_indifferent_access
  end

  def call
    # Pre-normalized payloads (from SDKs) already contain the 3 fields we need
    if pre_normalized?
      return {
        "vendor_name" => @vendor_name,
        "ai_model_name" => @response[:ai_model_name].to_s.presence || "unknown",
        "input_tokens" => @response[:input_tokens].to_i,
        "output_tokens" => @response[:output_tokens].to_i
      }
    end

    unless ALL_VENDORS.include?(@vendor_name)
      raise ParseError, "Unknown vendor: '#{@vendor_name}'"
    end

    result = parse_for_vendor
    result["vendor_name"] = @vendor_name
    result
  end

  private

  def pre_normalized?
    @response.key?(:ai_model_name) && @response.key?(:input_tokens) && @response.key?(:output_tokens)
  end

  def parse_for_vendor
    if OPENAI_COMPATIBLE.include?(@vendor_name)
      parse_openai
    elsif ANTHROPIC_COMPATIBLE.include?(@vendor_name)
      parse_anthropic
    else
      parse_google
    end
  end

  def parse_openai
    usage = @response[:usage] || {}
    {
      "ai_model_name" => @response[:model].to_s.presence || "unknown",
      "input_tokens" => usage[:prompt_tokens].to_i,
      "output_tokens" => usage[:completion_tokens].to_i
    }
  end

  def parse_anthropic
    usage = @response[:usage] || {}
    {
      "ai_model_name" => @response[:model].to_s.presence || "unknown",
      "input_tokens" => usage[:input_tokens].to_i,
      "output_tokens" => usage[:output_tokens].to_i
    }
  end

  def parse_google
    model = @response[:modelVersion] || @response[:model_version] || @response[:model]
    usage = @response[:usageMetadata] || @response[:usage_metadata] || {}
    input_raw = usage[:promptTokenCount] || usage[:prompt_token_count]
    output_raw = usage[:candidatesTokenCount] || usage[:candidates_token_count]

    if input_raw.nil? && output_raw.nil? && usage.present?
      Rails.logger.warn("Google vendor response missing token counts: #{usage.keys}")
    end

    {
      "ai_model_name" => model.to_s.presence || "unknown",
      "input_tokens" => input_raw.to_i,
      "output_tokens" => output_raw.to_i
    }
  end
end

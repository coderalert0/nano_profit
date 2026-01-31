module Api
  module V1
    class EventsController < BaseController
      def create
        events_data = params[:events]

        if events_data.blank?
          render json: { error: "Missing or empty events array" }, status: :bad_request
          return
        end

        if events_data.size > 100
          render json: { error: "Batch too large (max 100 events)" }, status: :payload_too_large
          return
        end

        known_pairs = VendorRate.active
          .where(organization_id: [ nil, current_organization.id ])
          .pluck(:vendor_name, :ai_model_name)
          .to_set

        results = events_data.map do |event_data|
          permitted = permit_event_fields(event_data)
          normalized = normalize_vendor_responses(event_data)

          if normalized.is_a?(Array)
            process_single_event(permitted, normalized, known_pairs)
          else
            normalized
          end
        end

        status = batch_status(results)
        render json: { results: results }, status: status
      end

      private

      def process_single_event(ep, vendor_costs, known_pairs)
        model_errors = validate_vendor_costs_with_pairs(vendor_costs, known_pairs)
        if model_errors.any?
          return { status: "error", errors: model_errors }
        end

        event = current_organization.events.create_or_find_by!(
          unique_request_token: ep[:unique_request_token]
        ) do |e|
          e.customer_external_id = ep[:customer_external_id]
          e.customer_name = ep[:customer_name]
          e.event_type = ep[:event_type]
          e.revenue_amount_in_cents = ep[:revenue_amount_in_cents]
          e.vendor_costs_raw = vendor_costs
          e.metadata = ep[:metadata] || {}
          e.occurred_at = ep[:occurred_at] || Time.current
          e.status = "pending"
        end

        if event.previously_new_record?
          ProcessEventJob.perform_later(event.id)
          { id: event.id, unique_request_token: event.unique_request_token, status: "created" }
        elsif event.status == "pending"
          ProcessEventJob.perform_later(event.id)
          { id: event.id, unique_request_token: event.unique_request_token, status: "duplicate" }
        else
          { id: event.id, unique_request_token: event.unique_request_token, status: "duplicate" }
        end
      rescue ActiveRecord::RecordInvalid => e
        { status: "error", errors: e.record.errors.full_messages }
      end

      def batch_status(results)
        errors = results.count { |r| r[:status] == "error" }
        if errors == 0
          :ok
        elsif errors == results.size
          :unprocessable_entity
        else
          :multi_status
        end
      end

      def normalize_vendor_responses(event_data)
        raw = event_data[:vendor_responses]
        return [] if raw.blank?

        raw.map do |vr|
          VendorResponseParser.call(
            vendor_name: vr[:vendor_name].to_s,
            raw_response: vr[:raw_response]&.to_unsafe_h
          )
        end
      rescue VendorResponseParser::ParseError => e
        { status: "error", errors: [ e.message ] }
      end

      MAX_TOKENS_PER_RESPONSE = 100_000_000
      MAX_REVENUE_CENTS = 100_000_00 # $100,000

      def validate_vendor_costs_with_pairs(vendor_costs, known_pairs)
        return [] if vendor_costs.blank?

        errors = []
        vendor_costs.each do |vc|
          ai_model_name = vc["ai_model_name"]
          vendor_name = vc["vendor_name"]
          input_tokens = vc["input_tokens"].to_i
          output_tokens = vc["output_tokens"].to_i

          if ai_model_name.blank?
            errors << "Missing ai_model_name for vendor cost entry"
          elsif !known_pairs.include?([ vendor_name, ai_model_name ])
            errors << "Unrecognized vendor_name '#{vendor_name}' with ai_model_name '#{ai_model_name}'"
          end

          if vc["input_tokens"].present? && input_tokens < 0
            errors << "Negative input_tokens for vendor '#{vendor_name}'"
          end

          if vc["output_tokens"].present? && output_tokens < 0
            errors << "Negative output_tokens for vendor '#{vendor_name}'"
          end

          if input_tokens > MAX_TOKENS_PER_RESPONSE
            errors << "input_tokens exceeds maximum (#{MAX_TOKENS_PER_RESPONSE}) for vendor '#{vendor_name}'"
          end

          if output_tokens > MAX_TOKENS_PER_RESPONSE
            errors << "output_tokens exceeds maximum (#{MAX_TOKENS_PER_RESPONSE}) for vendor '#{vendor_name}'"
          end

          if input_tokens == 0 && output_tokens == 0
            errors << "Both input_tokens and output_tokens are zero or missing for vendor '#{vendor_name}'"
          end
        end
        errors
      end

      def permit_event_fields(event_data)
        event_data.permit(
          :unique_request_token,
          :customer_external_id,
          :customer_name,
          :event_type,
          :revenue_amount_in_cents,
          :occurred_at,
          metadata: {}
        )
      end
    end
  end
end

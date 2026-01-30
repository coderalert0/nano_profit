module Api
  module V1
    class TelemetryEventsController < BaseController
      def create
        model_errors = validate_ai_model_names(event_params[:vendor_costs])
        if model_errors.any?
          render json: { errors: model_errors }, status: :unprocessable_entity
          return
        end

        event = current_organization.usage_telemetry_events.create_or_find_by!(
          unique_request_token: event_params[:unique_request_token]
        ) do |e|
          e.customer_external_id = event_params[:customer_external_id]
          e.customer_name = event_params[:customer_name]
          e.event_type = event_params[:event_type]
          e.revenue_amount_in_cents = event_params[:revenue_amount_in_cents]
          e.vendor_costs_raw = event_params[:vendor_costs] || []
          e.metadata = event_params[:metadata] || {}
          e.occurred_at = event_params[:occurred_at] || Time.current
          e.status = "pending"
        end

        if event.previously_new_record?
          ProcessUsageTelemetryJob.perform_later(event.id)
          render json: { id: event.id, status: event.status }, status: :accepted
        else
          render json: { id: event.id, status: event.status }, status: :ok
        end
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def validate_ai_model_names(vendor_costs)
        return [] if vendor_costs.blank?

        known_pairs = VendorRate.active
          .where(organization_id: [nil, current_organization.id])
          .pluck(:vendor_name, :ai_model_name)
          .to_set

        errors = []
        vendor_costs.each do |vc|
          ai_model_name = vc[:ai_model_name]
          vendor_name = vc[:vendor_name]
          if ai_model_name.blank?
            errors << "Missing ai_model_name for vendor cost entry"
          elsif !known_pairs.include?([vendor_name, ai_model_name])
            errors << "Unrecognized vendor_name '#{vendor_name}' with ai_model_name '#{ai_model_name}'"
          end
        end
        errors
      end

      def event_params
        params.require(:telemetry_event).permit(
          :unique_request_token,
          :customer_external_id,
          :customer_name,
          :event_type,
          :revenue_amount_in_cents,
          :occurred_at,
          metadata: {},
          vendor_costs: [ :vendor_name, :amount_in_cents, :unit_count, :unit_type, :ai_model_name, :input_tokens, :output_tokens ]
        )
      end
    end
  end
end

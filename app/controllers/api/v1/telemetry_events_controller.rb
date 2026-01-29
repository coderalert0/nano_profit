module Api
  module V1
    class TelemetryEventsController < BaseController
      def create
        existing = current_organization.usage_telemetry_events
          .find_by(unique_request_token: event_params[:unique_request_token])

        if existing
          render json: { id: existing.id, status: existing.status }, status: :ok
          return
        end

        event = current_organization.usage_telemetry_events.new(
          unique_request_token: event_params[:unique_request_token],
          customer_external_id: event_params[:customer_external_id],
          customer_name: event_params[:customer_name],
          event_type: event_params[:event_type],
          revenue_amount_in_cents: event_params[:revenue_amount_in_cents],
          vendor_costs_raw: event_params[:vendor_costs],
          metadata: event_params[:metadata] || {},
          occurred_at: event_params[:occurred_at] || Time.current,
          status: "pending"
        )

        if event.save
          ProcessUsageTelemetryJob.perform_later(event.id)
          render json: { id: event.id, status: event.status }, status: :accepted
        else
          render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def event_params
        params.require(:telemetry_event).permit(
          :unique_request_token,
          :customer_external_id,
          :customer_name,
          :event_type,
          :revenue_amount_in_cents,
          :occurred_at,
          metadata: {},
          vendor_costs: [ :vendor_name, :amount_in_cents, :unit_count, :unit_type ]
        )
      end
    end
  end
end

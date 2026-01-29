module Api
  module V1
    class TelemetryEventsController < BaseController
      def create
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

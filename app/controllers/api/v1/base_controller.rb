module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!
      after_action :set_request_id_header

      private

      def authenticate_api_key!
        token = request.headers["Authorization"]&.remove("Bearer ")

        if token.present?
          cache_key = "api_auth:#{Digest::SHA256.hexdigest(token)}"
          org_id = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
            Organization.find_by(api_key: token)&.id
          end
          @current_organization = Organization.find_by(id: org_id) if org_id
        end

        unless @current_organization
          render json: { error: "Invalid or missing API key" }, status: :unauthorized
        end
      end

      def current_organization
        @current_organization
      end

      def set_request_id_header
        response.headers["X-Request-Id"] = request.request_id
      end
    end
  end
end

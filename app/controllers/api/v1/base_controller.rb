module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key!

      private

      def authenticate_api_key!
        token = request.headers["Authorization"]&.remove("Bearer ")
        @current_organization = Organization.find_by(api_key: token) if token.present?

        unless @current_organization
          render json: { error: "Invalid or missing API key" }, status: :unauthorized
        end
      end

      def current_organization
        @current_organization
      end
    end
  end
end

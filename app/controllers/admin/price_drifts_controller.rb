module Admin
  class PriceDriftsController < BaseController
    before_action :set_price_drift, only: %i[apply ignore]

    def index
      @price_drifts = PriceDrift.order(
        Arel.sql("CASE status WHEN 0 THEN 0 WHEN 1 THEN 1 WHEN 2 THEN 2 END"),
        created_at: :desc
      )
      @drift_threshold = PlatformSetting.drift_threshold
    end

    def apply
      @price_drift.apply!
      redirect_to admin_price_drifts_path, notice: "Price drift applied — vendor rate updated."
    end

    def ignore
      @price_drift.ignore!
      redirect_to admin_price_drifts_path, notice: "Price drift ignored."
    end

    def update_threshold
      value = params[:drift_threshold].to_s.strip
      threshold = value.to_d

      if threshold >= 0
        PlatformSetting.drift_threshold = threshold
        redirect_to admin_price_drifts_path, notice: "Drift threshold updated to #{threshold}."
      else
        redirect_to admin_price_drifts_path, alert: "Threshold must be zero or positive."
      end
    rescue ArgumentError
      redirect_to admin_price_drifts_path, alert: "Invalid threshold value."
    end

    private

    def set_price_drift
      @price_drift = PriceDrift.find(params[:id])
    end
  end
end

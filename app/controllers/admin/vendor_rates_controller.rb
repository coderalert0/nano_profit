module Admin
  class VendorRatesController < BaseController
    include Paginatable

    before_action :set_vendor_rate, only: %i[edit update destroy]

    def index
      scope = VendorRate.includes(:organization)

      @selected_vendors = Array(params[:vendor]).reject(&:blank?)
      @selected_models = Array(params[:model]).reject(&:blank?)

      scope = scope.where(vendor_name: @selected_vendors) if @selected_vendors.any?
      scope = scope.where(ai_model_name: @selected_models) if @selected_models.any?
      scope = scope.order(vendor_name: :asc, ai_model_name: :asc)

      @vendors = VendorRate.distinct.pluck(:vendor_name).sort
      @models = VendorRate.distinct.pluck(:ai_model_name).sort

      @vendor_rates = paginate(scope)

      if infinite_scroll_request?
        render partial: "rows", locals: { vendor_rates: @vendor_rates, page: @page, total_pages: @total_pages }, layout: false
      end
    end

    def new
      @vendor_rate = VendorRate.new
    end

    def create
      @vendor_rate = VendorRate.new(vendor_rate_params)

      if @vendor_rate.save
        redirect_to admin_vendor_rates_path, notice: t("admin.vendor_rates.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @vendor_rate.update(vendor_rate_params)
        redirect_to admin_vendor_rates_path, notice: t("admin.vendor_rates.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @vendor_rate.destroy!
      redirect_to admin_vendor_rates_path, notice: t("admin.vendor_rates.deleted")
    end

    private

    def set_vendor_rate
      @vendor_rate = VendorRate.find(params[:id])
    end

    def vendor_rate_params
      params.require(:vendor_rate).permit(
        :vendor_name, :ai_model_name, :input_rate_per_1k, :output_rate_per_1k,
        :unit_type, :active
      )
    end
  end
end

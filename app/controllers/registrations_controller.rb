class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  def new
    @user = User.new
  end

  def create
    organization = Organization.new(name: params[:organization_name])
    @user = organization.users.build(user_params)

    if organization.save
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome to NanoProfit!"
    else
      @user.valid?
      organization.errors.each do |error|
        @user.errors.add(:base, error.full_message)
      end
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.permit(:email_address, :password, :password_confirmation)
  end
end

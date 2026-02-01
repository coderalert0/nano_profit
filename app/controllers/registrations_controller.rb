class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_registration_url, alert: "Too many signup attempts. Try again later." }

  def new
    @user = User.new
  end

  def create
    organization = Organization.new(name: params[:organization_name])
    @user = organization.users.build(user_params)

    if organization.save
      @user.generate_email_verification_token!
      UserMailer.email_verification(@user).deliver_later
      redirect_to new_session_path, notice: "Account created! Please check your email to verify your address."
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

class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    user = User.find_by(email_verification_token: params[:token])

    if user
      user.verify_email!
      redirect_to new_session_path, notice: "Email verified! You can now sign in."
    else
      redirect_to new_session_path, alert: "Invalid or expired verification link."
    end
  end
end

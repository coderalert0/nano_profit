class UserMailer < ApplicationMailer
  def email_verification(user)
    @user = user
    @url = verify_email_url(token: user.email_verification_token)
    mail to: user.email_address, subject: "Verify your NanoProfit email"
  end
end

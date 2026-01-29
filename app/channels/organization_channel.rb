class OrganizationChannel < ApplicationCable::Channel
  def subscribed
    if current_organization
      stream_for current_organization
    else
      reject
    end
  end

  private

  def current_organization
    current_user&.organization
  end

  def current_user
    connection.current_user
  end
end

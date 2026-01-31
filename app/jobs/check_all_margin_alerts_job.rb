class CheckAllMarginAlertsJob < ApplicationJob
  def perform
    Organization.find_each do |org|
      CheckMarginAlertsJob.perform_later(org.id)
    end
  end
end

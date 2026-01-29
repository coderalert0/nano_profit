require "test_helper"

class MarginAlertTest < ActiveSupport::TestCase
  test "acknowledge! sets acknowledged_at" do
    alert = margin_alerts(:active_alert)
    assert_nil alert.acknowledged_at
    alert.acknowledge!
    assert_not_nil alert.reload.acknowledged_at
  end

  test "acknowledged? returns correct value" do
    assert_not margin_alerts(:active_alert).acknowledged?
    assert margin_alerts(:acknowledged_alert).acknowledged?
  end

  test "unacknowledged scope" do
    unacked = MarginAlert.unacknowledged
    assert_includes unacked, margin_alerts(:active_alert)
    assert_not_includes unacked, margin_alerts(:acknowledged_alert)
  end

  test "validates alert_type inclusion" do
    alert = MarginAlert.new(
      organization: organizations(:acme),
      alert_type: "invalid_type",
      message: "test"
    )
    assert_not alert.valid?
    assert_includes alert.errors[:alert_type], "is not included in the list"
  end
end

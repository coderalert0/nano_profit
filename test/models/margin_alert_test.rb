require "test_helper"

class MarginAlertTest < ActiveSupport::TestCase
  test "acknowledge! sets acknowledged_at, acknowledged_by, and notes" do
    alert = margin_alerts(:active_alert)
    user = users(:admin)
    assert_nil alert.acknowledged_at

    alert.acknowledge!(user: user, notes: "Fixed the margin issue")

    alert.reload
    assert_not_nil alert.acknowledged_at
    assert_equal user, alert.acknowledged_by
    assert_equal "Fixed the margin issue", alert.notes
  end

  test "acknowledge! without notes stores nil" do
    alert = margin_alerts(:active_alert)
    user = users(:admin)

    alert.acknowledge!(user: user)

    alert.reload
    assert_not_nil alert.acknowledged_at
    assert_equal user, alert.acknowledged_by
    assert_nil alert.notes
  end

  test "acknowledge! with blank notes stores nil" do
    alert = margin_alerts(:active_alert)
    user = users(:admin)

    alert.acknowledge!(user: user, notes: "   ")

    alert.reload
    assert_nil alert.notes
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

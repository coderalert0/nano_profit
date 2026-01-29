require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "generates api_key on create" do
    org = Organization.create!(name: "Test Org")
    assert_not_nil org.api_key
    assert_equal 64, org.api_key.length
  end

  test "requires name" do
    org = Organization.new(name: nil)
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "api_key must be unique" do
    org1 = organizations(:acme)
    org2 = Organization.new(name: "Other", api_key: org1.api_key)
    assert_not org2.valid?
    assert_includes org2.errors[:api_key], "has already been taken"
  end

  test "regenerate_api_key! changes the key" do
    org = organizations(:acme)
    old_key = org.api_key
    org.regenerate_api_key!
    assert_not_equal old_key, org.reload.api_key
  end

  test "default margin_alert_threshold_bps is 0" do
    org = Organization.create!(name: "New Org")
    assert_equal 0, org.margin_alert_threshold_bps
  end
end

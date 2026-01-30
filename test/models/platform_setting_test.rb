require "test_helper"

class PlatformSettingTest < ActiveSupport::TestCase
  test "requires key" do
    setting = PlatformSetting.new(value: "1.0")
    assert_not setting.valid?
    assert_includes setting.errors[:key], "can't be blank"
  end

  test "requires value" do
    setting = PlatformSetting.new(key: "something")
    assert_not setting.valid?
    assert_includes setting.errors[:value], "can't be blank"
  end

  test "enforces unique key" do
    PlatformSetting.create!(key: "unique_test", value: "1")
    duplicate = PlatformSetting.new(key: "unique_test", value: "2")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "drift_threshold returns stored value" do
    setting = platform_settings(:drift_threshold)
    assert_equal setting.value.to_d, PlatformSetting.drift_threshold
  end

  test "drift_threshold returns default when no record exists" do
    PlatformSetting.where(key: "drift_threshold").delete_all
    assert_equal "0.0001".to_d, PlatformSetting.drift_threshold
  end

  test "drift_threshold= creates a new record" do
    PlatformSetting.where(key: "drift_threshold").delete_all
    PlatformSetting.drift_threshold = "0.005"
    assert_equal "0.005".to_d, PlatformSetting.drift_threshold
  end

  test "drift_threshold= updates an existing record" do
    PlatformSetting.drift_threshold = "0.01"
    assert_equal "0.01".to_d, PlatformSetting.drift_threshold
  end
end

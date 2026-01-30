class PlatformSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  DEFAULT_DRIFT_THRESHOLD = "0.01"  # 1% as a fraction

  def self.drift_threshold
    find_by(key: "drift_threshold")&.value&.to_d || DEFAULT_DRIFT_THRESHOLD.to_d
  end

  def self.drift_threshold=(val)
    record = find_or_initialize_by(key: "drift_threshold")
    record.update!(value: val.to_s)
  end
end

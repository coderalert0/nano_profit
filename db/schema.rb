# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_01_30_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "cost_entries", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.string "vendor_name"
    t.decimal "amount_in_cents", precision: 15, scale: 6
    t.decimal "unit_count"
    t.string "unit_type"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_cost_entries_on_event_id"
  end

  create_table "customers", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "external_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "monthly_subscription_revenue_in_cents", default: 0, null: false
    t.string "stripe_customer_id"
    t.index ["organization_id", "external_id"], name: "index_customers_on_organization_id_and_external_id", unique: true
    t.index ["organization_id", "stripe_customer_id"], name: "idx_customers_unique_org_stripe_id", unique: true, where: "(stripe_customer_id IS NOT NULL)"
    t.index ["organization_id"], name: "index_customers_on_organization_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "customer_id"
    t.string "unique_request_token", null: false
    t.string "customer_external_id", null: false
    t.string "customer_name"
    t.string "event_type", null: false
    t.bigint "revenue_amount_in_cents", null: false
    t.decimal "total_cost_in_cents", precision: 15, scale: 6
    t.decimal "margin_in_cents", precision: 15, scale: 6
    t.jsonb "vendor_costs_raw", default: []
    t.jsonb "metadata", default: {}
    t.datetime "occurred_at"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "occurred_at"], name: "index_events_on_customer_id_and_occurred_at"
    t.index ["customer_id"], name: "index_events_on_customer_id"
    t.index ["organization_id", "status"], name: "index_events_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.index ["unique_request_token"], name: "index_events_on_unique_request_token", unique: true
  end

  create_table "margin_alerts", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "customer_id"
    t.string "alert_type", null: false
    t.text "message", null: false
    t.datetime "acknowledged_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "notes"
    t.bigint "acknowledged_by_id"
    t.index ["acknowledged_by_id"], name: "index_margin_alerts_on_acknowledged_by_id"
    t.index ["customer_id"], name: "index_margin_alerts_on_customer_id"
    t.index ["organization_id", "acknowledged_at"], name: "index_margin_alerts_on_organization_id_and_acknowledged_at"
    t.index ["organization_id", "customer_id", "alert_type"], name: "idx_margin_alerts_unique_unacknowledged", unique: true, where: "(acknowledged_at IS NULL)"
    t.index ["organization_id"], name: "index_margin_alerts_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "api_key", null: false
    t.integer "margin_alert_threshold_bps", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_user_id"
    t.string "stripe_access_token"
    t.index ["api_key"], name: "index_organizations_on_api_key", unique: true
  end

  create_table "platform_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_platform_settings_on_key", unique: true
  end

  create_table "price_drifts", force: :cascade do |t|
    t.string "vendor_name", null: false
    t.string "ai_model_name", null: false
    t.decimal "old_input_rate", precision: 15, scale: 6, null: false
    t.decimal "new_input_rate", precision: 15, scale: 6, null: false
    t.decimal "old_output_rate", precision: 15, scale: 6, null: false
    t.decimal "new_output_rate", precision: 15, scale: 6, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["vendor_name", "ai_model_name"], name: "idx_price_drifts_unique_pending", unique: true, where: "(status = 0)"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "organization_id", null: false
    t.boolean "admin", default: false, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  create_table "vendor_rates", force: :cascade do |t|
    t.string "vendor_name", null: false
    t.string "ai_model_name", null: false
    t.decimal "input_rate_per_1k", precision: 15, scale: 6, null: false
    t.decimal "output_rate_per_1k", precision: 15, scale: 6, null: false
    t.string "unit_type", default: "tokens", null: false
    t.boolean "active", default: true, null: false
    t.bigint "organization_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_vendor_rates_on_organization_id"
    t.index ["vendor_name", "ai_model_name", "organization_id"], name: "idx_vendor_rates_unique_vendor_model_org", unique: true, where: "(organization_id IS NOT NULL)"
    t.index ["vendor_name", "ai_model_name"], name: "idx_vendor_rates_unique_vendor_model_global", unique: true, where: "(organization_id IS NULL)"
  end

  add_foreign_key "cost_entries", "events"
  add_foreign_key "customers", "organizations"
  add_foreign_key "events", "customers"
  add_foreign_key "events", "organizations"
  add_foreign_key "margin_alerts", "customers"
  add_foreign_key "margin_alerts", "organizations"
  add_foreign_key "margin_alerts", "users", column: "acknowledged_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "organizations"
  add_foreign_key "vendor_rates", "organizations"
end

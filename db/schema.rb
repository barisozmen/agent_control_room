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

ActiveRecord::Schema[8.1].define(version: 2026_06_28_004630) do
  create_table "audit_events", force: :cascade do |t|
    t.text "action_summary"
    t.string "actor_lineage"
    t.string "capability"
    t.datetime "created_at", null: false
    t.string "decision"
    t.string "event_kind", null: false
    t.datetime "occurred_at", null: false
    t.integer "passport_id"
    t.integer "permission_request_id"
    t.string "result", null: false
    t.integer "run_id", null: false
    t.string "source_event_id"
    t.integer "tool_action_id"
    t.datetime "updated_at", null: false
    t.index ["passport_id", "occurred_at"], name: "index_audit_events_on_passport_id_and_occurred_at"
    t.index ["passport_id"], name: "index_audit_events_on_passport_id"
    t.index ["permission_request_id"], name: "index_audit_events_on_permission_request_id"
    t.index ["run_id", "occurred_at"], name: "index_audit_events_on_run_id_and_occurred_at"
    t.index ["run_id", "source_event_id"], name: "index_audit_events_on_run_id_and_source_event_id", unique: true, where: "source_event_id IS NOT NULL"
    t.index ["run_id"], name: "index_audit_events_on_run_id"
    t.index ["tool_action_id"], name: "index_audit_events_on_tool_action_id"
  end

  create_table "grants", force: :cascade do |t|
    t.string "capability", null: false
    t.datetime "created_at", null: false
    t.string "effect", null: false
    t.datetime "expires_at"
    t.integer "passport_id", null: false
    t.string "pattern", null: false
    t.integer "permission_request_id"
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["passport_id", "capability", "pattern", "effect"], name: "idx_on_passport_id_capability_pattern_effect_a91039ba14", unique: true
    t.index ["passport_id"], name: "index_grants_on_passport_id"
    t.index ["permission_request_id"], name: "index_grants_on_permission_request_id"
  end

  create_table "passports", force: :cascade do |t|
    t.string "actor_kind", null: false
    t.string "actor_name", null: false
    t.string "actor_ref", null: false
    t.string "bash_rule", null: false
    t.datetime "created_at", null: false
    t.string "delegate_rule", null: false
    t.string "edit_rule", null: false
    t.datetime "expires_at"
    t.integer "parent_id"
    t.string "provider", null: false
    t.string "read_rule", null: false
    t.integer "run_id", null: false
    t.string "status", null: false
    t.text "task"
    t.datetime "updated_at", null: false
    t.string "web_rule", null: false
    t.index ["parent_id"], name: "index_passports_on_parent_id"
    t.index ["run_id", "actor_ref"], name: "index_passports_on_run_id_and_actor_ref", unique: true
    t.index ["run_id", "created_at", "id"], name: "index_passports_on_run_created_id"
    t.index ["run_id", "status"], name: "index_passports_on_run_id_and_status"
    t.index ["run_id"], name: "index_passports_on_run_id"
  end

  create_table "permission_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "decision"
    t.text "decision_note"
    t.integer "passport_id", null: false
    t.string "risk_level"
    t.text "risk_summary"
    t.integer "run_id", null: false
    t.string "status", null: false
    t.string "suggested_capability"
    t.string "suggested_pattern"
    t.integer "tool_action_id", null: false
    t.datetime "updated_at", null: false
    t.index ["passport_id", "status"], name: "index_permission_requests_on_passport_id_and_status"
    t.index ["passport_id"], name: "index_permission_requests_on_passport_id"
    t.index ["run_id", "status", "created_at", "id"], name: "index_permission_requests_on_run_status_created_id", order: { created_at: :desc, id: :desc }
    t.index ["run_id", "status", "decided_at", "id"], name: "index_permission_requests_on_run_status_decided_id", order: { decided_at: :desc, id: :desc }
    t.index ["run_id", "status"], name: "index_permission_requests_on_run_id_and_status"
    t.index ["run_id"], name: "index_permission_requests_on_run_id"
    t.index ["tool_action_id"], name: "index_permission_requests_on_tool_action_id", unique: true
  end

  create_table "runs", force: :cascade do |t|
    t.integer "audit_events_count", default: 0, null: false
    t.string "bridge_token", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "last_activity_at", null: false
    t.datetime "last_seen_at"
    t.string "mode", null: false
    t.integer "observed_pid"
    t.integer "passports_count", default: 0, null: false
    t.integer "pending_permission_requests_count", default: 0, null: false
    t.string "project_path", null: false
    t.string "runtime_name", null: false
    t.string "runtime_session_id"
    t.datetime "started_at"
    t.string "status", null: false
    t.string "title"
    t.integer "tool_actions_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["bridge_token"], name: "index_runs_on_bridge_token", unique: true
    t.index ["last_activity_at", "created_at", "id"], name: "index_runs_on_last_activity_at_created_at_id", order: :desc
    t.index ["runtime_name", "created_at"], name: "index_runs_on_runtime_name_and_created_at"
    t.index ["runtime_name", "runtime_session_id"], name: "index_runs_on_runtime_name_and_runtime_session_id", unique: true, where: "runtime_session_id IS NOT NULL"
    t.index ["status"], name: "index_runs_on_status"
  end

  create_table "tool_actions", force: :cascade do |t|
    t.string "action_kind", null: false
    t.text "action_summary"
    t.json "canonical_payload"
    t.string "capability", null: false
    t.text "command"
    t.datetime "created_at", null: false
    t.integer "exit_status"
    t.datetime "finished_at"
    t.integer "passport_id", null: false
    t.string "path"
    t.datetime "requested_at", null: false
    t.integer "run_id", null: false
    t.string "source_event_id"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["passport_id", "status"], name: "index_tool_actions_on_passport_id_and_status"
    t.index ["passport_id"], name: "index_tool_actions_on_passport_id"
    t.index ["run_id", "requested_at"], name: "index_tool_actions_on_run_id_and_requested_at"
    t.index ["run_id", "source_event_id"], name: "index_tool_actions_on_run_id_and_source_event_id", unique: true, where: "source_event_id IS NOT NULL"
    t.index ["run_id"], name: "index_tool_actions_on_run_id"
  end

  add_foreign_key "audit_events", "passports"
  add_foreign_key "audit_events", "permission_requests"
  add_foreign_key "audit_events", "runs"
  add_foreign_key "audit_events", "tool_actions"
  add_foreign_key "grants", "passports"
  add_foreign_key "grants", "permission_requests"
  add_foreign_key "passports", "passports", column: "parent_id"
  add_foreign_key "passports", "runs"
  add_foreign_key "permission_requests", "passports"
  add_foreign_key "permission_requests", "runs"
  add_foreign_key "permission_requests", "tool_actions"
  add_foreign_key "tool_actions", "passports"
  add_foreign_key "tool_actions", "runs"
end

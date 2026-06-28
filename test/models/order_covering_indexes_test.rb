require "test_helper"

class OrderCoveringIndexesTest < ActiveSupport::TestCase
  test "permission request indexes cover run-scoped pending and resolved ordering" do
    assert_index :permission_requests,
      [ "run_id", "status", "created_at", "id" ],
      name: "index_permission_requests_on_run_status_created_id"

    assert_index :permission_requests,
      [ "run_id", "status", "decided_at", "id" ],
      name: "index_permission_requests_on_run_status_decided_id"
  end

  test "passport index covers run-scoped tree ordering" do
    assert_index :passports,
      [ "run_id", "created_at", "id" ],
      name: "index_passports_on_run_created_id"
  end

  private

  def assert_index(table_name, columns, name:)
    index = ActiveRecord::Base.connection.indexes(table_name).find { |candidate| candidate.name == name }

    assert index, "Expected #{table_name} to have #{name}"
    assert_equal columns, index.columns
  end
end

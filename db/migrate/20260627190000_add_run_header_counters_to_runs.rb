class AddRunHeaderCountersToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :passports_count, :integer, null: false, default: 0
    add_column :runs, :tool_actions_count, :integer, null: false, default: 0
    add_column :runs, :pending_permission_requests_count, :integer, null: false, default: 0

    up_only do
      execute <<~SQL.squish
        UPDATE runs
        SET passports_count = (
          SELECT COUNT(*)
          FROM passports
          WHERE passports.run_id = runs.id
        ),
        tool_actions_count = (
          SELECT COUNT(*)
          FROM tool_actions
          WHERE tool_actions.run_id = runs.id
        ),
        pending_permission_requests_count = (
          SELECT COUNT(*)
          FROM permission_requests
          WHERE permission_requests.run_id = runs.id
            AND permission_requests.status = 'pending'
        )
      SQL
    end
  end
end

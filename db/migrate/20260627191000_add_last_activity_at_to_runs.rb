class AddLastActivityAtToRuns < ActiveRecord::Migration[8.1]
  def up
    add_column :runs, :last_activity_at, :datetime

    execute <<~SQL.squish
      UPDATE runs
      SET last_activity_at = COALESCE(last_seen_at, started_at, created_at)
    SQL

    change_column_null :runs, :last_activity_at, false

    remove_index :runs, name: "index_runs_on_last_seen_at_and_created_at" if index_name_exists?(:runs, "index_runs_on_last_seen_at_and_created_at")
    add_index :runs,
      [ :last_activity_at, :created_at, :id ],
      order: { last_activity_at: :desc, created_at: :desc, id: :desc },
      name: "index_runs_on_last_activity_at_created_at_id"
  end

  def down
    remove_index :runs, name: "index_runs_on_last_activity_at_created_at_id" if index_name_exists?(:runs, "index_runs_on_last_activity_at_created_at_id")
    add_index :runs, [ :last_seen_at, :created_at ], name: "index_runs_on_last_seen_at_and_created_at" unless index_name_exists?(:runs, "index_runs_on_last_seen_at_and_created_at")
    remove_column :runs, :last_activity_at
  end
end

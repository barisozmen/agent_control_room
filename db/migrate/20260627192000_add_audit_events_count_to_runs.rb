class AddAuditEventsCountToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :audit_events_count, :integer, null: false, default: 0

    up_only do
      execute <<~SQL.squish
        UPDATE runs
        SET audit_events_count = (
          SELECT COUNT(*)
          FROM audit_events
          WHERE audit_events.run_id = runs.id
        )
      SQL
    end
  end
end

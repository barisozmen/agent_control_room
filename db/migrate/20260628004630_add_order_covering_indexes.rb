class AddOrderCoveringIndexes < ActiveRecord::Migration[8.1]
  def up
    unless index_exists?(:permission_requests, [ :run_id, :status, :created_at, :id ])
      add_index :permission_requests,
        [ :run_id, :status, :created_at, :id ],
        order: { created_at: :desc, id: :desc },
        name: "index_permission_requests_on_run_status_created_id"
    end

    unless index_exists?(:permission_requests, [ :run_id, :status, :decided_at, :id ])
      add_index :permission_requests,
        [ :run_id, :status, :decided_at, :id ],
        order: { decided_at: :desc, id: :desc },
        name: "index_permission_requests_on_run_status_decided_id"
    end

    unless index_exists?(:passports, [ :run_id, :created_at, :id ])
      add_index :passports,
        [ :run_id, :created_at, :id ],
        name: "index_passports_on_run_created_id"
    end
  end

  def down
    remove_index_if_exists :passports, "index_passports_on_run_created_id"
    remove_index_if_exists :permission_requests, "index_permission_requests_on_run_status_decided_id"
    remove_index_if_exists :permission_requests, "index_permission_requests_on_run_status_created_id"
  end

  private

  def remove_index_if_exists(table_name, index_name)
    remove_index table_name, name: index_name if index_name_exists?(table_name, index_name)
  end
end

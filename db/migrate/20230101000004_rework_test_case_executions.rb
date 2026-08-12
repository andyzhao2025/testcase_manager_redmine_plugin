class ReworkTestCaseExecutions < ActiveRecord::Migration[5.2]
  def up
    add_column :test_case_executions, :status_id, :integer, null: true
    ensure_status('passed', 'Passed', 'passed', 3, '#00aa33', true)
    ensure_status('failed', 'Failed', 'failed', 4, '#dd0000', true)

    execute <<-SQL
      UPDATE test_case_executions
      SET status_id = (SELECT id FROM test_execution_statuses WHERE key = 'passed')
      WHERE status_id IS NULL AND result = TRUE
    SQL
    execute <<-SQL
      UPDATE test_case_executions
      SET status_id = (SELECT id FROM test_execution_statuses WHERE key = 'failed')
      WHERE status_id IS NULL AND result = FALSE
    SQL

    change_column :test_case_executions, :status_id, :integer, null: false
    add_foreign_key :test_case_executions, :test_execution_statuses,
                    column: :status_id, name: 'fk_test_case_executions_status'

    # Rename user -> executor.
    # Note: ActiveRecord's rename_column on PostgreSQL also renames the index
    # covering the old column (index_..._on_user_id -> index_..._on_executor_id),
    # so we must NOT try to add a fresh index on executor_id here -- on PostgreSQL
    # that would raise DuplicateTable. The renamed column stays indexed.
    rename_column :test_case_executions, :user_id, :executor_id
    add_foreign_key :test_case_executions, :users, column: :executor_id,
                    name: 'fk_test_case_executions_executor'

    # Rename issue -> defect_issue (nullable, keep legacy issue relationship optional).
    # No add_index here: rename_column on PostgreSQL already renames the covering
    # index (index_..._on_issue_id -> index_..._on_defect_issue_id).
    rename_column :test_case_executions, :issue_id, :defect_issue_id
    add_foreign_key :test_case_executions, :issues, column: :defect_issue_id,
                    name: 'fk_test_case_executions_defect_issue'

    # New plan-case link, backfilled from existing plan_cases or created on demand.
    add_column :test_case_executions, :test_plan_case_id, :integer, null: true
    backfill_test_plan_case_ids
    add_index :test_case_executions, :test_plan_case_id
    add_foreign_key :test_case_executions, :test_plan_cases, column: :test_plan_case_id,
                    name: 'fk_test_case_executions_plan_case'

    # Automation / CI reserved columns
    add_column :test_case_executions, :automation_source, :string, limit: 64
    add_column :test_case_executions, :external_run_id, :string, limit: 255
    add_column :test_case_executions, :build_url, :text
    add_column :test_case_executions, :duration_seconds, :integer

    # The boolean column is no longer the business truth.
    remove_column :test_case_executions, :result

    add_index :test_case_executions, [:test_plan_id, :test_case_id],
              name: 'index_test_case_executions_on_plan_and_case'
    add_index :test_case_executions, [:test_plan_id, :test_plan_case_id],
              name: 'index_test_case_executions_on_plan_and_plan_case'
    add_index :test_case_executions, [:project_id, :status_id],
              name: 'index_test_case_executions_on_project_and_status'
  end

  def down
    remove_index :test_case_executions, name: 'index_test_case_executions_on_project_and_status'
    remove_index :test_case_executions, name: 'index_test_case_executions_on_plan_and_plan_case'
    remove_index :test_case_executions, name: 'index_test_case_executions_on_plan_and_case'

    remove_column :test_case_executions, :duration_seconds
    remove_column :test_case_executions, :build_url
    remove_column :test_case_executions, :external_run_id
    remove_column :test_case_executions, :automation_source

    remove_foreign_key :test_case_executions, name: 'fk_test_case_executions_plan_case'
    remove_index :test_case_executions, :test_plan_case_id
    remove_column :test_case_executions, :test_plan_case_id

    remove_foreign_key :test_case_executions, name: 'fk_test_case_executions_defect_issue'
    remove_index :test_case_executions, :defect_issue_id
    rename_column :test_case_executions, :defect_issue_id, :issue_id

    remove_foreign_key :test_case_executions, name: 'fk_test_case_executions_executor'
    remove_index :test_case_executions, :executor_id
    rename_column :test_case_executions, :executor_id, :user_id

    add_column :test_case_executions, :result, :boolean, null: false, default: false
    execute <<-SQL
      UPDATE test_case_executions
      SET result = CASE
        WHEN (SELECT key FROM test_execution_statuses WHERE id = test_case_executions.status_id) = 'passed' THEN TRUE
        ELSE FALSE
      END
    SQL

    remove_foreign_key :test_case_executions, name: 'fk_test_case_executions_status'
    remove_column :test_case_executions, :status_id
  end

  private

  # Insert a status row only if no row with that key already exists.
  def ensure_status(key, name, category, position, color, is_final)
    found = select_value("SELECT COUNT(*) FROM test_execution_statuses WHERE key = '#{key}'").to_i
    return if found > 0

    execute <<-SQL
      INSERT INTO test_execution_statuses
        (project_id, key, name, category, position, color, is_default, is_final, created_at, updated_at)
      VALUES
        (NULL, '#{key}', '#{name}', '#{category}', #{position}, '#{color}', FALSE, #{is_final ? 'TRUE' : 'FALSE'},
         CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  # Rebuild each execution's test_plan_case row using anonymous ActiveRecord
  # classes so the backfill works on both PostgreSQL and SQLite without
  # depending on the real model definitions (which may not be loaded / shaped yet).
  def backfill_test_plan_case_ids
    execution_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'test_case_executions'
    end
    plan_case_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'test_plan_cases'
    end

    execution_class.where.not(test_plan_id: nil).where.not(test_case_id: nil).each do |execution|
      plan_id = execution.test_plan_id
      case_id = execution.test_case_id

      plan_case = plan_case_class.find_by(test_plan_id: plan_id, test_case_id: case_id)
      if plan_case.nil?
        max_pos = plan_case_class.where(test_plan_id: plan_id).maximum(:position).to_i
        plan_case = plan_case_class.create!(
          test_plan_id: plan_id,
          test_case_id: case_id,
          position: max_pos + 1
        )
      end
      execution.update_column(:test_plan_case_id, plan_case.id)
    end
  end
end

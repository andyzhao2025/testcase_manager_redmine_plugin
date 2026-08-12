class CreateTestPlanCases < ActiveRecord::Migration[5.2]
  def change
    create_table :test_plan_cases do |t|
      t.references :test_plan, null: false, foreign_key: true, type: :integer, index: false
      t.references :test_case, null: false, foreign_key: true, type: :integer, index: false
      t.integer :position, null: false, default: 0
      t.string :name_snapshot, limit: 255
      t.text :scenario_snapshot
      t.text :expected_snapshot
      t.text :environment_snapshot
      t.timestamps
    end

    add_index :test_plan_cases, [:test_plan_id, :test_case_id], unique: true
    add_index :test_plan_cases, [:test_plan_id, :position], unique: true
  end
end

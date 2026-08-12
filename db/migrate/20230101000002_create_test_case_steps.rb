class CreateTestCaseSteps < ActiveRecord::Migration[5.2]
  def change
    create_table :test_case_steps do |t|
      t.references :test_case, null: false, foreign_key: true, type: :integer, index: false
      t.integer :position, null: false, default: 0
      t.text :action, null: false
      t.text :expected_result, null: false
      t.text :test_data
      t.text :notes
      t.timestamps
    end

    add_index :test_case_steps, [:test_case_id, :position], unique: true
  end
end

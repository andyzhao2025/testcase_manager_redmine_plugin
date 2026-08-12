class EnhanceTestCases < ActiveRecord::Migration[5.2]
  def up
    add_column :test_cases, :case_state, :string, null: false, default: 'draft', limit: 32
    add_column :test_cases, :priority, :string, limit: 32
    add_column :test_cases, :archived_at, :datetime, null: true
    add_column :test_cases, :version, :integer, null: true

    # Ensure every existing test case has at least one structured step.
    # Old case kept scenario/expected; we split them into action / expected_result.
    test_case_class = Class.new(ActiveRecord::Base) { self.table_name = 'test_cases' }
    step_class = Class.new(ActiveRecord::Base) { self.table_name = 'test_case_steps' }

    test_case_class.all.each do |test_case|
      next if step_class.exists?(test_case_id: test_case.id)

      step_class.create!(
        test_case_id: test_case.id,
        position: 1,
        action: test_case.scenario.presence || '',
        expected_result: test_case.expected.presence || '',
      )
    end
  end

  def down
    step_class = Class.new(ActiveRecord::Base) { self.table_name = 'test_case_steps' }
    step_class.delete_all

    remove_column :test_cases, :version
    remove_column :test_cases, :archived_at
    remove_column :test_cases, :priority
    remove_column :test_cases, :case_state
  end
end

class AddTimestampsToTestCases < ActiveRecord::Migration[5.2]
  # The original create_test_cases migration never added created_at/updated_at,
  # so the test_cases table has no timestamps at all. This adds them (nullable
  # first so existing rows can be backfilled) and backfills the current time,
  # then tightens to non-null like Rails' default add_timestamps behavior.
  def up
    add_timestamps :test_cases, null: true

    test_case_class = Class.new(ActiveRecord::Base) { self.table_name = 'test_cases' }
    test_case_class.where(created_at: nil).update_all(created_at: Time.current, updated_at: Time.current)

    change_column :test_cases, :created_at, :datetime, null: false
    change_column :test_cases, :updated_at, :datetime, null: false
  end

  def down
    remove_timestamps :test_cases, null: true
  end
end

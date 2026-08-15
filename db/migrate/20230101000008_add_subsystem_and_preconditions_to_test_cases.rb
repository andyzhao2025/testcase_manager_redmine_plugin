class AddSubsystemAndPreconditionsToTestCases < ActiveRecord::Migration[5.2]
  def change
    # Subsystem / module this test case belongs to (lightweight categorization).
    add_column :test_cases, :subsystem, :string, limit: 255, null: true

    # Free-text preconditions that must hold before the steps can be executed.
    # Unlike test_case_steps (the per-step action/expected slices), this is a
    # single case-level prerequisite description.
    add_column :test_cases, :preconditions, :text, null: true
  end
end

class DropTestCaseTestPlans < ActiveRecord::Migration[5.2]
  def up
    # test_plan_cases replaced test_case_test_plans as the plan<->case join.
    # The old table carried no data beyond the FK skeleton and is no longer
    # referenced by any model or code, so it is safe to remove.
    drop_table :test_case_test_plans
  end

  def down
    # Recreate the join table in its original shape (see
    # 20220322000001_add_test_plans_ref_to_test_cases.rb).
    create_table :test_case_test_plans do |t|
      t.references :test_case, foreign_key: true
      t.references :test_plan, foreign_key: true
    end
  end
end

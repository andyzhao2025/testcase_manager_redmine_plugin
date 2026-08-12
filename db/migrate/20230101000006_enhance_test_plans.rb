class EnhanceTestPlans < ActiveRecord::Migration[5.2]
  def change
    add_column :test_plans, :plan_state, :string, null: false, default: 'draft', limit: 32
    add_column :test_plans, :notes, :text, null: true
    add_reference :test_plans, :source_plan, foreign_key: { to_table: :test_plans },
                   type: :integer, null: true

    # issue_status_id is kept as a deprecated compatibility column but no longer
    # drives the primary test semantics. We do not drop the data.
  end
end

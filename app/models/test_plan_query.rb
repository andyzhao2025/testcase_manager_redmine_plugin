class TestPlanQuery < Query

  self.queried_class = TestPlan
  self.view_permission = :view_test_plans

  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{TestPlan.table_name}.id", :default_order => 'desc', :caption => '#', :frozen => true),
    QueryColumn.new(:name, :sortable => "#{TestPlan.table_name}.name", :caption => :label_test_plans),
    QueryColumn.new(:plan_state, :sortable => "#{TestPlan.table_name}.plan_state"),
    QueryColumn.new(:estimated_bug, :sortable => "#{TestPlan.table_name}.estimated_bug"),
    QueryColumn.new(:user, :sortable => "#{TestPlan.table_name}.user_id"),
    QueryColumn.new(:begin_date, :sortable => "#{TestPlan.table_name}.begin_date"),
    QueryColumn.new(:end_date, :sortable => "#{TestPlan.table_name}.end_date"),
  ]

  def initialize(attributes=nil, *args)
    super attributes
    self.filters ||= { }
  end

  def initialize_available_filters
    add_available_filter "name", :type => :text
    add_available_filter "plan_state", :type => :list, :values => lambda { plan_state_values }
    add_available_filter "begin_date", :type => :date
    add_available_filter "end_date", :type => :date
    add_available_filter "estimated_bug", :type => :integer
    add_available_filter(
      "user_id",
      :type => :list, :values => lambda { author_values }
    )
  end

  def plan_state_values
    [[l(:label_plan_state_draft), "draft"],
     [l(:label_plan_state_ready), "ready"],
     [l(:label_plan_state_running), "running"],
     [l(:label_plan_state_closed), "closed"],
     [l(:label_plan_state_archived), "archived"]]
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns
  end

  def available_display_types
    ['list']
  end

  def getTestPlanConditions
    conditions = [statement]
    unless filters["name"].blank?
      conditions << sql_for_field("name", filters["name"][:operator], filters["name"][:values], TestPlan.table_name, "name")
    end
    unless filters["plan_state"].blank?
      conditions << sql_for_field("plan_state", filters["plan_state"][:operator], filters["plan_state"][:values], TestPlan.table_name, "plan_state")
    end
    unless filters["begin_date"].blank?
      conditions << sql_for_field("begin_date", filters["begin_date"][:operator], filters["begin_date"][:values], TestPlan.table_name, "begin_date")
    end
    unless filters["end_date"].blank?
      conditions << sql_for_field("end_date", filters["end_date"][:operator], filters["end_date"][:values], TestPlan.table_name, "end_date")
    end
    unless filters["estimated_bug"].blank?
      conditions << sql_for_field("estimated_bug", filters["estimated_bug"][:operator], filters["estimated_bug"][:values], TestPlan.table_name, "estimated_bug")
    end
    unless filters["user_id"].blank?
      user_ids = filters["user_id"][:values]
      if user_ids.any? { |user| user == "me" }
        user_ids.delete("me")
        user_ids << User.current.id.to_s
      end
      conditions << sql_for_field("user", filters["user_id"][:operator], user_ids, TestPlan.table_name, "user_id")
    end
    conditions.join(" AND ")
  end

  def base_scope
    TestPlan.visible
      .where(getTestPlanConditions)
  end

  # Specify selected columns by default
  def default_columns_names
    [:id, :name, :plan_state, :estimated_bug, :user, :begin_date, :end_date]
  end

  def default_sort_criteria
    [['id', 'desc']]
  end

  def test_plans(options={})
    order_option = [sort_clause]
    base_scope
      .includes(:test_plan_cases)
      .order(order_option)
      .limit(options[:limit])
      .offset(options[:offset])
  end

  def test_plan_count
    base_scope.count
  end

  # Backward-compat for callers that still use issue_status_id filter.
  def sql_for_issue_status_id_field(field, operator, value)
    sql_for_field(field, operator, value, TestPlan.table_name, "issue_status_id")
  end
end

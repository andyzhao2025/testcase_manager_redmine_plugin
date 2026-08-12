class TestCaseExecutionQuery < Query

  self.queried_class = TestCaseExecution
  self.view_permission = :view_test_case_executions

  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{TestCaseExecution.table_name}.id", :default_order => 'desc', :caption => '#', :frozen => true),
    QueryColumn.new(:test_case, :sortable => "#{TestCaseExecution.table_name}.test_case_id", :caption => :label_test_case),
    QueryColumn.new(:test_plan, :sortable => "#{TestCaseExecution.table_name}.test_plan_id"),
    QueryColumn.new(:status, :sortable => "#{TestCaseExecution.table_name}.status_id"),
    QueryColumn.new(:executor, :sortable => "#{TestCaseExecution.table_name}.executor_id"),
    QueryColumn.new(:defect_issue, :sortable => "#{TestCaseExecution.table_name}.defect_issue_id"),
    QueryColumn.new(:comment, :sortable => "#{TestCaseExecution.table_name}.comment"),
    QueryColumn.new(:scenario, :sortable => "#{TestCase.table_name}.scenario"),
    QueryColumn.new(:expected, :sortable => "#{TestCase.table_name}.expected"),
    TimestampQueryColumn.new(:execution_date, :sortable => "#{TestCaseExecution.table_name}.execution_date", :default_order => 'desc')
  ]

  def initialize(attributes=nil, *args)
    super attributes
    self.filters ||= { }
  end

  def initialize_available_filters
    add_available_filter "test_plan", :type => :text
    add_available_filter "test_case", :type => :text
    add_available_filter(
      "executor_id",
      :type => :list, :values => lambda { author_values }
    )
    add_available_filter(
      "status",
      :type => :list, :values => lambda { status_values }
    )
    add_available_filter "comment", :type => :text
    add_available_filter "execution_date", :type => :date
    add_available_filter "defect_issue_id", :type => :integer, :label => :field_defect_issue
    add_available_filter "scenario", :type => :text
    add_available_filter "expected", :type => :text
  end

  def status_values
    TestExecutionStatus.system.ordered.map { |s| [s.name, s.key] }
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns
  end

  def available_display_types
    ['list']
  end

  def getTestCaseExecutionConditions
    conditions = [statement]
    unless filters["status"].blank?
      conditions << sql_for_status_field(filters["status"][:operator], filters["status"][:values])
    end
    unless filters["executor_id"].blank?
      executor_ids = filters["executor_id"][:values]
      if executor_ids.any? { |user| user == "me" }
        executor_ids.delete("me")
        executor_ids << User.current.id.to_s
      end
      conditions << sql_for_field("executor", filters["executor_id"][:operator], executor_ids, TestCaseExecution.table_name, 'executor_id')
    end
    unless filters["execution_date"].blank?
      conditions << sql_for_field("execution_date", filters["execution_date"][:operator], filters["execution_date"][:values], TestCaseExecution.table_name, 'execution_date')
    end
    unless filters["comment"].blank?
      conditions << sql_for_field("comment", filters["comment"][:operator], filters["comment"][:values], TestCaseExecution.table_name, 'comment')
    end
    unless filters["defect_issue_id"].blank?
      conditions << sql_for_field("defect_issue_id", filters["defect_issue_id"][:operator], filters["defect_issue_id"][:values], TestCaseExecution.table_name, 'defect_issue_id')
    end
    conditions.join(" AND ")
  end

  def base_scope
    TestCaseExecution.visible.joins(:test_case, :test_plan)
      .includes(:status, :executor)
      .where(getTestCaseExecutionConditions)
  end

  # Specify selected columns by default
  def default_columns_names
    [:id, :test_plan, :test_case, :scenario, :expected, :status, :executor, :execution_date, :comment, :defect_issue]
  end

  def default_sort_criteria
    [['id', 'test_case', 'test_plan', 'desc']]
  end

  # Valid options:
  #   :test_plan_id :test_case_id :limit :offset
  def test_case_executions(options={})
    order_option = [sort_clause]
    conditions = []
    if options[:test_plan_id]
      conditions << sql_for_field("id", "=", [options[:test_plan_id]], TestPlan.table_name, 'id')
    end
    if options[:test_case_id]
      conditions << sql_for_field("id", "=", [options[:test_case_id]], TestCase.table_name, 'id')
    end
    base_scope()
      .where(conditions.join(" AND "))
      .order(order_option)
      .limit(options[:limit])
      .offset(options[:offset])
      .select("test_case_executions.*, test_cases.scenario, test_cases.expected")
  end

  def test_case_execution_count
    base_scope.count
  end

  def sql_for_status_field(operator, value)
    keys = Array(value)
    status_ids = TestExecutionStatus.system.where(key: keys).pluck(:id)
    case operator
    when "="
      status_ids.any? ? "#{TestCaseExecution.table_name}.status_id IN (#{status_ids.join(',')})" : "1=0"
    when "!"
      status_ids.any? ? "#{TestCaseExecution.table_name}.status_id NOT IN (#{status_ids.join(',')})" : "1=1"
    when "*"
      "1=1"
    when "!*"
      "#{TestCaseExecution.table_name}.status_id IS NULL"
    else
      "1=0"
    end
  end

  # Backward-compat with legacy result filter
  def sql_for_result_field(operator, value)
    passed_ids = TestExecutionStatus.system.where(key: 'passed').pluck(:id)
    failed_ids = TestExecutionStatus.system.where(key: 'failed').pluck(:id)
    case operator
    when "="
      if Array(value).include?('true')
        "#{TestCaseExecution.table_name}.status_id IN (#{(passed_ids + failed_ids).join(',')})"
      else
        "#{TestCaseExecution.table_name}.status_id IN (#{failed_ids.join(',')})"
      end
    when "!"
      if Array(value).include?('true')
        "#{TestCaseExecution.table_name}.status_id NOT IN (#{passed_ids.join(',')})"
      else
        "#{TestCaseExecution.table_name}.status_id NOT IN (#{failed_ids.join(',')})"
      end
    else
      "1=0"
    end
  end

  # override default statement for test_plan
  def sql_for_test_plan_field(field, operator, value)
    sql_for_field("test_plan", filters["test_plan"][:operator], filters["test_plan"][:values], TestPlan.table_name, 'name')
  end

  # override default statement for test_case
  def sql_for_test_case_field(field, operator, value)
    sql_for_field("test_case", filters["test_case"][:operator], filters["test_case"][:values], TestCase.table_name, 'name')
  end

  # override default statement for scenario
  def sql_for_scenario_field(field, operator, value)
    sql_for_field("scenario", filters["scenario"][:operator], filters["scenario"][:values], TestCase.table_name, 'scenario')
  end

  # override default statement for expected
  def sql_for_expected_field(field, operator, value)
    sql_for_field("expected", filters["expected"][:operator], filters["expected"][:values], TestCase.table_name, 'expected')
  end
end

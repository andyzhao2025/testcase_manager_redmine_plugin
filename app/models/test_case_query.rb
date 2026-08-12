class TestCaseQuery < Query

  self.queried_class = TestCase
  self.view_permission = :view_test_cases

  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{TestCase.table_name}.id", :default_order => 'desc', :caption => '#', :frozen => true),
    QueryColumn.new(:name, :sortable => "#{TestCase.table_name}.name", :caption => :label_test_case),
    QueryColumn.new(:user, :sortable => "#{TestCase.table_name}.user_id"),
    QueryColumn.new(:case_state, :sortable => "#{TestCase.table_name}.case_state"),
    QueryColumn.new(:priority, :sortable => "#{TestCase.table_name}.priority"),
    QueryColumn.new(:environment, :sortable => "#{TestCase.table_name}.environment"),
    QueryColumn.new(:latest_status, :sortable => "latest_status"),
    QueryColumn.new(:latest_execution_date, :sortable => "latest_execution_date"),
    QueryColumn.new(:scenario, :sortable => "#{TestCase.table_name}.scenario"),
    QueryColumn.new(:expected, :sortable => "#{TestCase.table_name}.expected")
  ]

  def initialize(attributes=nil, *args)
    super attributes
    self.filters ||= { }
  end

  def initialize_available_filters
    add_available_filter "name", :type => :text
    add_available_filter "case_state", :type => :list, :values => lambda { case_state_values }
    add_available_filter "priority", :type => :list, :values => lambda { priority_values }
    add_available_filter "environment", :type => :text
    add_available_filter(
      "user_id",
      :type => :list, :values => lambda { author_values }
    )
    add_available_filter(
      "latest_status",
      :type => :list, :values => lambda { status_values }
    )
    add_available_filter "latest_execution_date", :type => :date
    add_available_filter "scenario", :type => :text
    add_available_filter "expected", :type => :text
  end

  def available_columns
    return @available_columns if @available_columns
    @available_columns = self.class.available_columns.dup
    @available_columns
  end

  def available_display_types
    ['list']
  end

  def case_state_values
    [[l(:label_case_state_draft), "draft"],
     [l(:label_case_state_active), "active"],
     [l(:label_case_state_deprecated), "deprecated"],
     [l(:label_case_state_archived), "archived"]]
  end

  def priority_values
    [[l(:label_priority_low), "low"],
     [l(:label_priority_normal), "normal"],
     [l(:label_priority_high), "high"],
     [l(:label_priority_urgent), "urgent"]]
  end

  def status_values
    TestExecutionStatus.system.ordered.map { |s| [s.name, s.key] }
  end

  def getTestCaseConditions
    conditions = [statement]
    unless filters["name"].blank?
      conditions << sql_for_field("name", filters["name"][:operator], filters["name"][:values], TestCase.table_name, "name")
    end
    unless filters["case_state"].blank?
      conditions << sql_for_field("case_state", filters["case_state"][:operator], filters["case_state"][:values], TestCase.table_name, "case_state")
    end
    unless filters["priority"].blank?
      conditions << sql_for_field("priority", filters["priority"][:operator], filters["priority"][:values], TestCase.table_name, "priority")
    end
    unless filters["user_id"].blank?
      user_ids = filters["user_id"][:values]
      if user_ids.any? { |user| user == "me" }
        user_ids.delete("me")
        user_ids << User.current.id.to_s
      end
      conditions << sql_for_field("user", filters["user_id"][:operator], user_ids, TestCase.table_name, "user_id")
    end
    unless filters["environment"].blank?
      conditions << sql_for_field("environment", filters["environment"][:operator], filters["environment"][:values], TestCase.table_name, "environment")
    end
    unless filters["scenario"].blank?
      conditions << sql_for_field("scenario", filters["scenario"][:operator], filters["scenario"][:values], TestCase.table_name, "scenario")
    end
    unless filters["expected"].blank?
      conditions << sql_for_field("expected", filters["expected"][:operator], filters["expected"][:values], TestCase.table_name, "expected")
    end
    conditions.join(" AND ")
  end

  # Conditions that reference the derived latest_tce alias; only valid once the
  # latest-execution join is present.
  def latest_execution_conditions
    return "1=1" if filters["latest_status"].blank? && filters["latest_execution_date"].blank?

    parts = []
    if filters["latest_status"].present?
      parts << sql_for_latest_status_field("latest_status", filters["latest_status"][:operator], filters["latest_status"][:values])
    end
    if filters["latest_execution_date"].present?
      parts << sql_for_latest_execution_date_field("latest_execution_date", filters["latest_execution_date"][:operator], filters["latest_execution_date"][:values])
    end
    parts.join(" AND ")
  end

  def base_scope
    TestCase.visible
      .where(getTestCaseConditions)
  end

  # Specify selected columns by default
  def default_columns_names
    [:id, :name, :case_state, :priority, :latest_status, :latest_execution_date, :environment, :user]
  end

  def default_sort_criteria
    [['id', 'desc']]
  end

  def sort_clause
    if clause = sort_criteria.sort_clause(sortable_columns)
      clause.map {|c|
        nocase_sql = if ApplicationRecord.connection.adapter_name =~ /sqlite/i
                       nocase_columns = ["name", "environment", "scenario", "expected"].select { |col| c.start_with?("#{TestCase.table_name}.#{col}") }
                       unless nocase_columns.empty?
                         column = nocase_columns.first
                         if c.end_with?("ASC")
                           Arel.sql "#{TestCase.table_name}.#{column} COLLATE NOCASE ASC"
                         else
                           Arel.sql "#{TestCase.table_name}.#{column} COLLATE NOCASE DESC"
                         end
                       else
                         Arel.sql c
                       end
                     else
                       Arel.sql c
                     end
        nocase_sql
      }
    end
  end

  def test_cases(options={})
    order_option = [sort_clause]
    conditions = []
    if options[:test_plan_id]
      conditions << sql_for_field("id", "=", [options[:test_plan_id]], "test_plan_cases", 'test_plan_id')
    end

    scope = base_scope
    if options[:test_plan_id]
      scope = scope
        .joins(:test_plan_cases)
        .joins(test_plan_case_latest_execution_join(options[:test_plan_id]))
        .where(conditions.join(" AND "))
    else
      scope = scope.joins(test_plan_case_latest_execution_join(nil))
    end

    scope
      .where(latest_execution_conditions)
      .select(test_case_select_sql)
      .order(order_option)
      .limit(options[:limit])
      .offset(options[:offset])
  end

  def test_case_count(test_plan_id=nil, for_count=false)
    scope = base_scope
    if test_plan_id
      scope = scope
        .joins(:test_plan_cases)
        .joins(test_plan_case_latest_execution_join(test_plan_id))
        .where(sql_for_field("id", "=", [test_plan_id], "test_plan_cases", 'test_plan_id'))
    else
      scope = scope.joins(test_plan_case_latest_execution_join(nil))
    end
    scope = scope.where(latest_execution_conditions)
    Redmine::Database.postgresql? ? scope.count("test_cases.id") : scope.count
  end

  # Latest execution join: one row per test_case, the most recent execution
  # (optionally scoped to a test plan). Status is carried back via status_id.
  def test_plan_case_latest_execution_join(test_plan_id)
    where_sql = test_plan_id ? "WHERE tce.test_plan_id = #{TestPlan.connection.quote(test_plan_id)}" : ''
    Arel.sql(<<-SQL)
      LEFT JOIN (
        SELECT tce.test_case_id, tce.status_id, tce.execution_date, tce.id AS execution_id
        FROM (
          SELECT *,
                 ROW_NUMBER() OVER (
                   PARTITION BY test_case_id
                   ORDER BY execution_date desc, id desc
                 ) AS row_number_per_test_case_id
          FROM test_case_executions tce
          #{where_sql}
        ) tce
        WHERE tce.row_number_per_test_case_id = 1
      ) latest_tce ON latest_tce.test_case_id = test_cases.id
    SQL
  end

  def test_case_select_sql
    <<-SQL
      test_cases.*,
      latest_tce.execution_id AS latest_execution_id,
      latest_tce.status_id AS latest_status_id,
      latest_tce.execution_date AS latest_execution_date
    SQL
  end

  # Backward-compat: expose the latest result as a boolean derived from status,
  # in case any view or CSV exporter still references :latest_result.
  def sql_for_latest_result_field(field, operator, value)
    sql_for_latest_status_field(field, operator, value)
  end

  def sql_for_latest_status_field(field, operator, value)
    keys = Array(value)
    case operator
    when "="
      known = TestExecutionStatus.where(key: keys).pluck(:id)
      "latest_tce.status_id IN (#{known.join(',')})"
    when "!"
      known = TestExecutionStatus.where(key: keys).pluck(:id)
      "latest_tce.status_id NOT IN (#{known.join(',')}) OR latest_tce.status_id IS NULL"
    when "*"
      "1=1"
    when "!*"
      "latest_tce.status_id IS NULL"
    else
      "1=0"
    end
  end

  def sql_for_latest_execution_date_field(field, operator, value)
    db_table = "latest_tce"
    db_field = "execution_date"
    case operator
    when "="
      date_clause(db_table, db_field, parse_date(value.first), parse_date(value.first), false)
    when ">="
      date_clause(db_table, db_field, parse_date(value.first), nil, false)
    when "<="
      date_clause(db_table, db_field, nil, parse_date(value.first), false)
    when "><"
      date_clause(db_table, db_field, parse_date(value.first), parse_date(value.last), false)
    when "t"
      date_clause(db_table, db_field, User.current.today, User.current.today, false)
    when "w"
      # this week
      first_day_of_week = l(:general_first_day_of_week).to_i
      day_of_week = User.current.today.cwday
      days_ago = if day_of_week >= first_day_of_week
                   day_of_week - first_day_of_week
                 else
                   day_of_week + 7 - first_day_of_week
                 end
      date_clause(db_table, db_field, User.current.today - days_ago, User.current.today - days_ago + 6, false)
    when "lw"
      # last week
      first_day_of_week = l(:general_first_day_of_week).to_i
      day_of_week = User.current.today.cwday
      days_ago = if day_of_week >= first_day_of_week
                   day_of_week - first_day_of_week
                 else
                   day_of_week + 7 - first_day_of_week
                 end
      date_clause(db_table, db_field, User.current.today - days_ago - 7, User.current.today - days_ago - 1, false)
    when "m"
      date_clause(db_table, db_field, User.current.today.beginning_of_month, User.current.today.end_of_month, false)
    when "lm"
      date_clause(db_table, db_field, User.current.today.prev_month.beginning_of_month, User.current.today.prev_month.end_of_month, false)
    when "y"
      date_clause(db_table, db_field, User.current.today.beginning_of_year, User.current.today.end_of_year, false)
    when "!*"
      "#{db_table}.#{db_field} IS NULL"
    when "*"
      "1=1"
    else
      "1=1"
    end
  end
end

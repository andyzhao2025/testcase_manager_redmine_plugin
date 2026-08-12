# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

# --- Plugin fixture support --------------------------------------------------
# Redmine discovers fixtures only under its own test/fixtures dir, so this
# plugin's own fixture files (test_plans/test_cases/test_case_executions/
# test_plan_cases) are not auto-discovered. Rails 6.1's ActiveSupport::TestCase
# only supports a single string `fixture_path` (the host dir). Each plugin test
# class still *declares* these plugin tables via `fixtures :test_plans, ...`
# (so `setup_fixture_accessors` generates the test_plans/test_cases/... accessor
# methods and the table names stay registered in `fixture_table_names`), but the
# fixture DATA is read from the plugin's own fixtures dir instead of the host
# dir. We override `load_fixtures` so that:
#   * core table names (projects, users, ...) -> host fixture_path (unchanged)
#   * plugin table names (test_plans, ...)     -> PLUGIN_FIXTURE_DIR
# Both are merged into the single `@loaded_fixtures` hash the accessors consume,
# and core fixtures are loaded before plugin fixtures.

require 'active_record/fixtures'
PLUGIN_FIXTURE_DIR = File.expand_path('../fixtures', __FILE__)
# Table names as they appear in `fixture_table_names` (Rails stores them as strings).
PLUGIN_FIXTURE_TABLES = ["test_plans", "test_cases", "test_case_executions", "test_plan_cases", "test_execution_statuses"]

# Import CSV fixtures shipped with this plugin live under the PLUGIN's own
# test/fixtures/files directory. Redmine 5.1 (Rails 6.1) only resolves uploaded
# test files from the HOST app's test/fixtures/files, so import tests that call
# `uploaded_test_file("test_cases.csv", "text/csv")` fail to find them. Override
# `uploaded_test_file` so plugin CSVs resolve from the plugin dir, while any other
# path still resolves via the host's default mechanism.
PLUGIN_FILES_DIR = File.expand_path('../fixtures/files', __FILE__)

# The host `ActiveSupport::TestCase#uploaded_test_file` resolves relative to the
# host `fixture_path`, so plugin CSVs would not be found. Override it on the
# class so plugin import tests resolve their files from the plugin dir.
class ActiveSupport::TestCase
  def uploaded_test_file(name, mime)
    plugin_path = File.join(PLUGIN_FILES_DIR, name.to_s)
    if File.exist?(plugin_path)
      Rack::Test::UploadedFile.new(plugin_path, mime, true)
    else
      super
    end
  end
end

module TestCaseManagementFixtureLoader
  # test_execution_statuses is a dependency of the other plugin tables (they
  # reference it by integer status_id) and not every test class lists it in its
  # own fixtures declaration, so load it whenever any plugin table is requested.
  STATUS_DEPENDENCY = ["test_execution_statuses"].freeze

  def load_fixtures(config = ActiveRecord::Base)
    declared_tables = Array(fixture_table_names)
    plugin_tables = PLUGIN_FIXTURE_TABLES & declared_tables
    if plugin_tables.any?
      plugin_tables = (plugin_tables + STATUS_DEPENDENCY).uniq
    end
    core_tables = declared_tables - PLUGIN_FIXTURE_TABLES

    loaded = []
    if core_tables.any?
      loaded.concat(ActiveRecord::FixtureSet.create_fixtures(
        fixture_path, core_tables, fixture_class_names, config))
    end
    if plugin_tables.any?
      loaded.concat(ActiveRecord::FixtureSet.create_fixtures(
        PLUGIN_FIXTURE_DIR, plugin_tables, fixture_class_names, config))
    end
    loaded.index_by(&:name)
  end
end

ActiveSupport::TestCase.prepend(TestCaseManagementFixtureLoader)

def assert_flash_error(message)
  assert_equal message, flash[:error]
  assert_select "div#flash_error" do |div|
    assert_equal message, div.text
  end
end

def assert_contextual_link(label, path)
  assert_select "div#content div.contextual a:first-child" do |a|
    assert_equal path, a.first.attributes["href"].text
    assert_equal label, a.text
  end
end

def assert_back_to_lists_link(path)
  assert_select "div#content a" do |a|
    assert_equal path, a.first.attributes["href"].text
    assert_equal I18n.t(:label_back_to_lists), a.text
  end
end

# For backward compatibility with Redmine < 6.0.
# ActiveRecord.default_timezone is available in Rails 7.0+.
def configure_default_timezone(timezone)
  if ActiveRecord.respond_to?(:default_timezone)
    ActiveRecord.default_timezone = timezone
  else
    ActiveRecord::Base.default_timezone = timezone
  end
end

def generate_user_with_permissions(
      projects,
      permissions=[
        :view_project, :view_issues, :add_issues, :edit_issues, :delete_issues,
        :view_test_cases, :add_test_cases, :edit_test_cases, :delete_test_cases,
        :view_test_plans, :add_test_plans, :edit_test_plans, :delete_test_plans,
        :view_test_case_executions, :add_test_case_executions, :edit_test_case_executions, :delete_test_case_executions,
      ]
    )
  projects = [projects] if projects.is_a?(Project)
  permissions = [permissions] unless permissions.is_a?(Array)
  @role = Role.generate!(permissions: permissions.uniq)
  @user = User.generate!(login: "temp_user_#{User.count + 1}", password: "password")
  projects.each do |project|
    User.add_to_project(@user, project, @role)
  end
end

def activate_module_for_projects(projects = Project.all)
  projects.each do |project|
    project.enabled_module_names += ["testcase_management"]
    project.save!
  end
end

def login_as_allowed_with_permissions(projects, permissions = [])
  test_case_management_permissions = [
    :view_test_cases, :add_test_cases, :edit_test_cases, :delete_test_cases,
    :view_test_plans, :add_test_plans, :edit_test_plans, :delete_test_plans,
    :view_test_case_executions, :add_test_case_executions, :edit_test_case_executions, :delete_test_case_executions,
  ]
  generate_user_with_permissions(projects, (permissions + test_case_management_permissions).uniq)
  @request.session[:user_id] = @user.id
end

def login_with_permissions(projects, permissions)
  generate_user_with_permissions(projects, permissions)
  @request.session[:user_id] = @user.id
end

def assert_not_select(selector, options = {})
  assert_select selector,
                options.merge({ count: 0 }),
                "unexpectedly exist something matching to the selector: ${selector}"
end

def assert_successfully_imported(import)
  failures = []
  import.unsaved_items.each_with_index do |item, index|
    failures << "#{item.position}: #{item.message}"
  end
  assert_equal [], failures
end

def generate_test_cases(count, params={})
  count.times.collect do |index|
    TestCase.create!({
      name: "tc#{index}",
      scenario: "scenario",
      expected: "expected",
      environment: "Debian GNU/Linux",
      project: projects(:projects_001),
      user: users(:users_001),
    }.merge(params))
  end
end

def generate_test_case(params={})
  generate_test_cases(1, params).first
end

def generate_test_plans(count, params={})
  count.times.collect do |index|
    TestPlan.create!({
      name: "tp#{index}",
      project: projects(:projects_001),
      user: users(:users_001),
      plan_state: "draft",
    }.merge(params))
  end
end

def generate_test_plan(params={})
  generate_test_plans(1, params).first
end

def generate_test_case_executions(count, params={})
  count.times.collect do |index|
    TestCaseExecution.create!({
      comment: "tce#{index}",
      project: projects(:projects_001),
      executor: users(:users_001),
      status: TestExecutionStatus.canonical("passed"),
      execution_date: "2022-04-21",
    }.merge(params))
  end
end

def generate_test_case_execution(params={})
  generate_test_case_executions(1, params).first
end

def move_test_cases_to_project(project_id)
  TestCaseExecution.all.each do |test_case_execution|
    test_case_execution.update!(project_id: project_id)
  end
  TestCase.all.each do |test_case|
    test_case.update!(project_id: project_id)
  end
  TestPlan.all.each do |test_plan|
    test_plan.update!(project_id: project_id)
  end
end

def filter_params(project_id, field, operation, values, columns)
  filters = {
    project_id: project_id,
    set_filter: 1,
    f: [field],
    op: {
      "#{field}" => operation
    },
    v: values,
    c: columns
  }
  filters
end

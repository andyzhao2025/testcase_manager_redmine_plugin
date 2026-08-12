module ApplicationsHelper
  def find_project(id_or_identifier)
    begin
      @project = Project.find(id_or_identifier)
    rescue ArgumentError
      @project = project = Project.find(:identifier => id_or_identifier).first
    end
  end

  def prepare_issue_status_candidates
    @issue_status_candidates = {}
    IssueStatus.all.each do |issue_status|
      @issue_status_candidates[issue_status.name] = issue_status.id
    end
  end

  def prepare_test_plan_candidates
    @test_plan_candidates = {}
    TestPlan.all.each do |test_plan|
      @test_plan_candidates[test_plan.name] = test_plan.id
    end
  end

  def prepare_user_candidates
    @user_candidates = {}
    if @project
      users = @project.users
    else
      users = User.all
    end
    users.each do |user|
      @user_candidates[user.name] = user.id
    end
  end

  def prepare_status_candidates
    @status_candidates = {}
    TestExecutionStatus.system.ordered.each do |status|
      @status_candidates[status.name] = status.id
    end
  end

  def status_candidates_for_select
    TestExecutionStatus.system.ordered.map { |s| [s.name, s.id] }
  end

  # TestPlan lifecycle states (plan-state machine), ordered as the user sees them.
  def plan_state_options
    %w[draft ready running closed archived].map do |state|
      [l("label_plan_state_#{state}", default: state), state]
    end
  end

  # TestCase authoring lifecycle states.
  def case_state_options
    TestCase::CASE_STATES.map do |state|
      [l("label_case_state_#{state}", default: state), state]
    end
  end

  def yyyymmdd_date(date, separator="/")
    if date
      date.strftime("%Y#{separator}%m#{separator}%d")
    else
      "-"
    end
  end

  def find_project_id
    @project = find_project(params.permit(:project_id)[:project_id])
    raise ActiveRecord::RecordNotFound unless @project
    true
  rescue ActiveRecord::RecordNotFound
    flash.now[:error] = l(:error_project_not_found)
    render 'forbidden', status: 404
    false
  end

  def find_test_plan_id
    @test_plan_given = true
    @test_plan = TestPlan.find_by(id: params.permit(:test_plan_id)[:test_plan_id])
    unless @test_plan
      flash.now[:error] = l(:error_test_plan_not_found)
      render 'forbidden', status: 404
      return false
    end
    true
  end

  def find_test_plan_id_if_given
    if params[:test_plan_id].present?
      @test_plan_given = true
      find_test_plan_id
    else
      @test_plan_given = false
      @test_plan = nil
      true
    end
  end

  def find_test_plan
    @test_plan = TestPlan.find_by(id: params.permit(:id)[:id])
    unless @test_plan
      flash.now[:error] = l(:error_test_plan_not_found)
      render 'forbidden', status: 404
      return false
    end
    true
  end

  def find_test_case_id
    @test_case_given = true
    @test_case = TestCase.find_by(id: params.permit(:test_case_id)[:test_case_id])
    unless @test_case
      flash.now[:error] = l(:error_test_case_not_found)
      render 'forbidden', status: 404
      return false
    end
    true
  end

  def find_test_case_id_if_given
    if params[:test_case_id].present?
      @test_case_given = true
      find_test_case_id
    else
      @test_case_given = false
      @test_case = nil
      true
    end
  end

  def find_test_case
    @test_case = TestCase.find_by(id: params.permit(:id)[:id])
    unless @test_case
      flash.now[:error] = l(:error_test_case_not_found)
      render 'forbidden', status: 404
      return false
    end
    true
  end

  def find_test_cases
    # Used via context menu
    @test_cases = TestCase.where(id: params[:id] || params[:ids])
    raise ActiveRecord::RecordNotFound if @test_cases.empty?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_test_case_executions
    # Used via context menu
    @test_case_executions = TestCaseExecution.where(id: params[:id] || params[:ids])
    raise ActiveRecord::RecordNotFound if @test_case_executions.empty?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_test_plans
    # Used via context menu
    @test_plans = if params[:id] || params[:ids]
                    TestPlan.where(id: params[:id] || params[:ids])
                  else
                    find_project_id
                    TestPlan.where(project_id: @project.id)
                  end
    raise ActiveRecord::RecordNotFound if @test_plans.empty?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Primary authorization for the plugin's own operations. The plugin's own
  # permissions (view/edit/add/delete_test_*) are authoritative; the Redmine
  # issue permission is no longer a precondition for the core test workflows.
  def authorize_with_issues_permission(controller = params[:controller], action = params[:action], global = false)
    testcase_allowed = User.current.allowed_to?({controller: controller, action: action}, @project || @projects, :global => global)
    activated = !@project || @project.allows_to?(controller: controller, action: action)
    if testcase_allowed and activated
      true
    else
      if @project && @project.archived?
        @archived_project = @project
        render_403 :message => :notice_not_authorized_archived_project
      elsif !activated
        # Project module is disabled
        render_403
      else
        deny_access
      end
      false
    end
  end

  # Compatibility alias kept so existing call sites continue to compile.
  alias authorize_testcase_permission authorize_with_issues_permission

  # Issue permission is only needed for the optional defect/project linking
  # features (creating/attaching a Redmine issue to an execution).
  def authorize_issue_linking!
    unless User.current.allowed_to?(:add_issues, @project || @projects, global: false)
      deny_access
      return false
    end
    true
  end

  def related_issues_action(action)
    case action.to_sym
    when :auto_complete, :statistics, :show_context_menu, :list_context_menu
      :index
    when :assign_test_case, :unassign_test_case, :bulk_edit
      :edit
    when :bulk_update
      :update
    when :bulk_delete
      :destroy
    else
      action
    end
  end

  def column_truncated_text(text, limit: -1, truncate_line: true)
    contents = nil
    text.split("\n", limit).each do |line|
      unless contents
        contents = if truncate_line
                     content_tag("p", truncate(line))
                   else
                     content_tag("p", line)
                   end
      else
        contents += if truncate_line
                      content_tag("p", truncate(line))
                    else
                      content_tag("p", line)
                    end
      end
    end
    contents
  end
end

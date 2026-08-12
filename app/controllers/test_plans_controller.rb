class TestPlansController < ApplicationController

  include ApplicationsHelper

  before_action :find_project_id
  before_action :find_test_plan, :only => [:show, :edit, :update, :destroy]
  before_action :find_test_plan_id, :only => [:assign_test_case, :unassign_test_case]
  before_action :find_test_cases, :only => [:show_context_menu, :unassign_test_case]
  before_action :authorize_with_issues_permission
  before_action :find_test_plans, :only => [:list_context_menu, :bulk_edit, :bulk_update, :bulk_delete]

  before_action do
    prepare_user_candidates
    prepare_status_candidates
    if @project
      @source_plans = TestPlan.where(project_id: @project.id).where.not(id: @test_plan&.id).to_a
    else
      @source_plans = TestPlan.none
    end
  end

  helper :queries
  include QueriesHelper
  helper :test_plans_queries
  include TestPlansQueriesHelper
  helper :context_menus

  # GET /projects/:project_id/test_plans
  def index
    retrieve_query(TestPlanQuery, false)

    if @query.valid?
      respond_to do |format|
        @test_plans_export_limit = Setting.plugin_testcase_management["test_plans_export_limit"].to_i
        format.html do
          @test_plan_count = @query.test_plan_count
          @test_plan_pages = Paginator.new @test_plan_count, per_page_option, params["page"]
          test_plans_params = {offset: @test_plan_pages.offset,
                               limit: @test_plan_pages.per_page}
          if params[:test_case_id].present?
            test_plans_params[:test_case_id] = params[:test_case_id]
          end
          @test_plans = @query.test_plans(test_plans_params).visible
          @title = html_title(l(:label_test_plans))
          @csv_url = project_test_plans_path(@project, format: "csv")
        end
        format.csv do
          test_plans_params = {limit: @test_plans_export_limit}
          if params[:test_case_id].present?
            test_plans_params[:test_case_id] = params[:test_case_id]
          end
          @test_plans = @query.test_plans(test_plans_params).visible
          send_data(query_to_csv(@test_plans, @query, params[:csv]),
                    :type => 'text/csv; header=present', :filename => 'test_plans.csv')
        end
      end
    else
      flash.now[:error] = l(:error_index_failure)
      render 'forbidden', status: :unprocessable_entity
    end
  end

  # GET /projects/:project_id/test_plans/:id
  def show
    @test_case_case_add = TestPlanCase.new

    @title = html_title("##{@test_plan.id} #{@test_plan.name}", l(:label_test_plans))

    # Ordered plan-cases, each with its current (or derived) execution status.
    @test_plan_cases = @test_plan.test_plan_cases
      .includes(:test_case, test_case_execution: :status)
      .to_a

    # Statuses offered in the per-row quick-status dropdown.
    @statuses = TestExecutionStatus.system.ordered.to_a

    # Summary statistics across this plan's cases by status key.
    @status_summary = Hash.new(0)
    @test_plan_cases.each do |tpc|
      key = tpc.execution_status_key
      @status_summary[key] += 1
    end
    @progress = @test_plan_cases.empty? ? 0 :
      ((@test_plan_cases.sum { |tpc| tpc.execution_status&.is_final ? 1 : 0 }.to_f / @test_plan_cases.size) * 100).round
  end

  # GET /projects/:project_id/test_plans/:id/edit
  def edit
    @title = html_title("#{l(:label_test_plan_edit)} ##{@test_plan.id}")
  end

  # PUT /projects/:project_id/test_plans/:id
  def update
    raise ::Unauthorized unless @test_plan.editable?
    update_params = {}
    update_params[:name] = test_plan_params[:name]
    update_params[:begin_date] = test_plan_params[:begin_date]
    update_params[:end_date] = test_plan_params[:end_date]
    update_params[:estimated_bug] = test_plan_params[:estimated_bug]
    update_params[:plan_state] = test_plan_params[:plan_state] if test_plan_params[:plan_state].present?
    update_params[:notes] = test_plan_params[:notes] if test_plan_params.key?(:notes)
    if test_plan_params[:source_plan_id].present?
      update_params[:source_plan_id] = test_plan_params[:source_plan_id].to_i
    end
    if test_plan_params[:user].present?
      user = User.find(test_plan_params[:user])
      update_params[:user_id] = user.id
    end
    if @test_plan.update(update_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_test_plan_path
    else
      flash.now[:error] = l(:error_update_failure)
      render :edit
    end
  end

  # GET /projects/:project_id/test_plans/new
  def new
    @test_plan = TestPlan.new
    @title = html_title(l(:label_test_plan_new))
  end

  # POST /projects/:project_id/test_plans
  def create
    @test_plan = TestPlan.new(:project_id => @project.id)
    @test_plan.safe_attributes = {
      name: test_plan_params[:name],
      begin_date: test_plan_params[:begin_date],
      end_date: test_plan_params[:end_date],
      plan_state: (test_plan_params[:plan_state].presence || @test_plan.plan_state.presence || 'draft'),
      notes: test_plan_params[:notes],
      estimated_bug: test_plan_params[:estimated_bug]
    }
    @test_plan.user = User.find(test_plan_params[:user].to_i) if test_plan_params[:user].present?
    if test_plan_params[:source_plan_id].present?
      @test_plan.source_plan_id = test_plan_params[:source_plan_id].to_i
    end
    if test_plan_params[:issue_status].present?
      issue_status = IssueStatus.find_by(id: test_plan_params[:issue_status].to_i)
      @test_plan.issue_status = issue_status if issue_status
    end
    if @test_plan.valid?
      @test_plan.save
      # Copy cases from source plan if a template was selected
      copy_cases_from_source if @test_plan.source_plan_id
      flash[:notice] = l(:notice_successful_create)
      if params[:continue]
        redirect_to new_project_test_plan_path(@project)
      else
        redirect_to project_test_plan_path(:id => @test_plan.id)
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def copy_cases_from_source
    source = TestPlan.find_by(id: @test_plan.source_plan_id)
    return unless source
    source.test_plan_cases.order(:position).each do |tpc|
      @test_plan.test_plan_cases.create!(
        test_case_id: tpc.test_case_id,
        position: @test_plan.test_plan_cases.size + 1,
        name_snapshot: tpc.name_snapshot,
        scenario_snapshot: tpc.scenario_snapshot,
        expected_snapshot: tpc.expected_snapshot,
        environment_snapshot: tpc.environment_snapshot
      )
    end
  end

  public

  # DELETE /projects/:project_id/test_plans/:id
  def destroy
    raise ::Unauthorized unless @test_plan.deletable?
    begin
      if @test_plan.destroy
        flash[:notice] = l(:notice_successful_delete)
        redirect_to project_test_plans_path
      else
        flash.now[:error] = l(:error_delete_failure)
        render :show
      end
    rescue
      flash.now[:error] = l(:error_test_plan_not_found)
      render 'forbidden', status: 404
    end
  end

  # POST /projects/:project_id/test_plans/:test_plan_id/assign_test_case
  def assign_test_case
    begin
      @test_case = TestCase.find(params.require(:test_plan_case).permit(:test_case_id)[:test_case_id])
      raise ActiveRecord::RecordNotFound unless @test_case.visible?
      raise ActiveRecord::RecordNotFound unless @test_plan.visible?
      @test_plan_case = TestPlanCase.where(test_plan: @test_plan,
                                           test_case: @test_case).first
      unless @test_plan_case
        TestPlanCase.create!(
          test_plan: @test_plan,
          test_case: @test_case,
          position: (@test_plan.test_plan_cases.maximum(:position) || 0) + 1
        )
        flash[:notice] = l(:notice_successful_update)
      end
      redirect_to project_test_plan_path(id: @test_plan.id)
    rescue ActiveRecord::RecordNotFound
      flash[:error] = l(:error_test_case_not_found) unless @test_case
      redirect_to project_test_plan_path(id: @test_plan.id)
    rescue
      render 'forbidden', status: 404
    end
  end

  # DELETE /projects/:project_id/test_plans/:test_plan_id/assign_test_case/:id
  # DELETE /projects/:project_id/test_plans/:test_plan_id/assign_test_case/?ids[]=ID1&ids[]=ID2 ...
  def unassign_test_case
    begin
      raise ActiveRecord::RecordNotFound unless @test_cases.all?(&:visible?)
      raise ActiveRecord::RecordNotFound unless @test_plan.visible?
      @test_cases.each do |test_case|
        plan_case = TestPlanCase.where(test_plan: @test_plan, test_case: test_case).first
        if plan_case
          plan_case.destroy
          # FIXME: unassign without full rendering, use remote XHR
          flash[:notice] = l(:notice_successful_delete)
        end
      end
      redirect_to project_test_plan_path(id: @test_plan.id)
    rescue
      render 'forbidden', status: 404
    end
  end

  # POST /projects/:project_id/test_plans/:id/reorder
  # Body: { test_plan_case_ids: [3, 1, 2] } — order of ids is the new sequence.
  def reorder
    raise ::Unauthorized unless @test_plan.editable?
    ids = Array(params[:test_plan_case_ids]).map(&:to_i)
    @test_plan.test_plan_cases.each do |tpc|
      idx = ids.index(tpc.id)
      if idx
        tpc.update_column(:position, idx + 1)
      end
    end
    respond_to do |format|
      format.html { redirect_to project_test_plan_path(id: @test_plan.id) }
      format.json { render json: { ok: true } }
    end
  end

  # POST /projects/:project_id/test_plans/:id/copy
  def copy
    raise ::Unauthorized unless @test_plan.editable?
    new_plan = @test_plan.dup
    new_plan.name = "#{@test_plan.name} (copy)"
    new_plan.plan_state = 'draft'
    new_plan.source_plan_id = @test_plan.id
    new_plan.issue_status_id = nil
    if new_plan.save
      @test_plan.test_plan_cases.order(:position).each do |tpc|
        new_plan.test_plan_cases.create!(
          test_case_id: tpc.test_case_id,
          position: tpc.position,
          name_snapshot: tpc.name_snapshot,
          scenario_snapshot: tpc.scenario_snapshot,
          expected_snapshot: tpc.expected_snapshot,
          environment_snapshot: tpc.environment_snapshot
        )
      end
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_test_plan_path(id: new_plan.id)
    else
      flash.now[:error] = l(:error_update_failure)
      render :show
    end
  end

  # GET /projects/:project_id/test_plans/statistics
  def statistics
    begin
      # Aggregate per plan the current status counts, deriving Not run when no
      # execution record exists. Computed in Ruby to stay portable across DBs.
      @test_plans = TestPlan.where(project: @project)
        .includes(test_plan_cases: :test_case_execution)
        .order(id: :desc)
        .map do |plan|
          summary = Hash.new(0)
          plan.test_plan_cases.each { |tpc| summary[tpc.execution_status_key] += 1 }
          {
            id: plan.id,
            name: plan.name,
            user_id: plan.user_id,
            estimated_bug: plan.estimated_bug,
            count_cases: plan.test_plan_cases.size,
            count_not_executed: summary['not_run'],
            count_passed: summary['passed'],
            count_failed: summary['failed'],
            count_in_progress: summary['in_progress'],
            count_on_hold: summary['on_hold'],
            count_not_applicable: summary['not_applicable'],
          }
        end
      @title = html_title(l(:label_test_plan_statistics))
      render :statistics
    rescue
      render 'forbidden', status: 404
    end
  end

  # GET /projects/:project_id/test_plans/:id/context_menu
  def show_context_menu
    if @test_cases.size == 1
      @test_case = @test_cases.first
    end
    @test_case_ids = @test_cases.map(&:id).sort

    edit_allowed = @test_cases.all? {|t| t.editable?(User.current)}
    @can = {:edit => edit_allowed, :delete => edit_allowed}
    @back = back_url

    @safe_attributes = @test_cases.map(&:safe_attribute_names).reduce(:&)
    @assignables = @project.users
    render :layout => false
  end

  # GET /projects/:project_id/test_plans/context_menu
  def list_context_menu
    if @test_plans.size == 1
      @test_plan = @test_plans.first
    end
    @test_plan_ids = @test_plans.map(&:id).sort

    edit_allowed = @test_plans.all? {|t| t.editable?(User.current)}
    @can = {:edit => edit_allowed, :delete => edit_allowed}
    @back = back_url

    @safe_attributes = @test_plans.map(&:safe_attribute_names).reduce(:&)
    @assignables = @project.users
    render :layout => false
  end

  def bulk_edit
    @assignables = @project.users
    @safe_attributes = @test_plans.map(&:safe_attribute_names).reduce(:&)
    @test_plan_params = params[:test_plan] || {}
    @back_url = params[:back_url]
  end

  def bulk_update
    attributes = parse_params_for_bulk_update(params[:test_plan])

    unsaved_test_plans = []
    saved_test_plans = []

    @test_plans.each do |orig_test_plan|
      orig_test_plan.reload
      test_plan = orig_test_plan
      test_plan.safe_attributes = attributes
      if test_plan.save
        saved_test_plans << test_plan
      else
        unsaved_test_plans << orig_test_plan
      end
    end

    if unsaved_test_plans.empty?
      flash[:notice] = l(:notice_successful_update) unless saved_test_plans.empty?
      redirect_to params[:back_url]
    else
      @saved_test_plans = saved_test_plans
      @unsaved_test_plans = unsaved_test_plans
      @test_plans = TestPlan.where(id: @unsaved_test_plans.map(&:id)).to_a
      bulk_edit
      render :action => 'bulk_edit'
    end
  end

  # DELETE /projects/:project_id/test_plans/bulk_delete
  def bulk_delete
    @test_plan_params = params[:test_plan] || {}

    delete_allowed = @test_plans.all? { |t| t.editable?(User.current) }
    if delete_allowed
      @test_plans.destroy_all
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:notice] = l(:error_delete_failure)
    end
    redirect_to params[:back_url]
  end

  private

  def test_plan_params
    params.require(:test_plan).permit(:project_id,
                                      :name,
                                      :user,
                                      :begin_date,
                                      :end_date,
                                      :estimated_bug,
                                      :issue_status,
                                      :plan_state,
                                      :source_plan_id,
                                      :notes)
  end

  def query_to_csv(items, query, options={})
    columns = query.columns

    Redmine::Export::CSV.generate(:encoding => params[:encoding]) do |csv|
      # csv header fields
      csv << columns.map {|c| c.caption.to_s} + [l(:field_test_cases)]
      # csv lines
      items.each do |item|
        csv << columns.map {|c| csv_content(c, item)} + [item.test_cases.pluck(:id).join(",")]
      end
    end
  end
end

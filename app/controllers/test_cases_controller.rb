class TestCasesController < ApplicationController

  include ApplicationsHelper

  before_action :find_project_id
  before_action :find_test_plan_id_if_given, :only => [:new, :create, :show, :edit, :index, :update, :destroy]
  before_action :find_test_case, :only => [:show, :edit, :update, :destroy]
  before_action :authorize_with_issues_permission
  before_action :find_test_cases, :only => [:list_context_menu, :bulk_edit, :bulk_update, :bulk_delete]

  before_action do
    prepare_user_candidates
    prepare_issue_status_candidates
    if @test_plan
      prepare_test_plan_candidates
    end
  end

  helper :attachments
  helper :queries
  include QueriesHelper
  helper :test_cases_queries
  include TestCasesQueriesHelper
  helper :context_menus

  # GET /projects/:project_id/test_cases
  # GET /projects/:project_id/test_plans/:test_plan_id/test_cases
  def index
    retrieve_query(TestCaseQuery, false)

    if @query.valid?
      respond_to do |format|
        @test_cases_export_limit = Setting.plugin_testcase_management["test_cases_export_limit"].to_i
        format.html do
          if @test_plan_given
            @test_case_count = @query.test_case_count(params[:test_plan_id], true)
            @test_case_pages = Paginator.new @test_case_count, per_page_option, params["page"]
            @test_cases = @query.test_cases(test_plan_id: params[:test_plan_id],
                                            offset: @test_case_pages.offset,
                                            limit: @test_case_pages.per_page).visible
            @title = html_title(l(:label_test_cases),
                                "##{@test_plan.id} #{@test_plan.name}",
                                l(:label_test_plans))
            @csv_url = project_test_plan_test_cases_path(@project, test_plan_id: params[:test_plan_id], format: "csv")
          else
            @test_case_count = @query.test_case_count(nil, true)
            @test_case_pages = Paginator.new @test_case_count, per_page_option, params["page"]
            @test_cases = @query.test_cases(offset: @test_case_pages.offset,
                                            limit: @test_case_pages.per_page).visible
            @title = html_title(l(:label_test_cases))
            @csv_url = project_test_cases_path(@project, format: "csv")
          end
        end
        format.csv do
          if @test_plan_given
            @test_cases = @query.test_cases(test_plan_id: params[:test_plan_id],
                                            limit: @test_cases_export_limit).visible
          else
            @test_cases = @query.test_cases(limit: @test_cases_export_limit).visible
          end
          send_data(query_to_csv(@test_cases, @query, params[:csv]),
                    :type => 'text/csv; header=present', :filename => 'test_cases.csv')
        end
      end
    else
      flash.now[:error] = l(:error_index_failure)
      render 'forbidden', status: :unprocessable_entity
    end
  end

  # GET /projects/:project_id/test_cases/new
  # GET /projects/:project_id/test_plans/:test_plan_id/test_cases/new
  def new
    @test_case = TestCase.new
    if params.permit(:test_plan_id)[:test_plan_id]
      @test_plan = TestPlan.find(params.permit(:test_plan_id)[:test_plan_id])
      @title = html_title(l(:label_test_case_new),
                          "##{@test_plan.id} #{@test_plan.name}",
                          l(:label_test_plans))
    else
      @test_plan = nil
      @title = html_title(l(:label_test_case_new))
    end
  end

  # POST /projects/:project_id/test_cases
  # POST /projects/:project_id/test_plans/:test_plan_id/test_cases
  def create
    begin
      @test_case = TestCase.new(:project_id => @project.id,
                                :user => User.find(test_case_params[:user]),
                                :name => test_case_params[:name],
                                :environment => test_case_params[:environment],
                                :scenario => test_case_params[:scenario],
                                :expected => test_case_params[:expected],
                                :case_state => test_case_params[:case_state],
                                :priority => test_case_params[:priority])
      if params[:test_case].permit!.to_h["test_case_steps_attributes"]
        @test_case.test_case_steps_attributes = params[:test_case].permit!.to_h["test_case_steps_attributes"]
      end
      if @test_plan
        @test_case.test_plan_cases.build(test_plan: @test_plan)
      end
      if params[:attachments].present?
        @test_case.save_attachments params.require(:attachments).permit!
      end
      if @test_case.valid?
        @test_case.save
        flash[:notice] = l(:notice_successful_create)
        if @test_plan
          if params[:continue]
            redirect_to new_project_test_plan_test_case_path(test_plan_id: @test_plan.id)
          else
            redirect_to project_test_plan_path(id: @test_plan.id)
          end
        else
          if params[:continue]
            redirect_to new_project_test_case_path
          else
            redirect_to project_test_case_path(id: @test_case.id)
          end
        end
      else
        render :new, status: :unprocessable_entity
      end
    rescue
      render :new, status: :unprocessable_entity
    end
  end

  # GET /projects/:project_id/test_cases/:id
  # GET /projects/:project_id/test_plans/:test_plan_id/test_cases/:id
  def show
    if @test_plan_given
      @test_case_executions = @test_case.test_case_executions_for(@test_plan)
      @title = html_title("##{@test_case.id} #{@test_case.name}",
                          l(:label_test_cases),
                          "##{@test_plan.id} #{@test_plan.name}",
                          l(:label_test_plans))
    else
      @test_case_executions = @test_case.test_case_executions
      @title = html_title("##{@test_case.id} #{@test_case.name}",
                          l(:label_test_cases))
    end
  end

  # GET /projects/:project_id/test_cases/:id/edit
  # GET /projects/:project_id/test_plans/:test_plan_id/test_cases/:id/edit
  def edit
    if @test_plan_given
      @title = html_title("#{l(:label_test_case_edit)} ##{@test_case.id}",
                          l(:label_test_cases),
                          "##{@test_plan.id} #{@test_plan.name}",
                          l(:label_test_plans))
    else
      @title = html_title("#{l(:label_test_case_edit)} ##{@test_case.id}",
                          l(:label_test_cases))
    end
  end

  # PUT /projects/:project_id/test_cases/:id
  # PUT /projects/:project_id/test_plans/:test_plan_id/test_cases/:id
  def update
    raise ::Unauthorized unless @test_case.editable?
    update_params = {
      name: test_case_params[:name],
      scenario: test_case_params[:scenario],
      expected: test_case_params[:expected],
      environment: test_case_params[:environment],
      case_state: (test_case_params[:case_state].presence || @test_case.case_state.presence || 'draft'),
      priority: test_case_params[:priority]
    }
    if params[:test_case].permit!.to_h["test_case_steps_attributes"]
      update_params[:test_case_steps_attributes] = params[:test_case].permit!.to_h["test_case_steps_attributes"]
    end
    user = User.find(test_case_params[:user])
    update_params[:user_id] = user.id if user.present?
    if params[:attachments].present?
      @test_case.save_attachments params.require(:attachments).permit!
    end
    if @test_case.update(update_params)
      flash[:notice] = l(:notice_successful_update)
      if params[:test_plan_id].present?
        redirect_to project_test_plan_path(id: params[:test_plan_id])
      else
        redirect_to project_test_case_path
      end
    else
      flash.now[:error] = l(:error_update_failure)
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /projects/:project_id/test_cases/:id
  # DELETE /projects/:project_id/test_plans/:test_plan_id/test_cases/:id
  def destroy
    raise ::Unauthorized unless @test_case.deletable?
    begin
      if @test_case.destroy
        flash[:notice] = l(:notice_successful_delete)
        if params[:test_plan_id].present?
          redirect_to project_test_plan_path(id: params.permit(:test_plan_id)[:test_plan_id])
        else
          redirect_to project_test_cases_path
        end
      else
        flash.now[:error] = l(:error_delete_failure)
        render :show
      end
    rescue
      flash.now[:error] = l(:error_test_case_not_found)
      render 'forbidden', status: 404
    end
  end

  # GET /projects/:project_id/test_cases/auto_complete
  def auto_complete
    test_cases = []
    unless User.current.allowed_to?(:view_issues, @project, :global => true)
      render :json => test_cases
      return
    end
    q = params.permit(:term)[:term]
    test_plan_id = params.permit(:test_plan_id)[:test_plan_id]
    num = 0
    if q.present?
      begin
        num = Integer(q)
      rescue
      end
    end
    like = if Redmine::Database.postgresql?
             "ILIKE"
           else
             "LIKE"
           end
    begin
      if test_plan_id.present?
        test_cases = TestCase.visible.where.not(id: TestPlan.find(test_plan_id).test_cases.select(:id))
                       .where("projects.identifier = ? AND test_cases.name #{like} ?",
                              @project.identifier, "%#{q}%").order(id: :desc).limit(10).to_a
      end
      render :json => format_test_cases_json(test_cases)
    rescue
      render :json => test_cases
    end
  end

  # GET /projects/:project_id/test_cases/statistics
  def statistics
    return unless authorize_with_issues_permission(params[:controller], :index)
    begin
      plans = TestPlan.where(project: @project).includes(test_plan_cases: :test_case_execution)

      # Aggregate per assigned user: how many plan-cases fall into each status
      # bucket (Not run derived when there is no execution record).
      @test_cases = Hash.new { |h, k| h[k] = { count: 0, not_executed: 0, passed: 0, failed: 0,
                                                in_progress: 0, on_hold: 0, not_applicable: 0 } }
      plans.each do |plan|
        bucket = @test_cases[plan.user_id]
        bucket[:count] += plan.test_plan_cases.size
        plan.test_plan_cases.each do |tpc|
          key = tpc.execution_status_key
          case key
          when 'passed'        then bucket[:passed] += 1
          when 'failed'        then bucket[:failed] += 1
          when 'in_progress'   then bucket[:in_progress] += 1
          when 'on_hold'       then bucket[:on_hold] += 1
          when 'not_applicable' then bucket[:not_applicable] += 1
          else                      bucket[:not_executed] += 1
          end
        end
      end
      @test_cases = @test_cases.sort_by { |_user_id, stats| [-stats[:not_executed], -stats[:failed]] }.to_h
      render :statistics
    rescue
      render 'forbidden', status: 404
    end
  end

  # GET /projects/:project_id/test_cases/bulk_edit
  def bulk_edit
    @assignables = @project.users
    @safe_attributes = @test_cases.map(&:safe_attribute_names).reduce(:&)
    @test_case_params = params[:test_case] || {}
    @back_url = params[:back_url]
  end

  # POST /projects/:project_id/test_cases/bulk_update
  def bulk_update
    attributes = parse_params_for_bulk_update(params[:test_case])

    unsaved_test_cases = []
    saved_test_cases = []

    @test_cases.each do |orig_test_case|
      orig_test_case.reload
      test_case = orig_test_case
      test_case.safe_attributes = attributes
      if test_case.save
        saved_test_cases << test_case
      else
        unsaved_test_cases << orig_test_case
      end
    end

    if unsaved_test_cases.empty?
      flash[:notice] = l(:notice_successful_update) unless saved_test_cases.empty?
      unless @test_cases.first.test_plan
        redirect_back_or_default project_test_cases_path
      else
        redirect_back_or_default project_test_plans_path(id: @test_cases.first.test_plan.id)
      end
    else
      @saved_test_cases = @test_cases
      @unsaved_test_cases = unsaved_test_cases
      @test_cases = TestCase.visible.where(id: @unsaved_test_cases.map(&:id)).to_a
      bulk_edit
      render :action => 'bulk_edit'
    end
  end

  # DELETE /projects/:project_id/test_cases/bulk_delete
  def bulk_delete
    @test_case_params = params[:test_case] || {}

    delete_allowed = @test_cases.all? { |t| t.deletable?(User.current) }
    if delete_allowed
      @test_cases.destroy_all
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:notice] = l(:error_delete_failure)
    end
    redirect_to params[:back_url]
  end

  # GET /projects/:project_id/test_cases/context_menu
  def list_context_menu
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

  private

  def format_test_cases_json(test_cases)
    test_cases.map do |test_case|
      {
        'id': test_case.id,
        'label': "##{test_case.id} #{test_case.name.truncate(60)}",
        'value': test_case.id
      }
    end
  end

  def test_case_params
    params.require(:test_case).permit(:project_id,
                                      :test_plan_id,
                                      :name,
                                      :user,
                                      :environment,
                                      :scenario,
                                      :expected,
                                      :case_state,
                                      :priority,
                                      :archived_at,
                                      :version,
                                      test_case_steps_attributes: [:id, :position, :action, :expected_result, :test_data, :notes, :_destroy])
  end

  def csv_value(column, test_case, value)
    case column.name
    when :latest_status
      latest_execution = test_case.latest_test_case_execution(@test_plan)
      if latest_execution && latest_execution.status
        latest_execution.status.name
      else
        l(:label_none)
      end
    when :case_state
      test_case.case_state ? l("label_case_state_#{test_case.case_state}", default: test_case.case_state) : l(:label_none)
    when :latest_execution_date
      !value ? l(:label_none) :
        yyyymmdd_date(value)
    else
      super
    end
  end
end

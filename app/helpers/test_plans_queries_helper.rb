module TestPlansQueriesHelper

  def column_value(column, item, value)
    if item.is_a?(TestPlan)
      case column.name
      when :id
        link_to item.id,
                project_test_plan_url(project_id: item.project.identifier,
                                      id: item.id)
      when :name
        link_to item.name,
                project_test_plan_url(project_id: item.project.identifier,
                                      id: item.id)
      when :plan_state
        l("label_plan_state_#{item.plan_state}", default: item.plan_state)
      when :begin_date, :end_date
        if value
          yyyymmdd_date(value)
        else
          l(:label_none)
        end
      else
        super
      end
    elsif item.is_a?(TestCase)
      # For test cases bound to a test plan
      case column.name
      when :id
        link_to item.id,
                project_test_plan_test_case_url(project_id: item.project.identifier,
                                                test_plan_id: @test_plan.id,
                                                id: item.id)
      when :name
        link_to item.name,
                project_test_plan_test_case_url(project_id: item.project.identifier,
                                                test_plan_id: @test_plan.id,
                                                id: item.id)
      when :latest_status
        latest_execution = item.latest_test_case_execution(@test_plan)
        status = latest_execution ? latest_execution.status : TestExecutionStatus.not_run
        if latest_execution
          link_to status.name,
                  project_test_plan_test_case_test_case_execution_url(project_id: item.project.identifier,
                                                                      test_plan_id: @test_plan.id,
                                                                      test_case_id: item.id,
                                                                      id: latest_execution.id)
        else
          content_tag(:span, status ? status.name : l(:label_none), class: "status #{status&.key}")
        end
      when :latest_execution_date
        if value
          yyyymmdd_date(value)
        else
          l(:label_none)
        end
      when :scenario, :expected
        column_truncated_text(value, truncate_line: false)
      else
        super
      end
    else
      raise ArgumentError
    end
  end
end

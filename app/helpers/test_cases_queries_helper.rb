module TestCasesQueriesHelper

  def column_value(column, item, value)
    if item.is_a?(TestCase)
      case column.name
      when :id
        if @test_plan_given
          link_to item.id,
                  project_test_plan_test_case_url(project_id: item.project.identifier,
                                                  test_plan_id: @test_plan.id,
                                                  id: item.id)
        else
          link_to item.id,
                  project_test_case_url(project_id: item.project.identifier,
                                        id: item.id)
        end
      when :name
        if @test_plan_given
          link_to item.name,
                  project_test_plan_test_case_url(project_id: item.project.identifier,
                                                  test_plan_id: @test_plan.id,
                                                  id: item.id)
        else
          link_to item.name,
                  project_test_case_url(project_id: item.project.identifier,
                                        id: item.id)
        end
      when :scenario, :expected
        column_truncated_text(value, truncate_line: false)
      when :case_state
        l("label_case_state_#{item.case_state}", default: item.case_state)
      when :priority
        item.priority.presence || l(:label_none)
      when :latest_status
        latest_execution = item.latest_test_case_execution(@test_plan)
        status = if latest_execution && latest_execution.status
                   latest_execution.status
                 else
                   TestExecutionStatus.not_run
                 end
        if latest_execution && status
          link_to status.name,
                  project_test_plan_test_case_test_case_execution_url(project_id: item.project.identifier,
                                                                       test_plan_id: latest_execution.test_plan_id,
                                                                       test_case_id: item.id,
                                                                       id: latest_execution.id)
        else
          status_name = status ? status.name : l(:label_none)
          content_tag(:span, status_name, class: "status #{status&.key}")
        end
      when :latest_execution_date
        if value
          latest_execution = item.latest_test_case_execution(@test_plan)
          if latest_execution
            link_to yyyymmdd_date(value),
                    project_test_plan_test_case_test_case_execution_url(project_id: item.project.identifier,
                                                                         test_plan_id: latest_execution.test_plan_id,
                                                                         test_case_id: item.id,
                                                                         id: latest_execution.id)
          else
            yyyymmdd_date(value)
          end
        else
          l(:label_none)
        end
      else
        super
      end
    else
      raise ArgumentError
    end
  end
end

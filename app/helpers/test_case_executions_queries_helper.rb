module TestCaseExecutionsQueriesHelper

  def column_value(column, item, value)
    if item.is_a?(TestCaseExecution)
      case column.name
      when :id
        link_to item.id,
                project_test_case_execution_url(project_id: item.project.identifier,
                                                id: item.id)
      when :test_case
        link_to item.test_case.name,
                project_test_case_url(project_id: item.project.identifier,
                                      id: item.test_case.id)
      when :test_plan
        link_to truncate(item.test_plan.name),
                project_test_plan_url(project_id: item.project.identifier,
                                      id: item.test_plan.id)
      when :status
        if item.status
          content_tag(:span, item.status.name, class: "status #{item.status.key}")
        else
          l(:label_none)
        end
      when :executor
        item.executor ? item.executor.name : l(:label_none)
      when :defect_issue
        if item.defect_issue
          link_to_issue item.defect_issue
        else
          l(:label_none)
        end
      when :comment
        truncate(value)
      when :scenario
        column_truncated_text(item.test_case.scenario, truncate_line: false)
      when :expected
        column_truncated_text(item.test_case.expected, truncate_line: false)
      when :execution_date
        yyyymmdd_date(value)
      else
        super
      end
    else
      raise ArgumentError
    end
  end
end

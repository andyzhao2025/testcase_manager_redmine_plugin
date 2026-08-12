module TestCaseManagement
  module QueriesControllerPatch
    def redirect_to_test_case_query(options)
      redirect_to project_test_cases_path(project_id: @project.identifier)
    end

    def redirect_to_test_plan_query(options)
      redirect_to project_test_plans_path(project_id: @project.identifier)
    end

    def redirect_to_test_case_execution_query(options)
      redirect_to project_test_case_executions_path(project_id: @project.identifier)
    end
  end
end

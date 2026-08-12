class TestCaseExecutionImport < Import
  AUTO_MAPPABLE_FIELDS = {
    "test_case" => "field_test_case",
    "test_plan" => "field_test_plan",
    # "status" is the new field; "result" is retained as a legacy alias so
    # pre-status-model CSV exports keep importing.
    "status" => "field_status",
    "result" => "field_result",
    "executor" => "field_executor",
    "user" => "field_user",
    "defect_issue" => "field_defect_issue",
    "issue" => "field_issue",
    "comment" => "field_comment",
    "execution_date" => "field_execution_date",
    "automation_source" => "field_automation_source",
    "external_run_id" => "field_external_run_id",
    "build_url" => "field_build_url",
    "duration_seconds" => "field_duration_seconds",
  }

  def self.menu_item
    :test_case_executions
  end

  def self.authorized?(user)
    user.allowed_to?(:add_test_case_executions, nil, :global => true)
  end

  def saved_objects
    object_ids = saved_items.pluck(:obj_id)
    TestCaseExecution.where(:id => object_ids).order(:id)
  end

  def allowed_target_projects
    Project.allowed_to(user, :add_test_case_executions)
  end

  def project
    project_id = mapping["project_id"].to_i
    allowed_target_projects.find_by_id(project_id) || allowed_target_projects.first
  end

  def mappable_custom_fields
    []
  end

  private

  # Map the pre-status-model boolean labels (and common plain-English variants)
  # to canonical status keys, so legacy CSV exports keep importing cleanly.
  def legacy_status(label)
    legacy = {
      "passed" => "passed",
      "failure" => "failed",
      "failed" => "failed",
      "succeed" => "passed",
      "success" => "passed",
      "not_run" => "not_run",
      "not run" => "not_run",
      "in_progress" => "in_progress",
      "on_hold" => "on_hold",
      "on hold" => "on_hold",
      "not_applicable" => "not_applicable",
      "na" => "not_applicable",
    }[label.to_s.strip.downcase]
    legacy && TestExecutionStatus.canonical(legacy)
  end

  def build_object(row, item)
    test_case_execution = TestCaseExecution.new
    test_case_execution.executor = user
    test_case_execution.project_id = mapping["project_id"].to_i

    begin
      id_or_name = row_value(row, "test_case")
      test_case = if TestCase.where(name: id_or_name, project_id: test_case_execution.project_id).first
                    TestCase.where(name: id_or_name, project_id: test_case_execution.project_id).first
                  elsif TestCase.where(id: id_or_name, project_id: test_case_execution.project_id).first
                    TestCase.where(id: id_or_name, project_id: test_case_execution.project_id).first
                  else
                    nil
                  end
      if test_case
        test_case_execution.test_case = test_case
      end
    rescue ActiveRecord::RecordNotFound
    end

    begin
      id_or_name = row_value(row, "test_plan")
      test_plan = if TestPlan.where(name: id_or_name, project_id: test_case_execution.project_id).first
                    TestPlan.where(name: id_or_name, project_id: test_case_execution.project_id).first
                  elsif TestPlan.where(id: id_or_name, project_id: test_case_execution.project_id).first
                    TestPlan.where(id: id_or_name, project_id: test_case_execution.project_id).first
                  else
                    nil
                  end
      if test_plan
        test_case_execution.test_plan = test_plan
      end
    rescue ActiveRecord::RecordNotFound
    end

    attributes = {
      "comment" => row_value(row, "comment")
    }

    # Map a status label to a canonical TestExecutionStatus key. Accepts both the
    # new "status" column and the legacy "result" column (Succeed/Failure labels).
    status_label = row_value(row, "status") || row_value(row, "result")
    if status_label.present?
      status = TestExecutionStatus.canonical(status_label) ||
               TestExecutionStatus.canonical(status_label.to_s.downcase.gsub(/\s+/, "_")) ||
               legacy_status(status_label)
      attributes["status_id"] = status.id if status
    end

    if executor_name = row_value(row, "executor") || row_value(row, "user")
      if found_user = Principal.detect_by_keyword(test_case_execution.ownable_users, executor_name)
        attributes["executor_id"] = found_user.id
      end
    end

    if automation_source = row_value(row, "automation_source")
      attributes["automation_source"] = automation_source
    end
    if external_run_id = row_value(row, "external_run_id")
      attributes["external_run_id"] = external_run_id
    end
    if build_url = row_value(row, "build_url")
      attributes["build_url"] = build_url
    end
    if duration_seconds = row_value(row, "duration_seconds")
      attributes["duration_seconds"] = duration_seconds
    end

    if execution_date = row_date(row, "execution_date")
      attributes["execution_date"] = execution_date
    end

    if defect_issue_id = row_value(row, "defect_issue")
      begin
        issue = Issue.find(defect_issue_id)
        if issue and issue.project_id == test_case_execution.project_id
          test_case_execution.defect_issue = issue
        end
      rescue ActiveRecord::RecordNotFound
      end
    end

    test_case_execution.send :safe_attributes=, attributes, user

    test_case_execution
  end
end

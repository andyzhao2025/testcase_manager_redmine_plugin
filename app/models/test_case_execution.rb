class TestCaseExecution < ApplicationRecord
  include Redmine::SafeAttributes
  include TestCaseManagement::SafeAttributes
  include TestCaseManagement::InheritIssuePermissions

  belongs_to :executor, class_name: "User", foreign_key: :executor_id
  belongs_to :project
  belongs_to :status, class_name: "TestExecutionStatus", foreign_key: :status_id
  belongs_to :test_plan
  belongs_to :test_plan_case, optional: true
  belongs_to :test_case
  # defect_issue is the optional link to a Redmine issue for bug tracking,
  # unrelated to the plugin's primary authority (which is status based).
  belongs_to :defect_issue, class_name: "Issue", foreign_key: :defect_issue_id, optional: true
  acts_as_attachable

  validates :status, presence: true
  validates :executor, presence: true
  validates :test_plan, presence: true
  validates :test_case, presence: true
  validates :execution_date, presence: true
  validates :test_plan_case_id, uniqueness: true, allow_nil: true

  validate :owned_only_by_visible_user

  safe_attributes(
    "project_id",
    "status_id",
    "executor_id",
    # Legacy aliases for the renamed user/issue columns and the replaced
    # boolean result; mapped in TestCaseManagement::SafeAttributes.
    "user_id",
    "issue_id",
    "result",
    "test_plan_id",
    "test_plan_case_id",
    "test_case_id",
    "defect_issue_id",
    "comment",
    "execution_date",
    "automation_source",
    "external_run_id",
    "build_url",
    "duration_seconds",
    :if => lambda {|instance, user| instance.new_record? || instance.attributes_editable?(user)})

  def safe_attribute_names(user=nil)
    names = super
    if new_record?
      names |= %w(project_id)
    end
    names
  end

  scope :visible, (lambda do |*args|
    user = args.shift || User.current
    joins(:project).
    where(TestCaseManagement::InheritIssuePermissions.visible_condition(user, args.first || {},
                                                                        permission: :view_test_case_executions,
                                                                        owner_column: :executor_id))
  end)

  scope :automated, -> { where.not(automation_source: nil) }
  scope :manual, -> { where(automation_source: nil) }

  # Ownership of an execution is attributed via executor, not user.
  def owner_ref
    :executor
  end

  def visible?(user=User.current)
    super(user, permission: :view_test_case_executions)
  end

  def editable?(user=User.current)
    attributes_editable?(user, edit_permission: :edit_test_case_executions)
  end

  def deletable?(user=User.current)
    super(user, delete_permission: :delete_test_case_executions)
  end

  def passed?
    status.present? && status.passed?
  end

  def failed?
    status.present? && status.failed?
  end

  def status_key
    status ? status.key : nil
  end

  def status_name
    status ? status.name : nil
  end

  def automated?
    automation_source.present?
  end

  # Legacy-compat aliases for the renamed owner (user -> executor) and defect
  # link (issue -> defect_issue) so outside code from the pre-rename plugin
  # degrades gracefully instead of raising NoMethodError.
  def user
    executor
  end

  def user=(value)
    self.executor = value
  end

  def user_id
    executor_id
  end

  def user_id=(value)
    self.executor_id = value
  end

  def issue
    defect_issue
  end

  def issue_id
    defect_issue_id
  end

  def issue_id=(value)
    self.defect_issue_id = value
  end

  # Legacy-compat accessor so outside code that reads `result` degrades to the
  # boolean derived from the status rather than crashing.
  def result
    return nil unless status
    status.passed? ? true : false
  end

  def attachments_visible?(user=User.current)
    visible?(user)
  end

  def attachments_editable?(user=User.current)
    editable?(user)
  end

  def attachments_deletable?(user=User.current)
    deletable?(user)
  end
end

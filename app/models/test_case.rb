class TestCase < ApplicationRecord
  include Redmine::SafeAttributes
  include TestCaseManagement::SafeAttributes
  include TestCaseManagement::InheritIssuePermissions

  belongs_to :user
  belongs_to :project
  has_many :test_case_steps, -> { order(:position) }, dependent: :destroy, inverse_of: :test_case
  has_many :test_plan_cases, dependent: :destroy
  has_many :test_plans, through: :test_plan_cases
  has_many :test_case_executions, dependent: :destroy
  acts_as_attachable

  validates :name, presence: true, length: { maximum: 255 }
  validates :scenario, presence: true
  validates :expected, presence: true
  validates :user, presence: true
  validates :project, presence: true
  CASE_STATES = %w[draft active deprecated archived].freeze

  validates :case_state, inclusion: { in: CASE_STATES }, allow_nil: true

  validates_associated :test_case_executions

  validate :owned_only_by_visible_user

  # case_state is non-null. Apply the draft default on new records so create/import
  # paths that omit it still persist cleanly.
  after_initialize :apply_case_state_default
  def apply_case_state_default
    self.case_state = 'draft' if case_state.blank? && new_record?
  end

  accepts_nested_attributes_for :test_case_steps, allow_destroy: true

  safe_attributes(
    "project_id",
    "user_id",
    "name",
    "environment",
    "scenario",
    "expected",
    "case_state",
    "priority",
    "archived_at",
    "version",
    "test_case_steps_attributes",
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
    where(TestCaseManagement::InheritIssuePermissions.visible_condition(user, args.first || {}, permission: :view_test_cases))
  end)

  # scope :not_archived, -> { where(archived_at: nil) }

  # Returns the latest execution status for this test case, optionally scoped to
  # a specific test plan. Returns a TestExecutionStatus or the derived Not run.
  def latest_status(test_plan_or_id = nil)
    scope = test_case_executions.order(execution_date: :desc, id: :desc)
    if test_plan_or_id
      plan_id = test_plan_or_id.respond_to?(:id) ? test_plan_or_id.id : test_plan_or_id
      scope = scope.where(test_plan_id: plan_id)
    end
    execution = scope.first
    if execution && execution.status
      execution.status
    else
      TestExecutionStatus.not_run
    end
  end

  def latest_status_key(test_plan_or_id = nil)
    status = latest_status(test_plan_or_id)
    status ? status.key : 'not_run'
  end

  def latest_test_case_execution(test_plan_or_id = nil)
    scope = test_case_executions.order(execution_date: :desc, id: :desc)
    if test_plan_or_id
      plan_id = test_plan_or_id.respond_to?(:id) ? test_plan_or_id.id : test_plan_or_id
      scope = scope.where(test_plan_id: plan_id)
    end
    scope.first
  end

  def test_case_executions_for(test_plan = nil)
    conditions = { test_case: self }
    if test_plan
      conditions[:test_plan_id] = test_plan.respond_to?(:id) ? test_plan.id : test_plan
    end
    TestCaseExecution.where(conditions)
  end

  # Backward-compat shim: many call sites (views, context menus, legacy code)
  # still reference the singular +test_plan+. Returns the first associated plan.
  def test_plan
    test_plans.first
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

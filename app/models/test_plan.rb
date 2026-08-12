class TestPlan < ApplicationRecord
  include Redmine::SafeAttributes
  include TestCaseManagement::SafeAttributes
  include TestCaseManagement::InheritIssuePermissions

  belongs_to :user
  belongs_to :project
  # issue_status is kept only as a deprecated compatibility column; it no longer
  # drives the plugin's primary status semantics.
  belongs_to :issue_status, optional: true
  belongs_to :source_plan, class_name: "TestPlan", optional: true
  has_many :source_plans, class_name: "TestPlan", foreign_key: :source_plan_id, dependent: :nullify

  has_many :test_plan_cases, -> { order(:position) }, dependent: :destroy, inverse_of: :test_plan
  has_many :test_cases, through: :test_plan_cases
  has_many :test_case_executions, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :user, presence: true
  validates :project, presence: true
  validates :plan_state, inclusion: { in: %w[draft ready running closed archived] }, allow_nil: true

  validates_associated :test_plan_cases

  validate :owned_only_by_visible_user

  PLAN_STATES = %w[draft ready running closed archived].freeze

  # States that represent a frozen run container (snapshots are refreshed only
  # before this point, never afterwards).
  RUN_STATES = %w[running closed].freeze

  attr_accessor :test_case_ids # for import

  # plan_state is non-null. Apply the draft default on new records (and any
  # instance where the column is unexpectedly unset) so create/import paths that
  # omit it still persist cleanly.
  after_initialize :apply_plan_state_default
  def apply_plan_state_default
    self.plan_state = 'draft' if plan_state.blank? && new_record?
  end

  safe_attributes(
    "project_id",
    "name",
    "user_id",
    "estimated_bug",
    "begin_date",
    "end_date",
    "plan_state",
    "source_plan_id",
    "notes",
    "issue_status_id", # deprecated compat, retained
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
    where(TestCaseManagement::InheritIssuePermissions.visible_condition(user, args.first || {}, permission: :view_test_plans))
  end)

  def visible?(user=User.current)
    super(user, permission: :view_test_plans)
  end

  def editable?(user=User.current)
    attributes_editable?(user, edit_permission: :edit_test_plans)
  end

  def deletable?(user=User.current)
    super(user, delete_permission: :delete_test_plans)
  end

  # A TestPlan is a run container once it moves past ready.
  def run?
    RUN_STATES.include?(plan_state)
  end

  def started?
    run?
  end

  def plan_state_keys
    PLAN_STATES
  end
end

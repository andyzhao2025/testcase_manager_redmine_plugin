class TestPlanCase < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :test_plan, inverse_of: :test_plan_cases
  belongs_to :test_case

  # Current-result model: each TestPlanCase holds at most one execution record.
  has_one :test_case_execution, foreign_key: :test_plan_case_id, dependent: :destroy

  validates :test_plan, presence: true
  validates :test_case, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :test_case_id, uniqueness: { scope: :test_plan_id }
  validates :position, uniqueness: { scope: :test_plan_id }

  before_validation :set_position, on: :create
  before_validation :capture_snapshot, on: :create
  before_validation :refresh_snapshot, on: :update

  safe_attributes(
    "test_plan_id",
    "test_case_id",
    "position",
    "name_snapshot",
    "scenario_snapshot",
    "expected_snapshot",
    "environment_snapshot",
  )

  # The execution status shown for this plan-case: either the recorded execution
  # status, or the derived Not run when no execution record exists.
  def execution_status
    return test_case_execution.status if test_case_execution && test_case_execution.status
    TestExecutionStatus.not_run
  end

  def execution_status_key
    execution_status ? execution_status.key : 'not_run'
  end

  def current_execution
    test_case_execution
  end

  # Copy the live test case definition into the snapshot columns. Invoked on
  # creation and refreshed when the owning plan is a run container.
  def capture_snapshot
    return if test_case.nil?

    self.name_snapshot        ||= test_case.name
    self.scenario_snapshot    ||= test_case.scenario
    self.expected_snapshot    ||= test_case.expected
    self.environment_snapshot ||= test_case.environment
  end

  def refresh_snapshot
    return if test_plan.nil? || !test_plan.run?
    return if test_case.nil?

    self.name_snapshot        = test_case.name
    self.scenario_snapshot    = test_case.scenario
    self.expected_snapshot    = test_case.expected
    self.environment_snapshot = test_case.environment
  end

  # Display helpers prefer the snapshot so historical runs are not polluted by
  # later edits to the live TestCase.
  def display_name
    name_snapshot.presence || test_case&.name
  end

  def display_scenario
    scenario_snapshot.presence || test_case&.scenario
  end

  def display_expected
    expected_snapshot.presence || test_case&.expected
  end

  def display_environment
    environment_snapshot.presence || test_case&.environment
  end

  private

  def set_position
    return if position.present? && position.to_i > 0

    self.position = if test_plan_id
                      test_plan.test_plan_cases.maximum(:position).to_i + 1
                    else
                      1
                    end
  end
end

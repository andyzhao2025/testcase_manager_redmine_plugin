require_dependency 'project'

module TestCaseManagement
  module ProjectPatch
    extend ActiveSupport::Concern

    included do
      has_many :test_cases, dependent: :destroy
      has_many :test_case_executions, dependent: :destroy
      has_many :test_plans, dependent: :destroy
      has_many :test_plan_cases, through: :test_plans
      has_many :test_execution_statuses, dependent: :nullify
    end
  end
end

class TestCaseStep < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :test_case, inverse_of: :test_case_steps

  validates :test_case, presence: true
  validates :action, presence: true
  validates :expected_result, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :set_position, on: :create

  safe_attributes(
    "test_case_id",
    "position",
    "action",
    "expected_result",
    "test_data",
    "notes",
  )

  private

  def set_position
    return if position.present?

    self.position = if test_case_id
                      test_case.test_case_steps.maximum(:position).to_i + 1
                    else
                      1
                    end
  end
end

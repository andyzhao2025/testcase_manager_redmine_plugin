class TestExecutionStatus < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :project, optional: true

  has_many :test_case_executions, foreign_key: :status_id, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :category, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  # The key is the stable internal identifier; it must never be changed once
  # created, because execution records and queries rely on it.
  def readonly_key?
    !new_record? && persisted? && key_changed?
  end
  validate :key_not_changed
  def key_not_changed
    errors.add(:key, :readonly) if readonly_key?
  end

  safe_attributes(
    "project_id",
    "name",
    "category",
    "position",
    "color",
    "is_default",
    "is_final",
  )

  CATEGORIES = %w[pending running passed failed blocked skipped].freeze
  SYSTEM_KEYS = %w[not_run in_progress passed failed on_hold not_applicable].freeze

  scope :by_key, ->(key) { where(key: key) }
  scope :system, -> { where(project_id: nil) }
  scope :ordered, -> { order(:position) }
  scope :default_statuses, -> { where(is_default: true) }
  scope :final_statuses, -> { where(is_final: true) }

  class << self
    # Canonical status lookup by its stable key (system or project-level).
    def find_by_key(key, project_id: nil)
      scope = by_key(key)
      scope = scope.where(project_id: project_id) if project_id
      scope.first
    end

    def canonical(key)
      by_key(key).first
    end
  end

  # Not run is a derived state: it is shown whenever a TestPlanCase has no
  # execution record, rather than being persisted as a normal execution result.
  def self.not_run
    by_key('not_run').first
  end

  def not_run?
    key == 'not_run'
  end

  def passed?
    key == 'passed'
  end

  def failed?
    key == 'failed'
  end
end

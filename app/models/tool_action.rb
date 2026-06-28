class ToolAction < ApplicationRecord
  CAPABILITIES = Passport::CAPABILITIES
  STATUSES = %w[requested asking allowed running finished blocked denied failed].freeze

  belongs_to :run, counter_cache: true
  belongs_to :passport

  has_one :permission_request, dependent: :destroy
  has_many :audit_events, dependent: :nullify

  validates :capability, :action_kind, :status, :requested_at, presence: true
  validates :capability, inclusion: { in: CAPABILITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :source_event_id, uniqueness: { scope: :run_id, allow_nil: true }

  def request_text
    command.presence || path.presence || action_summary.to_s
  end
end

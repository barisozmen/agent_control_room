class Run < ApplicationRecord
  STATUSES = %w[starting running completed interrupted failed].freeze
  MODES = %w[demo manual observed].freeze

  has_many :passports, dependent: :destroy
  has_many :tool_actions, dependent: :destroy
  has_many :permission_requests, dependent: :destroy
  has_many :audit_events, dependent: :destroy

  validates :runtime_name, :project_path, :mode, :status, presence: true
  validates :bridge_token, presence: true, uniqueness: true
  validates :runtime_name, inclusion: { in: RuntimeAdapters::Registry.names }
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }

  before_validation :ensure_bridge_token, on: :create

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }
  scope :session_list, -> { order(Arel.sql("COALESCE(last_seen_at, started_at, created_at) DESC"), created_at: :desc, id: :desc) }
  scope :active, -> { where(status: %w[starting running]) }

  def self.current
    active.latest_first.first || latest_first.first
  end

  def active?
    status.in?(%w[starting running])
  end

  def failed?
    status == "failed"
  end

  def root_passport
    passports.find_by(parent_id: nil)
  end

  def selected_passport(passport_id = nil)
    passports.find_by(id: passport_id) || passports.find_by(actor_ref: "security-auditor") || passports.find_by(actor_ref: "main-agent") || root_passport
  end

  def display_title
    title.presence || "#{runtime_name} #{id}"
  end

  def runtime
    RuntimeAdapters::Registry.fetch(runtime_name)
  end

  def runtime_label
    runtime.label
  end

  def runtime_setup_guidance
    "Install #{runtime.label} or set #{runtime.command_env_key}, then retry the demo."
  end

  def display_project
    Pathname.new(project_path).basename.to_s
  rescue StandardError
    project_path
  end

  def broadcast_control_room!(selected_passport: nil)
    selected_passport ||= self.selected_passport

    broadcast_session_sidebar!
    broadcast_replace_to self, target: "run_header", partial: "runs/run_header", locals: { run: self }
    broadcast_replace_to self, target: "passport_tree", partial: "runs/passport_tree", locals: { run: self, selected_passport: selected_passport }
    broadcast_replace_to self, target: "permission_inbox", partial: "runs/permission_inbox", locals: { run: self }
    broadcast_replace_to self, target: "audit_timeline", partial: "runs/audit_timeline", locals: { run: self, audit_events: audit_events.chronological }

    return unless selected_passport.present?

    broadcast_replace_to self, target: "passport_detail", partial: "runs/passport_detail", locals: { run: self, passport: selected_passport }
  end

  def broadcast_runtime_event!(audit_event:, ui_changes:, selected_passport: nil)
    normalized_changes = Array(ui_changes).map(&:to_sym)
    selected_passport ||= self.selected_passport if normalized_changes.intersect?([:passport_tree, :passport_detail])

    broadcast_audit_event!(audit_event) if audit_event.present?
    broadcast_session_sidebar! if normalized_changes.include?(:session_sidebar)
    broadcast_replace_to self, target: "run_header", partial: "runs/run_header", locals: { run: self } if normalized_changes.include?(:run_header)
    broadcast_replace_to self, target: "passport_tree", partial: "runs/passport_tree", locals: { run: self, selected_passport: selected_passport } if normalized_changes.include?(:passport_tree)
    broadcast_replace_to self, target: "permission_inbox", partial: "runs/permission_inbox", locals: { run: self } if normalized_changes.include?(:permission_inbox)

    return unless normalized_changes.include?(:passport_detail) && selected_passport.present?

    broadcast_replace_to self, target: "passport_detail", partial: "runs/passport_detail", locals: { run: self, passport: selected_passport }
  end

  private

  def ensure_bridge_token
    self.bridge_token ||= SecureRandom.urlsafe_base64(32)
  end

  def broadcast_audit_event!(audit_event)
    audit_events_count = audit_events.count

    broadcast_append_to self, target: "audit_event_list", partial: "runs/audit_event", locals: { run: self, event: audit_event }
    broadcast_update_to self, target: "audit_timeline_count", partial: "runs/audit_timeline_count", locals: { audit_events_count: audit_events_count }
    broadcast_remove_to self, target: "audit_timeline_empty_state" if audit_events_count == 1
  end

  def broadcast_session_sidebar!
    broadcast_replace_to self, target: "session_sidebar", partial: "runs/session_sidebar", locals: { runs: Run.session_list, selected_run: self }
    broadcast_replace_to "runtime_sessions", target: "session_sidebar", partial: "runs/session_sidebar", locals: { runs: Run.session_list, selected_run: nil }
  end
end

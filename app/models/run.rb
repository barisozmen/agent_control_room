class Run < ApplicationRecord
  PassportTree = Data.define(:root_passport, :children_by_parent_id, :child_counts_by_passport_id, :agent_count, :passport_by_id, :passport_by_actor_ref) do
    def children_for(passport)
      return [] if passport.blank?

      children_by_parent_id.fetch(passport.id) { [] }
    end

    def child_count_for(passport)
      return 0 if passport.blank?

      child_counts_by_passport_id.fetch(passport.id, 0)
    end

    def selected_passport(passport_id = nil)
      if passport_id.present?
        selected = passport_by_id[passport_id.to_i]
        return selected if selected.present?
      end

      passport_by_actor_ref["security-auditor"] || passport_by_actor_ref["main-agent"] || root_passport
    end
  end

  STATUSES = %w[starting running completed interrupted failed].freeze
  MODES = %w[demo manual observed].freeze
  SESSION_LIST_LIMIT = 50

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
  scope :session_list, -> { order(Arel.sql("COALESCE(last_seen_at, started_at, created_at) DESC"), created_at: :desc, id: :desc).limit(SESSION_LIST_LIMIT) }
  scope :active, -> { where(status: %w[starting running]) }

  def self.current
    active.latest_first.first || latest_first.first
  end

  def self.session_sidebar_locals(selected_run:)
    runs = session_list.to_a

    {
      runs: runs,
      selected_run: selected_run,
      pending_counts_by_run_id: pending_permission_request_counts_for(runs)
    }
  end

  def self.pending_permission_request_counts_for(runs)
    run_ids = Array(runs).filter_map(&:id).uniq
    return {} if run_ids.empty?

    PermissionRequest.pending.where(run_id: run_ids).unscope(:order).group(:run_id).count
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

  def tool_actions_for_display
    tool_actions.includes({ passport: :grants }, { permission_request: :grant }).order(requested_at: :desc, id: :desc)
  end

  def passport_tree
    ordered_passports = passports.order(:created_at, :id).to_a
    children_by_parent_id = ordered_passports.group_by(&:parent_id)
    child_counts_by_passport_id = children_by_parent_id.each_with_object({}) do |(parent_id, children), counts|
      next if parent_id.nil?

      counts[parent_id] = children.size
    end

    PassportTree.new(
      root_passport: children_by_parent_id.fetch(nil) { [] }.first,
      children_by_parent_id: children_by_parent_id,
      child_counts_by_passport_id: child_counts_by_passport_id,
      agent_count: ordered_passports.count(&:agent?),
      passport_by_id: ordered_passports.index_by(&:id),
      passport_by_actor_ref: ordered_passports.index_by(&:actor_ref)
    )
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
    passport_tree = self.passport_tree
    selected_passport ||= passport_tree.selected_passport
    session_sidebar = Run.session_sidebar_locals(selected_run: self)

    broadcast_replace_to self, target: "session_sidebar", partial: "runs/session_sidebar", locals: session_sidebar
    broadcast_replace_to self, target: "run_header", partial: "runs/run_header", locals: { run: self }
    broadcast_replace_to self, target: "passport_tree", partial: "runs/passport_tree", locals: { run: self, selected_passport: selected_passport, passport_tree: passport_tree }
    broadcast_replace_to self, target: "permission_inbox", partial: "runs/permission_inbox", locals: { run: self }
    broadcast_replace_to self, target: "audit_timeline", partial: "runs/audit_timeline", locals: { run: self, audit_event_page: audit_timeline_page }
    broadcast_replace_to self, target: "tool_action_list", partial: "runs/tool_action_list", locals: { run: self, tool_actions: tool_actions_for_display }
    broadcast_replace_to "runtime_sessions", target: "session_sidebar", partial: "runs/session_sidebar", locals: session_sidebar.merge(selected_run: nil)

    return unless selected_passport.present?

    broadcast_replace_to self, target: "passport_detail", partial: "runs/passport_detail", locals: { run: self, passport: selected_passport }
  end

  def broadcast_runtime_event!(audit_event:, ui_changes:, selected_passport: nil)
    normalized_changes = Array(ui_changes).map(&:to_sym)
    passport_tree = nil
    if normalized_changes.include?(:passport_tree)
      passport_tree = self.passport_tree
      selected_passport ||= passport_tree.selected_passport
    elsif normalized_changes.include?(:passport_detail)
      selected_passport ||= self.selected_passport
    end

    broadcast_audit_event!(audit_event) if audit_event.present?
    broadcast_session_sidebar! if normalized_changes.include?(:session_sidebar)
    broadcast_replace_to self, target: "run_header", partial: "runs/run_header", locals: { run: self } if normalized_changes.include?(:run_header)
    broadcast_replace_to self, target: "passport_tree", partial: "runs/passport_tree", locals: { run: self, selected_passport: selected_passport, passport_tree: passport_tree } if normalized_changes.include?(:passport_tree)
    broadcast_replace_to self, target: "permission_inbox", partial: "runs/permission_inbox", locals: { run: self } if normalized_changes.include?(:permission_inbox)
    broadcast_replace_to self, target: "tool_action_list", partial: "runs/tool_action_list", locals: { run: self, tool_actions: tool_actions_for_display } if normalized_changes.include?(:tool_action_list)

    return unless normalized_changes.include?(:passport_detail) && selected_passport.present?

    broadcast_replace_to self, target: "passport_detail", partial: "runs/passport_detail", locals: { run: self, passport: selected_passport }
  end

  def audit_timeline_page(before_id: nil)
    AuditEvent.timeline_page_for(self, before_id: before_id)
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
    session_sidebar = Run.session_sidebar_locals(selected_run: self)

    broadcast_replace_to self, target: "session_sidebar", partial: "runs/session_sidebar", locals: session_sidebar
    broadcast_replace_to "runtime_sessions", target: "session_sidebar", partial: "runs/session_sidebar", locals: session_sidebar.merge(selected_run: nil)
  end
end

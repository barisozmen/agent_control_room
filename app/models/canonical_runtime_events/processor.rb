module CanonicalRuntimeEvents
  class Processor
    attr_reader :audit_event, :ui_changes

    def initialize(run:, event:)
      @run = run
      @event = event.with_indifferent_access
      @ui_changes = []
    end

    def process
      ApplicationRecord.transaction do
        case event.fetch(:type)
        when "session.started" then record_session_started
        when "actor.delegated" then mint_passport
        when "runtime.event" then record_runtime_event
        when "tool.requested" then authorize_tool_action
        when "tool.observed" then record_observed_tool_action
        when "tool.finished" then finish_tool_action
        when "tool.blocked" then block_tool_action
        when "session.finished" then finish_session
        else
          raise ArgumentError, "Unknown runtime event type: #{event[:type]}"
        end
      end
    end

    private

    attr_reader :run, :event

    def record_session_started
      run.update!(status: "running", started_at: started_at)
      mark_ui_changes(:run_header, :session_sidebar) if run.saved_change_to_status?
      audit!("session.started", result: "started", action_summary: "#{run.runtime_label} session started")
      run
    end

    def mint_passport
      parent = event[:parent_actor_ref].present? ? run.passports.find_by!(actor_ref: event[:parent_actor_ref]) : nil
      rules = event.fetch(:rules).with_indifferent_access
      created_passport = false

      passport = run.passports.find_or_create_by!(actor_ref: event.fetch(:actor_ref)) do |record|
        created_passport = true
        record.parent = parent
        record.actor_name = event.fetch(:actor_name)
        record.actor_kind = event.fetch(:actor_kind)
        record.provider = event.fetch(:provider)
        record.task = event[:task]
        record.status = "active"
        record.read_rule = rules.fetch(:read)
        record.edit_rule = rules.fetch(:edit)
        record.bash_rule = rules.fetch(:bash)
        record.web_rule = rules.fetch(:web)
        record.delegate_rule = rules.fetch(:delegate)
      end
      mark_ui_changes(:run_header, :passport_tree, :passport_detail) if created_passport

      audit!(
        "actor.delegated",
        passport: passport,
        result: "minted",
        capability: "delegate",
        action_summary: "#{passport.actor_name} passport minted"
      )

      passport
    end

    def authorize_tool_action
      passport = run.passports.find_by!(actor_ref: event.fetch(:actor_ref))
      action = find_or_create_tool_action!(passport)

      return action unless action.status == "requested"

      decision = passport.authorization_for(action.capability, action.request_text)

      case decision
      when "allow"
        action.update!(status: "allowed")
        mark_ui_changes(:passport_detail, :tool_action_list) if action.saved_change_to_status?
        audit!("tool.allowed", passport: passport, tool_action: action, result: "allowed", capability: action.capability, action_summary: action.action_summary)
      when "ask"
        action.update!(status: "asking")
        request = PermissionRequest.find_or_create_by!(tool_action: action) do |record|
          record.run = run
          record.passport = passport
          record.status = "pending"
          record.risk_level = event[:risk_level]
          record.risk_summary = event[:risk_summary]
          record.suggested_capability = event[:suggested_capability].presence || action.capability
          record.suggested_pattern = event[:suggested_pattern].presence || action.request_text
        end
        mark_ui_changes(:run_header, :session_sidebar, :permission_inbox, :passport_detail, :tool_action_list)
        audit!("permission.requested", passport: passport, tool_action: action, permission_request: request, result: "ask", capability: action.capability, action_summary: action.action_summary)
      else
        action.update!(status: "blocked", finished_at: occurred_at)
        mark_ui_changes(:passport_detail, :tool_action_list) if action.saved_change_to_status?
        audit!("tool.blocked", passport: passport, tool_action: action, result: "blocked", capability: action.capability, action_summary: action.action_summary)
      end

      action
    end

    def record_observed_tool_action
      passport = run.passports.find_by!(actor_ref: event.fetch(:actor_ref))
      action = find_or_create_tool_action!(passport)
      status = event[:status].presence_in(ToolAction::STATUSES) || "running"
      attributes = { status: status }
      attributes[:finished_at] = occurred_at if status.in?(%w[finished blocked failed])
      attributes[:exit_status] = event[:exit_status] if event.key?(:exit_status)
      action.update!(attributes)
      mark_ui_changes(:run_header, :passport_detail, :tool_action_list) if action.saved_changes?
      audit!("tool.observed", passport: passport, tool_action: action, result: "observed", capability: action.capability, action_summary: action.action_summary)
      action
    end

    def finish_tool_action
      action = terminal_tool_action
      action.update!(status: "finished", finished_at: occurred_at, exit_status: event[:exit_status])
      mark_ui_changes(:passport_detail, :tool_action_list) if action.saved_change_to_status?
      audit!("tool.finished", passport: action.passport, tool_action: action, result: "finished", capability: action.capability, action_summary: action.action_summary)
      action
    end

    def block_tool_action
      action = terminal_tool_action
      action.update!(status: "blocked", finished_at: occurred_at)
      mark_ui_changes(:passport_detail, :tool_action_list) if action.saved_change_to_status?
      audit!("tool.blocked", passport: action.passport, tool_action: action, result: "blocked", capability: action.capability, action_summary: action.action_summary)
      action
    end

    def finish_session
      run.update!(status: event[:status].presence || "completed", finished_at: occurred_at)
      mark_ui_changes(:run_header, :session_sidebar) if run.saved_change_to_status?
      audit!("session.finished", result: run.status, action_summary: "#{run.runtime_label} session #{run.status}")
      run
    end

    def record_runtime_event
      passport = event[:actor_ref].present? ? run.passports.find_by(actor_ref: event[:actor_ref]) : nil
      audit!(
        event[:event_kind].presence || "runtime.event",
        passport: passport,
        result: event[:result].presence || "observed",
        capability: event[:capability],
        action_summary: event[:action_summary]
      )
      mark_ui_changes(:run_header, :tool_action_list)
      run
    end

    def audit!(kind, result:, passport: nil, tool_action: nil, permission_request: nil, capability: nil, action_summary: nil)
      created_audit_event = false

      if event[:event_id].present?
        record = AuditEvent.find_or_create_by!(run: run, source_event_id: event[:event_id]) do |record|
          created_audit_event = true
          assign_audit_attributes(record, kind, result, passport, tool_action, permission_request, capability, action_summary)
        end
      else
        record = AuditEvent.create!(run: run) do |record|
          created_audit_event = true
          assign_audit_attributes(record, kind, result, passport, tool_action, permission_request, capability, action_summary)
        end
      end

      ensure_audit_event_matches!(record, kind, result, passport, tool_action, permission_request, capability, action_summary) unless created_audit_event
      @audit_event = record if created_audit_event
      record
    end

    def find_or_create_tool_action!(passport)
      if event[:event_id].present?
        run.tool_actions.find_or_create_by!(source_event_id: event[:event_id]) do |record|
          assign_tool_action_attributes(record, passport)
        end
      else
        run.tool_actions.create! do |record|
          assign_tool_action_attributes(record, passport)
        end
      end
    end

    def terminal_tool_action
      source_event_id = event.fetch(:source_event_id)
      run.tool_actions.find_by(source_event_id: source_event_id) || create_observed_tool_action!(source_event_id)
    end

    def create_observed_tool_action!(source_event_id)
      passport = run.passports.find_by!(actor_ref: event.fetch(:actor_ref))
      run.tool_actions.create!(source_event_id: source_event_id) do |record|
        assign_tool_action_attributes(record, passport)
        record.status = "running"
      end
    end

    def assign_tool_action_attributes(record, passport)
      record.passport = passport
      record.capability = event.fetch(:capability)
      record.action_kind = event.fetch(:action_kind)
      record.action_summary = event.fetch(:action_summary)
      record.command = event[:command]
      record.path = event[:path]
      record.canonical_payload = event.to_h
      record.status = "requested"
      record.requested_at = occurred_at
    end

    def assign_audit_attributes(record, kind, result, passport, tool_action, permission_request, capability, action_summary)
      record.passport = passport
      record.tool_action = tool_action
      record.permission_request = permission_request
      record.event_kind = kind
      record.actor_lineage = passport&.lineage_label
      record.capability = capability
      record.action_summary = action_summary
      record.result = result
      record.occurred_at = occurred_at
    end

    def ensure_audit_event_matches!(record, kind, result, passport, tool_action, permission_request, capability, action_summary)
      return if record.event_kind == kind &&
        record.result == result &&
        record.passport_id == passport&.id &&
        record.tool_action_id == tool_action&.id &&
        record.permission_request_id == permission_request&.id &&
        record.capability == capability &&
        record.action_summary == action_summary

      raise ArgumentError, "Runtime event id #{event[:event_id]} already belongs to another audit event"
    end

    def occurred_at
      @occurred_at ||= event[:occurred_at].present? ? Time.zone.parse(event[:occurred_at].to_s) : Time.current
    end

    def started_at
      @started_at ||= event[:started_at].present? ? Time.zone.parse(event[:started_at].to_s) : occurred_at
    end

    def mark_ui_changes(*changes)
      @ui_changes |= changes
    end
  end
end

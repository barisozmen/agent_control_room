require "digest"

module ObservedRuntimeSessions
  class Ingestor
    OWNER_REF = "local-owner"
    MAIN_AGENT_REF = "main-agent"
    OWNER_RULES = { read: "allow", edit: "allow", bash: "allow", web: "allow", delegate: "allow" }.freeze
    AGENT_RULES = { read: "allow", edit: "ask", bash: "ask", web: "ask", delegate: "ask" }.freeze
    PROCESSABLE_TYPES = %w[
      session.started
      actor.delegated
      tool.requested
      tool.finished
      tool.blocked
      session.finished
    ].freeze

    attr_reader :event, :run, :result, :runtime, :audit_event, :ui_changes

    def initialize(runtime_name:, event:)
      @runtime = RuntimeAdapters::Registry.fetch(runtime_name)
      @event = event.with_indifferent_access
      @ui_changes = []
    end

    def process
      @run = find_or_create_run!
      ensure_base_passports!
      ensure_actor_passport! if actor_event?

      @result = processable? ? process_canonical_event : run
      touch_run!
      self
    end

    private

    def find_or_create_run!
      Run.find_or_initialize_by(runtime_name: runtime.name, runtime_session_id: session_id).tap do |record|
        new_run = record.new_record?
        record.project_path = project_path
        record.mode = "observed"
        record.status = "running" if record.new_record? || record.status.in?(%w[starting completed interrupted failed])
        record.started_at ||= occurred_at
        record.title = title
        record.observed_pid = observed_pid if observed_pid.present?
        record.last_seen_at = occurred_at
        record.save!

        mark_ui_changes(:session_sidebar) if new_run || record.saved_change_to_title? || record.saved_change_to_project_path? || record.saved_change_to_status?
        mark_ui_changes(:run_header) if record.saved_change_to_status?
      end
    end

    def process_canonical_event
      processor = CanonicalRuntimeEvents::Processor.new(
        run: run,
        event: canonical_event
      )
      processor.process.tap do
        @audit_event = processor.audit_event
        mark_ui_changes(*processor.ui_changes)
      end
    end

    def canonical_event
      event.merge(
        run_id: run.id,
        runtime_name: runtime.name,
        session_id: session_id,
        actor_ref: actor_ref,
        occurred_at: occurred_at.iso8601
      )
    end

    def processable?
      PROCESSABLE_TYPES.include?(event[:type])
    end

    def actor_event?
      event[:type].in?(%w[tool.requested tool.finished tool.blocked actor.delegated])
    end

    def ensure_base_passports!
      created_owner = false
      owner = run.passports.find_or_create_by!(actor_ref: OWNER_REF) do |passport|
        created_owner = true
        assign_passport(passport, actor_name: local_owner_name, actor_kind: "human", provider: "local", parent: nil, task: "Local machine owner", rules: OWNER_RULES)
      end

      created_agent = false
      run.passports.find_or_create_by!(actor_ref: MAIN_AGENT_REF) do |passport|
        created_agent = true
        assign_passport(passport, actor_name: runtime.main_agent_name, actor_kind: "agent", provider: runtime.provider, parent: owner, task: runtime.observed_task, rules: AGENT_RULES)
      end

      mark_ui_changes(:run_header, :passport_tree) if created_owner || created_agent
    end

    def ensure_actor_passport!
      return if actor_ref.blank? || run.passports.exists?(actor_ref: actor_ref)

      parent = run.passports.find_by(actor_ref: parent_actor_ref) || run.passports.find_by!(actor_ref: MAIN_AGENT_REF)
      run.passports.create! do |passport|
        assign_passport(
          passport,
          actor_name: event[:actor_name].presence || actor_ref,
          actor_kind: event[:actor_kind].presence || "agent",
          provider: event[:provider].presence || runtime.provider,
          parent: parent,
          task: event[:task].presence || "Observed #{runtime.label} actor",
          rules: scoped_rules(parent, event[:rules])
        )
        passport.actor_ref = actor_ref
      end
      mark_ui_changes(:run_header, :passport_tree)
    end

    def assign_passport(passport, actor_name:, actor_kind:, provider:, parent:, task:, rules:)
      passport.parent = parent
      passport.actor_name = actor_name
      passport.actor_kind = actor_kind
      passport.provider = provider
      passport.task = task
      passport.status = "active"
      passport.read_rule = rules.fetch(:read)
      passport.edit_rule = rules.fetch(:edit)
      passport.bash_rule = rules.fetch(:bash)
      passport.web_rule = rules.fetch(:web)
      passport.delegate_rule = rules.fetch(:delegate)
    end

    def scoped_rules(parent, raw_rules)
      requested = AGENT_RULES.merge((raw_rules || {}).with_indifferent_access.slice(*Passport::CAPABILITIES).symbolize_keys)

      Passport::CAPABILITIES.each_with_object({}) do |capability, rules|
        requested_rule = requested.fetch(capability.to_sym)
        parent_rule = parent.rule_for(capability)
        rules[capability.to_sym] = Passport::RULE_RANK.fetch(requested_rule) <= Passport::RULE_RANK.fetch(parent_rule) ? requested_rule : parent_rule
      end
    end

    def touch_run!
      run.update!(last_seen_at: occurred_at, title: title)
      mark_ui_changes(:session_sidebar) if run.saved_change_to_title?
    end

    def session_id
      @session_id ||= event[:session_id].presence ||
        event[:sessionID].presence ||
        event.dig(:session, :id).presence ||
        event.dig(:properties, :sessionID).presence ||
        event.dig(:properties, :session_id).presence ||
        "#{runtime.name}-process-#{observed_pid || Digest::SHA256.hexdigest("#{project_path}:#{title}")[0, 16]}"
    end

    def project_path
      event[:project_path].presence || event[:directory].presence || event[:worktree].presence || Dir.home
    end

    def title
      event[:title].presence || File.basename(project_path.to_s).presence || session_id
    end

    def observed_pid
      event[:pid].presence || event[:process_id].presence
    end

    def actor_ref
      @actor_ref ||= event[:actor_ref].presence || MAIN_AGENT_REF
    end

    def parent_actor_ref
      event[:parent_actor_ref].presence || (actor_ref == MAIN_AGENT_REF ? OWNER_REF : MAIN_AGENT_REF)
    end

    def local_owner_name
      ENV["USER"].presence || "Local owner"
    end

    def occurred_at
      @occurred_at ||= event[:occurred_at].present? ? Time.zone.parse(event[:occurred_at].to_s) : Time.current
    end

    def mark_ui_changes(*changes)
      @ui_changes |= changes
    end
  end
end

require "json"
require "set"

module RuntimeAdapters
  class OpencodeSessionLogScanner
    MAIN_AGENT_REF = "main-agent"
    AGENT_RULES = { read: "allow", edit: "ask", bash: "ask", web: "ask", delegate: "ask" }.freeze

    Session = Data.define(:id, :title, :project_path, :created_at, :updated_at, :status, :parent_id) do
      def runtime_name
        "opencode"
      end

      def root?
        parent_id.blank?
      end

      def to_runtime_event
        {
          runtime_name: runtime_name,
          type: event_type,
          event_id: "opencode-session-log-#{id}-#{event_suffix}",
          session_id: id,
          title: title,
          project_path: project_path,
          started_at: created_at.iso8601,
          last_seen_at: updated_at.iso8601,
          occurred_at: occurred_at.iso8601,
          status: status
        }
      end

      private

      def event_type
        status == "running" ? "session.started" : "session.finished"
      end

      def event_suffix
        status == "running" ? "started" : "finished"
      end

      def occurred_at
        status == "running" ? created_at : updated_at
      end
    end

    DelegatedSession = Data.define(:session, :root_session, :parent_session) do
      def runtime_name
        "opencode"
      end

      def to_runtime_event
        {
          runtime_name: runtime_name,
          type: "actor.delegated",
          event_id: "opencode-session-log-#{session.id}-delegated",
          session_id: root_session.id,
          title: root_session.title,
          project_path: root_session.project_path,
          actor_ref: actor_ref_for(session),
          parent_actor_ref: parent_actor_ref,
          actor_name: actor_name_for(session),
          actor_kind: "agent",
          provider: "opencode",
          task: session.title,
          rules: AGENT_RULES,
          started_at: root_session.created_at.iso8601,
          last_seen_at: [ root_session.updated_at, session.updated_at ].max.iso8601,
          occurred_at: session.created_at.iso8601,
          canonical_payload: {
            source: "opencode_session_log",
            opencode_session_id: session.id,
            parent_opencode_session_id: session.parent_id
          }
        }
      end

      private

      def parent_actor_ref
        return MAIN_AGENT_REF if parent_session.blank? || parent_session.root?

        actor_ref_for(parent_session)
      end

      def actor_ref_for(opencode_session)
        "opencode-session-#{opencode_session.id}"
      end

      def actor_name_for(opencode_session)
        agent_name = opencode_session.title.to_s[/\(@([A-Za-z0-9_-]+)\s+subagent\)/, 1]
        return "opencode/#{agent_name}" if agent_name.present?

        "opencode/subagent"
      end
    end

    def initialize(opencode_home: ENV.fetch("OPENCODE_HOME", File.join(Dir.home, ".local", "share", "opencode")), limit: 25, active_project_paths: nil, process_scanner: RuntimeAdapters::OpencodeProcessScanner.new)
      @opencode_home = Pathname.new(opencode_home)
      @limit = limit
      @projects_by_id = {}
      @active_project_paths = active_project_paths
      @process_scanner = process_scanner
    end

    def sessions
      loaded_sessions = session_paths.filter_map { |path| session_for(path) }
      sessions_by_id = loaded_sessions.index_by(&:id)
      root_sessions = loaded_sessions.select { |session| root_session?(session, sessions_by_id) }
      activity_by_root_id = activity_by_root_id_for(loaded_sessions, sessions_by_id)
      running_session_ids = running_session_ids_for(root_sessions)

      selected_roots = root_sessions
        .map { |session| session.with(status: running_session_ids.include?(session.id) ? "running" : "completed") }
        .sort_by { |session| -activity_by_root_id.fetch(session.id, session.updated_at).to_f }
        .first(limit)

      selected_root_ids = selected_roots.map(&:id).to_set
      delegated_sessions = delegated_sessions_for(loaded_sessions, sessions_by_id, selected_root_ids)

      selected_roots + delegated_sessions
    end

    private

    attr_reader :opencode_home, :limit, :projects_by_id, :active_project_paths, :process_scanner

    def session_paths
      Dir.glob(opencode_home.join("storage", "session", "*", "*.json"))
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    def session_for(path)
      payload = read_json(path)
      return if payload.blank?

      id = payload["id"].presence || File.basename(path, ".json")
      project_id = payload["projectID"].presence || Pathname.new(path).dirname.basename.to_s
      project = project_for(project_id)
      project_path = payload["directory"].presence || project&.fetch("worktree", nil).presence
      return if id.blank? || project_path.blank?

      created_at = time_from(payload.dig("time", "created")) || file_mtime(path)
      updated_at = time_from(payload.dig("time", "updated")) || created_at

      Session.new(
        id: id,
        title: payload["title"].presence || File.basename(project_path),
        project_path: project_path,
        created_at: created_at,
        updated_at: updated_at,
        status: "completed",
        parent_id: payload["parentID"].presence
      )
    rescue StandardError => error
      Rails.logger.debug("OpenCode session log skipped #{path}: #{error.class}: #{error.message}")
      nil
    end

    def root_session?(session, sessions_by_id)
      session.parent_id.blank? || !sessions_by_id.key?(session.parent_id)
    end

    def delegated_sessions_for(sessions, sessions_by_id, selected_root_ids)
      sessions
        .reject { |session| root_session?(session, sessions_by_id) }
        .filter_map do |session|
          root_session = root_for(session, sessions_by_id)
          next if root_session.blank? || !selected_root_ids.include?(root_session.id)

          DelegatedSession.new(
            session: session,
            root_session: root_session,
            parent_session: sessions_by_id[session.parent_id]
          )
        end
        .sort_by { |delegation| [ delegation_depth(delegation.session, sessions_by_id), delegation.session.created_at, delegation.session.id ] }
    end

    def activity_by_root_id_for(sessions, sessions_by_id)
      sessions.each_with_object({}) do |session, activity_by_root_id|
        root = root_for(session, sessions_by_id)
        next if root.blank?

        activity_by_root_id[root.id] = [ activity_by_root_id[root.id] || root.updated_at, session.updated_at ].max
      end
    end

    def root_for(session, sessions_by_id)
      current = session
      seen_session_ids = Set.new

      while current.parent_id.present? && sessions_by_id.key?(current.parent_id)
        return if seen_session_ids.include?(current.id)

        seen_session_ids.add(current.id)
        current = sessions_by_id.fetch(current.parent_id)
      end

      current
    end

    def delegation_depth(session, sessions_by_id)
      depth = 0
      current = session
      seen_session_ids = Set.new

      while current.parent_id.present? && sessions_by_id.key?(current.parent_id)
        return depth if seen_session_ids.include?(current.id)

        seen_session_ids.add(current.id)
        depth += 1
        current = sessions_by_id.fetch(current.parent_id)
      end

      depth
    end

    def project_for(project_id)
      return if project_id.blank?

      projects_by_id.fetch(project_id) do
        projects_by_id[project_id] = read_json(opencode_home.join("storage", "project", "#{project_id}.json"))
      end
    end

    def read_json(path)
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
      Rails.logger.debug("OpenCode metadata skipped #{path}: #{error.class}: #{error.message}")
      nil
    end

    def time_from(value)
      return if value.blank?

      numeric = Float(value, exception: false)
      return Time.zone.at(numeric > 10_000_000_000 ? numeric / 1_000.0 : numeric) if numeric

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def file_mtime(path)
      File.mtime(path).in_time_zone
    end

    def running_session_ids_for(sessions)
      active_paths = active_paths_for_scan
      return Set.new if active_paths.empty?

      sessions
        .group_by(&:project_path)
        .filter_map { |project_path, project_sessions| project_sessions.max_by(&:updated_at)&.id if active_paths.include?(project_path) }
        .to_set
    end

    def active_paths_for_scan
      paths = active_project_paths || process_scanner.sessions.map(&:cwd)
      paths.compact.to_set
    rescue StandardError => error
      Rails.logger.debug("OpenCode active process scan skipped: #{error.class}: #{error.message}")
      Set.new
    end
  end
end

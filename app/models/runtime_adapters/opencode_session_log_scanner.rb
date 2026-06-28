require "json"
require "set"

module RuntimeAdapters
  class OpencodeSessionLogScanner
    Session = Data.define(:id, :title, :project_path, :created_at, :updated_at, :status) do
      def runtime_name
        "opencode"
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

    def initialize(opencode_home: ENV.fetch("OPENCODE_HOME", File.join(Dir.home, ".local", "share", "opencode")), limit: 25, active_project_paths: nil, process_scanner: RuntimeAdapters::OpencodeProcessScanner.new)
      @opencode_home = Pathname.new(opencode_home)
      @limit = limit
      @projects_by_id = {}
      @active_project_paths = active_project_paths
      @process_scanner = process_scanner
    end

    def sessions
      loaded_sessions = session_paths.filter_map { |path| session_for(path) }
      running_session_ids = running_session_ids_for(loaded_sessions)

      loaded_sessions
        .map { |session| session.with(status: running_session_ids.include?(session.id) ? "running" : "completed") }
        .sort_by { |session| -session.updated_at.to_f }
        .first(limit)
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
        status: "completed"
      )
    rescue StandardError => error
      Rails.logger.debug("OpenCode session log skipped #{path}: #{error.class}: #{error.message}")
      nil
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

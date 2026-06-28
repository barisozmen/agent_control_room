require "json"
require "fileutils"

module RuntimeAdapters
  class CodexSessionLogScanner
    STATE_VERSION = 1

    def initialize(codex_home: ENV.fetch("CODEX_HOME", File.join(Dir.home, ".codex")), limit: 12, state_path: default_state_path)
      @codex_home = Pathname.new(codex_home)
      @limit = limit
      @state_path = state_path && Pathname.new(state_path)
    end

    def sessions
      paths = recent_log_paths
      return [] if paths.empty?

      state = load_state
      next_paths = {}

      paths.flat_map do |path|
        events, entry = events_for(path, state[path.to_s])
        next_paths[path.to_s] = entry if entry
        events
      end.tap do
        save_state(next_paths)
      end
    end

    private

    attr_reader :codex_home, :limit, :state_path

    def recent_log_paths
      Dir.glob(codex_home.join("sessions", "**", "rollout-*.jsonl"))
        .sort_by { |path| -File.mtime(path).to_f }
        .first(limit)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    def events_for(path, previous_entry)
      stat = File.stat(path)
      offset = reusable_cursor?(previous_entry, stat) ? previous_entry.fetch("offset").to_i : 0
      context = offset.positive? ? context_from(previous_entry) : {}
      events = []

      File.open(path, "rb") do |file|
        file.seek(offset)
        translator = RuntimeAdapters::CodexJsonlTranslator.new(
          session_id: context["session_id"],
          project_path: context["project_path"],
          title: context["title"],
          occurred_at: time_from(context["occurred_at"])
        )

        while (line = file.gets)
          line.force_encoding(Encoding::UTF_8)

          unless line.lstrip.start_with?("{")
            break unless line.end_with?("\n")

            offset = file.pos
            next
          end

          begin
            record = JSON.parse(line)
          rescue JSON::ParserError
            break unless line.end_with?("\n")

            offset = file.pos
            next
          end

          events.concat(translator.events_for(record))
          update_context(context, record)
          offset = file.pos
        end
      end

      [ events, state_entry(stat, offset, context) ]
    rescue Errno::ENOENT, Errno::EACCES => error
      Rails.logger.debug("Codex session log skipped #{path}: #{error.class}: #{error.message}")
      [ [], nil ]
    end

    def reusable_cursor?(entry, stat)
      return false unless entry.is_a?(Hash)

      offset = entry["offset"].to_i
      return false if offset.negative? || offset > stat.size

      inode = integer_from(entry["inode"])
      dev = integer_from(entry["dev"])
      return true if inode.nil? || dev.nil?

      inode == stat.ino && dev == stat.dev
    end

    def context_from(entry)
      entry.slice("session_id", "project_path", "title", "occurred_at").compact
    end

    def update_context(context, record)
      record = record.with_indifferent_access
      context["occurred_at"] = record[:timestamp].to_s if record[:timestamp].present?

      case record[:type]
      when "session_meta"
        payload = record.fetch(:payload, {}).with_indifferent_access
        context["session_id"] = payload[:id].presence || payload[:session_id].presence || context["session_id"]
        context["project_path"] = payload[:cwd].presence || context["project_path"]
        context["title"] = payload[:title].presence || context["title"]
      when "thread.started"
        context["session_id"] = record[:thread_id].presence || context["session_id"]
      end
    end

    def state_entry(stat, offset, context)
      {
        "offset" => offset,
        "inode" => stat.ino,
        "dev" => stat.dev,
        "size" => [ stat.size, offset ].max,
        "mtime" => stat.mtime.to_f,
        "session_id" => context["session_id"],
        "project_path" => context["project_path"],
        "title" => context["title"],
        "occurred_at" => context["occurred_at"]
      }.compact
    end

    def load_state
      return {} unless state_path&.exist?

      payload = JSON.parse(File.read(state_path))
      paths = payload.fetch("paths", {})
      paths.is_a?(Hash) ? paths : {}
    rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError => error
      Rails.logger.debug("Codex session log scanner state skipped: #{error.class}: #{error.message}")
      {}
    end

    def save_state(paths)
      return unless state_path

      FileUtils.mkdir_p(state_path.dirname)
      tmp_path = state_path.sub_ext(".#{Process.pid}.tmp")
      File.write(tmp_path, JSON.generate({ "version" => STATE_VERSION, "paths" => paths }))
      File.rename(tmp_path, state_path)
    rescue Errno::ENOENT, Errno::EACCES => error
      Rails.logger.debug("Codex session log scanner state not saved: #{error.class}: #{error.message}")
    ensure
      FileUtils.rm_f(tmp_path) if defined?(tmp_path) && tmp_path&.exist?
    end

    def integer_from(value)
      Integer(value, exception: false)
    end

    def time_from(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def default_state_path
      Rails.root.join("tmp", "runtime_adapters", "codex_session_log_scanner_state.json")
    end
  end
end

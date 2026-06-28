require "json"

module RuntimeAdapters
  class CodexSessionLogScanner
    def initialize(codex_home: ENV.fetch("CODEX_HOME", File.join(Dir.home, ".codex")), limit: 12)
      @codex_home = Pathname.new(codex_home)
      @limit = limit
    end

    def sessions
      recent_log_paths.flat_map { |path| events_for(path) }
    end

    private

    attr_reader :codex_home, :limit

    def recent_log_paths
      Dir.glob(codex_home.join("sessions", "**", "rollout-*.jsonl"))
        .sort_by { |path| -File.mtime(path).to_f }
        .first(limit)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    def events_for(path)
      translator = RuntimeAdapters::CodexJsonlTranslator.new
      File.foreach(path).flat_map do |line|
        next [] unless line.lstrip.start_with?("{")

        translator.events_for(JSON.parse(line))
      rescue JSON::ParserError
        []
      end
    rescue Errno::ENOENT, Errno::EACCES => error
      Rails.logger.debug("Codex session log skipped #{path}: #{error.class}: #{error.message}")
      []
    end
  end
end

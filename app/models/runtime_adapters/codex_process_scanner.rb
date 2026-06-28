require "open3"
require "timeout"

module RuntimeAdapters
  class CodexProcessScanner
    Session = Data.define(:pid, :started_at, :command, :cwd) do
      def to_runtime_event
        {
          type: "session.started",
          event_id: "#{session_id}-started",
          session_id: session_id,
          title: "Codex",
          project_path: cwd,
          pid: pid,
          occurred_at: started_at.iso8601
        }
      end

      private

      def session_id
        "codex-process-#{pid}-#{started_at.to_i}"
      end
    end

    def initialize(command_runner: Open3.method(:capture2e), limit: 25, timeout_seconds: 1.5)
      @command_runner = command_runner
      @limit = limit
      @timeout_seconds = timeout_seconds
    end

    def sessions
      ps_output
        .each_line
        .filter_map { |line| parse_process_line(line) }
        .select { |process| codex_cli_session?(process[:command]) }
        .first(limit)
        .filter_map { |process| session_for(process) }
    end

    private

    attr_reader :command_runner, :limit, :timeout_seconds

    def ps_output
      capture("ps", "-axo", "pid=,lstart=,command=")
    end

    def parse_process_line(line)
      parts = line.strip.split(/\s+/, 7)
      return if parts.size < 7

      pid, weekday, month, day, clock, year, command = parts
      {
        pid: Integer(pid, exception: false),
        started_at: parse_started_at([ weekday, month, day, clock, year ].join(" ")),
        command: command.to_s.strip
      }
    end

    def parse_started_at(value)
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      Time.current
    end

    def codex_cli_session?(command)
      return false unless command.match?(%r{(^|\s|/)codex(\s|$)})
      return false if command.match?(/\bcodex\s+app-server\b/)
      return false if command.match?(/\bcodex\s+debug\b/)
      return false if command.match?(/\bcodex\s+plugin\b/)

      true
    end

    def session_for(process)
      return unless process[:pid].present?

      cwd = cwd_for(process[:pid])
      return if cwd.blank?

      Session.new(
        pid: process[:pid],
        started_at: process[:started_at],
        command: process[:command],
        cwd: cwd
      )
    end

    def cwd_for(pid)
      proc_cwd = "/proc/#{pid}/cwd"
      return File.realpath(proc_cwd) if File.exist?(proc_cwd)

      capture("lsof", "-a", "-p", pid.to_s, "-d", "cwd", "-Fn")
        .each_line
        .find { |line| line.start_with?("n") }
        &.delete_prefix("n")
        &.strip
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    def capture(*command)
      output, status = Timeout.timeout(timeout_seconds) { command_runner.call(*command) }
      return "" if status.respond_to?(:success?) && !status.success?

      output.to_s
    rescue Timeout::Error, Errno::ENOENT => error
      Rails.logger.debug("Codex process scan skipped #{command.first}: #{error.class}: #{error.message}")
      ""
    end
  end
end

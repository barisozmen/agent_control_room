require "fileutils"

module RuntimeAdapters
  class CliProcess
    class Unavailable < StandardError; end

    class AsyncProcessMonitor
      def initialize(process)
        @process = process
      end

      def watch(pid, &callback)
        waiter = process.detach(pid)
        return unless waiter.respond_to?(:value)

        Thread.new do
          status = waiter.value
          Rails.application.executor.wrap { callback.call(status) }
        rescue StandardError => error
          Rails.logger.error("Failed to record runtime process exit for pid #{pid}: #{error.class}: #{error.message}")
        end
      end

      private

      attr_reader :process
    end

    class Noop
      def start_demo!(run:)
        nil
      end
    end

    def initialize(runtime:, command:, demo_args:, process: Process, check_available: true, monitor: nil, version_args: [ "--version" ])
      @runtime = runtime
      @command = command
      @demo_args = demo_args
      @process = process
      @check_available = check_available
      @monitor = monitor || AsyncProcessMonitor.new(process)
      @version_args = version_args
    end

    def start_demo!(run:)
      ensure_available!

      pid = process.spawn(
        adapter_environment(run),
        command,
        *demo_args,
        chdir: run.project_path,
        out: log_path(run).to_s,
        err: [ :child, :out ]
      )
      record_process_started!(run, pid)
      monitor.watch(pid) { |status| record_process_finished!(run.id, pid, status) }
      pid
    rescue Errno::ENOENT => error
      raise Unavailable, error.message
    end

    private

    attr_reader :runtime, :command, :demo_args, :process, :check_available, :monitor, :version_args

    def ensure_available!
      return unless check_available
      return if system(command, *version_args, out: File::NULL, err: File::NULL)

      raise Unavailable, unavailable_message
    rescue Errno::ENOENT
      raise Unavailable, unavailable_message
    end

    def unavailable_message
      "`#{command}` is not available. Install #{runtime.label} or set #{runtime.command_env_key}."
    end

    def adapter_environment(run)
      {
        "AGENT_PASSPORTS_RUNTIME_NAME" => runtime.name,
        "AGENT_PASSPORTS_RUN_ID" => run.id.to_s,
        "AGENT_PASSPORTS_BRIDGE_TOKEN" => run.bridge_token,
        "AGENT_PASSPORTS_RUNTIME_EVENTS_URL" => runtime_events_url
      }
    end

    def runtime_events_url
      "http://127.0.0.1:#{server_port}/runtime_events"
    end

    def server_port
      ENV["PORT"].presence || resolved_dev_port || "3000"
    end

    def resolved_dev_port
      script = Rails.root.join("bin/find_server_port")
      return unless script.exist?

      IO.popen([ script.to_s ], &:read).to_s.strip.presence
    rescue StandardError => error
      Rails.logger.warn("Failed to resolve dev server port: #{error.class}: #{error.message}")
      nil
    end

    def log_path(run)
      FileUtils.mkdir_p(Rails.root.join("log"))
      Rails.root.join("log", "#{runtime.name.tr("_", "-")}-demo-run-#{run.id}.log")
    end

    def record_process_started!(run, pid)
      AuditEvent.create!(
        run: run,
        event_kind: "adapter.process_started",
        result: "started",
        action_summary: "#{runtime.label} process started with pid #{pid}",
        occurred_at: Time.current
      )
    end

    def record_process_finished!(run_id, pid, status)
      run = Run.find_by(id: run_id)
      return unless run

      result = process_result(status)
      summary = process_finished_summary(pid, status, result)
      occurred_at = Time.current

      run.with_lock do
        if run.status.in?(%w[starting running])
          attributes = { status: result, finished_at: occurred_at }
          attributes[:error_message] = summary unless result == "completed"
          run.update!(attributes)
        end

        AuditEvent.create!(
          run: run,
          event_kind: "adapter.process_finished",
          result: result,
          action_summary: summary,
          occurred_at: occurred_at
        )
      end

      ingest_process_log!(run)
      run.reload.broadcast_control_room!
    end

    def ingest_process_log!(_run)
      nil
    end

    def process_result(status)
      return "completed" if status.respond_to?(:success?) && status.success?
      return "interrupted" if status.respond_to?(:signaled?) && status.signaled?

      "failed"
    end

    def process_finished_summary(pid, status, result)
      if status.respond_to?(:exitstatus) && status.exitstatus.present?
        "#{runtime.label} process #{result} with pid #{pid} (exit #{status.exitstatus})"
      elsif status.respond_to?(:termsig) && status.termsig.present?
        "#{runtime.label} process #{result} with pid #{pid} (signal #{status.termsig})"
      else
        "#{runtime.label} process #{result} with pid #{pid}"
      end
    end
  end
end

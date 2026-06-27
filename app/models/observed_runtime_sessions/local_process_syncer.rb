module ObservedRuntimeSessions
  class LocalProcessSyncer
    SCAN_TTL = 10.seconds
    SCAN_MUTEX = Mutex.new

    def self.sync!(scanners: nil)
      new(scanners: scanners).sync!
    end

    def self.sync_if_stale!(scanners: nil, now: Time.current, ttl: SCAN_TTL)
      skip = reserve_scan(now: now, ttl: ttl)
      if skip
        log_scan_skip(skip.fetch(:reason), skip.fetch(:since), now, ttl)
        return []
      end

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sync!(scanners: scanners).tap do |sessions|
        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000).round(1)
        Rails.logger.info("Local runtime scan completed in #{elapsed_ms}ms; imported #{sessions.size} session(s)")
      end
    ensure
      finish_scan if skip.nil?
    end

    def self.reset_scan_debounce!
      SCAN_MUTEX.synchronize do
        @scan_in_progress = false
        @last_scan_finished_at = nil
        @last_scan_started_at = nil
      end
    end

    def initialize(scanners: nil)
      @scanners = scanners || default_scanners
    end

    def sync!
      scanners.flat_map do |scanner|
        scanner.sessions.filter_map { |session| ingest(session) }
      rescue StandardError => error
        Rails.logger.warn("Local runtime scan failed for #{scanner.class.name}: #{error.class}: #{error.message}")
        []
      end
    end

    private

    attr_reader :scanners

    def default_scanners
      [ RuntimeAdapters::CodexProcessScanner.new ]
    end

    def ingest(session)
      event = session.respond_to?(:to_runtime_event) ? session.to_runtime_event : session
      ObservedRuntimeSessions::Ingestor.new(runtime_name: "codex", event: event).process
    end

    def self.reserve_scan(now:, ttl:)
      SCAN_MUTEX.synchronize do
        return { reason: "already running", since: @last_scan_started_at || now } if @scan_in_progress

        if @last_scan_finished_at && now < @last_scan_finished_at + ttl
          return { reason: "recently completed", since: @last_scan_finished_at }
        end

        @scan_in_progress = true
        @last_scan_started_at = now
        nil
      end
    end
    private_class_method :reserve_scan

    def self.finish_scan
      SCAN_MUTEX.synchronize do
        @scan_in_progress = false
        @last_scan_finished_at = Time.current
      end
    end
    private_class_method :finish_scan

    def self.log_scan_skip(reason, since, now, ttl)
      age_ms = ((now - since) * 1_000).round(1)
      Rails.logger.info("Local runtime scan skipped (#{reason}); last scan activity #{age_ms}ms ago; ttl #{ttl.to_f}s")
    end
    private_class_method :log_scan_skip
  end
end

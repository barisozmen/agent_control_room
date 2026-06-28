require "json"

module RuntimeAdapters
  class CodexRunLogIngestor
    def initialize(run:, path:)
      @run = run
      @path = Pathname.new(path)
    end

    def process
      return [] unless path.file?

      ensure_base_passports!
      translator = RuntimeAdapters::CodexJsonlTranslator.new(
        session_id: run.runtime_session_id || "run-#{run.id}",
        project_path: run.project_path,
        title: run.title.presence || "Codex: #{run.display_project}"
      )

      each_json_record.flat_map do |record|
        translator.events_for(record).filter_map { |event| process_event(event) }
      end
    end

    private

    attr_reader :run, :path

    def each_json_record
      return enum_for(:each_json_record) unless block_given?

      path.each_line do |line|
        next unless line.lstrip.start_with?("{")

        yield JSON.parse(line)
      rescue JSON::ParserError
        next
      end
    end

    def process_event(event)
      result = CanonicalRuntimeEvents::Processor.new(run: run, event: event).tap(&:process)
      result.audit_event
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, KeyError, ArgumentError => error
      Rails.logger.debug("Codex log event skipped: #{error.class}: #{error.message}")
      nil
    end

    def ensure_base_passports!
      owner = run.passports.find_or_create_by!(actor_ref: ObservedRuntimeSessions::Ingestor::OWNER_REF) do |passport|
        passport.actor_name = ENV["USER"].presence || "Local owner"
        passport.actor_kind = "human"
        passport.provider = "local"
        passport.task = "Local machine owner"
        passport.status = "active"
        assign_rules(passport, ObservedRuntimeSessions::Ingestor::OWNER_RULES)
      end

      run.passports.find_or_create_by!(actor_ref: ObservedRuntimeSessions::Ingestor::MAIN_AGENT_REF) do |passport|
        passport.parent = owner
        passport.actor_name = run.runtime.main_agent_name
        passport.actor_kind = "agent"
        passport.provider = run.runtime.provider
        passport.task = run.runtime.observed_task
        passport.status = "active"
        assign_rules(passport, ObservedRuntimeSessions::Ingestor::AGENT_RULES)
      end
    end

    def assign_rules(passport, rules)
      passport.read_rule = rules.fetch(:read)
      passport.edit_rule = rules.fetch(:edit)
      passport.bash_rule = rules.fetch(:bash)
      passport.web_rule = rules.fetch(:web)
      passport.delegate_rule = rules.fetch(:delegate)
    end
  end
end

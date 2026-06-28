require "json"
require "digest"

module RuntimeAdapters
  class CodexJsonlTranslator
    SENSITIVE_KEY_PATTERN = /(authorization|cookie|password|secret|token|api[_-]?key|credential)/i
    MAX_STRING_LENGTH = 1_200

    def initialize(session_id: nil, project_path: nil, title: nil, occurred_at: nil)
      @session_id = session_id
      @project_path = project_path
      @title = title
      @occurred_at = occurred_at
    end

    def events_for(record)
      record = record.with_indifferent_access
      @occurred_at = parsed_time(record[:timestamp]) || @occurred_at || Time.current

      case record[:type]
      when "session_meta" then session_meta_event(record)
      when "thread.started" then thread_started_event(record)
      when "item.started", "item.completed" then exec_item_events(record)
      when "response_item" then response_item_events(record)
      else
        []
      end
    end

    def self.sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, inner), sanitized|
          sanitized[key] = key.to_s.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : sanitize(inner)
        end
      when Array
        value.map { |inner| sanitize(inner) }
      when String
        value.length > MAX_STRING_LENGTH ? "#{value.first(MAX_STRING_LENGTH)}... [truncated]" : value
      else
        value
      end
    end

    private

    attr_reader :session_id, :project_path, :title, :occurred_at

    def session_meta_event(record)
      payload = record.fetch(:payload, {}).with_indifferent_access
      @session_id = payload[:id].presence || payload[:session_id].presence || session_id
      @project_path = payload[:cwd].presence || project_path
      @title = payload[:title].presence || codex_title(project_path)

      [ base_event("session.started", event_id: "#{event_prefix}-session-started") ]
    end

    def thread_started_event(record)
      @session_id = record[:thread_id].presence || session_id
      [ base_event("session.started", event_id: "#{event_prefix}-session-started") ]
    end

    def exec_item_events(record)
      item = record.fetch(:item, {}).with_indifferent_access
      return [] unless item[:type] == "command_execution"

      source_event_id = request_event_id(item[:id])
      if record[:type] == "item.started"
        [ observed_tool_event(item, source_event_id: source_event_id, status: "running", command: item[:command]) ]
      else
        [ finished_tool_event(item, source_event_id: source_event_id, exit_status: item[:exit_code]) ]
      end
    end

    def response_item_events(record)
      payload = record.fetch(:payload, {}).with_indifferent_access

      case payload[:type]
      when "function_call", "custom_tool_call"
        [ persisted_call_started_event(payload) ].compact
      when "function_call_output", "custom_tool_call_output"
        [ persisted_call_finished_event(payload) ].compact
      else
        []
      end
    end

    def persisted_call_started_event(payload)
      call_id = payload[:call_id].presence || payload[:id].presence
      return if call_id.blank?

      tool_name = payload[:name].presence || payload[:call_type].presence || "tool"
      arguments = parse_arguments(payload[:arguments] || payload[:input])
      source_event_id = request_event_id(call_id)

      case tool_name
      when "exec_command"
        command = arguments[:cmd].presence || arguments[:command].presence || payload[:arguments].to_s
        observed_tool_event(
          payload,
          source_event_id: source_event_id,
          status: "running",
          capability: "bash",
          action_kind: "shell_command",
          action_summary: command.to_s,
          command: command.to_s.presence
        )
      when "apply_patch"
        paths = paths_from_patch(payload[:input].presence || payload[:arguments].presence)
        observed_tool_event(
          payload,
          source_event_id: source_event_id,
          status: "running",
          capability: "edit",
          action_kind: "file_edit",
          action_summary: paths.any? ? "Apply patch: #{paths.first(3).join(", ")}" : "Apply patch",
          path: paths.first
        )
      else
        observed_tool_event(
          payload,
          source_event_id: source_event_id,
          status: "running",
          capability: "web",
          action_kind: tool_name.to_s,
          action_summary: tool_name.to_s.humanize
        )
      end
    end

    def persisted_call_finished_event(payload)
      call_id = payload[:call_id].presence || payload[:id].presence
      return if call_id.blank?

      finished_tool_event(payload, source_event_id: request_event_id(call_id), exit_status: exit_status_from_output(payload[:output]))
    end

    def observed_tool_event(raw, source_event_id:, status:, capability: "bash", action_kind: "shell_command", action_summary: nil, command: nil, path: nil)
      base_event(
        "tool.observed",
        event_id: source_event_id,
        actor_ref: "main-agent",
        capability: capability,
        action_kind: action_kind,
        action_summary: action_summary.presence || command.presence || path.presence || action_kind.to_s.humanize,
        command: command,
        path: path,
        status: status,
        observation_mode: "posthoc",
        raw_event: self.class.sanitize(raw)
      )
    end

    def finished_tool_event(raw, source_event_id:, exit_status: nil)
      base_event(
        "tool.finished",
        event_id: "#{source_event_id}-finished",
        source_event_id: source_event_id,
        actor_ref: "main-agent",
        capability: "bash",
        action_kind: "shell_command",
        action_summary: "Codex tool completed",
        exit_status: exit_status,
        observation_mode: "posthoc",
        raw_event: self.class.sanitize(raw)
      )
    end

    def base_event(type, **attributes)
      {
        type: type,
        session_id: session_id,
        title: title.presence || codex_title(project_path),
        project_path: project_path.presence || Dir.pwd,
        occurred_at: occurred_at.iso8601
      }.merge(attributes.compact)
    end

    def request_event_id(id)
      "#{event_prefix}-#{id || "unknown"}-requested"
    end

    def event_prefix
      "codex-jsonl-#{session_id.presence || Digest::SHA256.hexdigest("#{project_path}:#{title}")[0, 16]}"
    end

    def codex_title(path)
      basename = path.present? ? File.basename(path.to_s) : nil
      basename.present? ? "Codex: #{basename}" : "Codex"
    end

    def parsed_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_arguments(value)
      case value
      when Hash then value.with_indifferent_access
      when String
        JSON.parse(value).with_indifferent_access
      else
        {}.with_indifferent_access
      end
    rescue JSON::ParserError
      {}.with_indifferent_access
    end

    def paths_from_patch(value)
      value.to_s.scan(/^\*\*\* (?:Update|Add|Delete) File: (.+)$/).flatten.map(&:strip).uniq
    end

    def exit_status_from_output(value)
      value.to_s[/Process exited with code (-?\d+)/, 1]&.to_i
    end
  end
end

module ObservedOpencodeSessions
  class Ingestor
    attr_reader :delegate

    def initialize(event:)
      @delegate = ObservedRuntimeSessions::Ingestor.new(runtime_name: "opencode", event: event)
    end

    def process
      delegate.process
      self
    end

    def event
      delegate.event
    end

    def run
      delegate.run
    end

    def result
      delegate.result
    end

    def audit_event
      delegate.audit_event
    end

    def ui_changes
      delegate.ui_changes
    end
  end
end

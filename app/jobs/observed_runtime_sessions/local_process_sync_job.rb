module ObservedRuntimeSessions
  class LocalProcessSyncJob < ApplicationJob
    queue_as :default

    limits_concurrency(
      key: "local_process_sync",
      to: 1,
      duration: LocalProcessSyncer::SCAN_TTL,
      on_conflict: :discard
    )

    def perform
      LocalProcessSyncer.sync_if_stale!
    end
  end
end

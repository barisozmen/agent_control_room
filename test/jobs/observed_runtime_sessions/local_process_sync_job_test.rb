require "test_helper"

module ObservedRuntimeSessions
  class LocalProcessSyncJobTest < ActiveJob::TestCase
    test "performs stale-guarded local process sync" do
      calls = 0

      with_syncer_replaced_by(-> { calls += 1 }) do
        LocalProcessSyncJob.perform_now
      end

      assert_equal 1, calls
    end

    test "discards duplicate solid queue executions while one sync is active" do
      assert_equal 1, LocalProcessSyncJob.concurrency_limit
      assert_equal "local_process_sync", LocalProcessSyncJob.concurrency_key
      assert_equal LocalProcessSyncer::SCAN_TTL, LocalProcessSyncJob.concurrency_duration
      assert_equal :discard, LocalProcessSyncJob.concurrency_on_conflict
    end

    private

    def with_syncer_replaced_by(replacement)
      original = LocalProcessSyncer.method(:sync_if_stale!)
      LocalProcessSyncer.define_singleton_method(:sync_if_stale!, replacement)
      yield
    ensure
      LocalProcessSyncer.define_singleton_method(:sync_if_stale!, original)
    end
  end
end

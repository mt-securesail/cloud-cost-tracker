# In-memory holder for the latest result from each cost source (PRD 7.1).
# No database: a restarted task simply fetches again (R5).
#
# Thread-safe: the refresher writes from background threads while Puma threads
# read. Holds only the latest result per source, so memory never grows (N2).
class CostStore
  # result: the last good result (kept when a later fetch fails, PRD F9).
  # fetched_at: when that result was fetched. error: the last failure, if the
  # most recent attempt failed (error class name only, never a message).
  Entry = Data.define(:result, :fetched_at, :error, :attempted_at)

  EMPTY = Entry.new(result: nil, fetched_at: nil, error: nil, attempted_at: nil)

  @mutex = Mutex.new
  @entries = {}

  class << self
    def read(source)
      @mutex.synchronize { @entries.fetch(source, EMPTY) }
    end

    def record_success(source, result, at: Time.now.utc)
      @mutex.synchronize do
        @entries[source] = Entry.new(result: result, fetched_at: at, error: nil, attempted_at: at)
      end
    end

    def record_failure(source, error_name, at: Time.now.utc)
      @mutex.synchronize do
        previous = @entries.fetch(source, EMPTY)
        @entries[source] = previous.with(error: error_name, attempted_at: at)
      end
    end

    # For tests.
    def reset!
      @mutex.synchronize { @entries.clear }
    end
  end
end

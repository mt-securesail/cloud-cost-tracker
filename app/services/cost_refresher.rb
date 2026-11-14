# Background refresh of the cost data, inside the Puma process (PRD 7.1, R2-R6).
# Page views only read CostStore; they never call AWS.
#
# Each source runs on its own timer, once at startup and then every interval.
# A failed fetch is logged and retried at the next interval, never in a tight
# loop, so a failing Cost Explorer can't run up charges (N3).
class CostRefresher
  # Defaults from the PRD; override with environment variables (R6).
  DEFAULT_INTERVALS = { cloudwatch: 30.minutes, cost_explorer: 6.hours, history: 1.day }.freeze
  ENV_NAMES = {
    cloudwatch: "COST_REFRESH_CLOUDWATCH_SECONDS",
    cost_explorer: "COST_REFRESH_COST_EXPLORER_SECONDS",
    history: "COST_REFRESH_HISTORY_SECONDS"
  }.freeze
  # Floors, so a typo in an override can't turn into a request storm.
  # Cost Explorer is $0.01 per request: hourly at most is about $15/month.
  MINIMUM_INTERVALS = { cloudwatch: 5.minutes, cost_explorer: 1.hour, history: 1.hour }.freeze

  class << self
    # Only the real web server fetches, never tests, consoles, `rails runner`,
    # or the ZAP scan container (which sets COST_FETCH_ENABLED=false).
    # On by default only in production, so a local `bin/rails server` doesn't
    # spend money unless COST_FETCH_ENABLED=true is set on purpose.
    def enabled?(env: ENV, rails_env: Rails.env, server: defined?(Rails::Server))
      return false unless server
      return false if rails_env.test?

      setting = env["COST_FETCH_ENABLED"]
      rails_env.production? ? setting != "false" : setting == "true"
    end

    def interval(source, env: ENV)
      raw = env[ENV_NAMES.fetch(source)]
      seconds = raw.present? ? Integer(raw, exception: false) : nil
      seconds = DEFAULT_INTERVALS.fetch(source).to_i if seconds.nil?
      [seconds, MINIMUM_INTERVALS.fetch(source).to_i].max
    end

    def start
      @timers ||= sources.map do |source, fetcher|
        Concurrent::TimerTask.new(execution_interval: interval(source), run_now: true) do
          refresh(source, fetcher)
        end.tap(&:execute)
      end
      Rails.logger.info("cost_fetch scheduler=started intervals=#{sources.keys.map { |s| "#{s}:#{interval(s)}s" }.join(',')}")
    end

    # Runs one fetch and records the outcome. Never raises, so a failure can't
    # kill the timer or the web process. Logs only the source and outcome:
    # no amounts, and no error messages (they can contain account details).
    def refresh(source, fetcher)
      Rails.application.executor.wrap do
        result = fetcher.fetch
        CostStore.record_success(source, result)
        Rails.logger.info("cost_fetch source=#{source} result=ok")
      end
    rescue StandardError => e
      CostStore.record_failure(source, e.class.name)
      Rails.logger.error("cost_fetch source=#{source} result=error error=#{e.class.name}")
    end

    private

    def sources
      {
        cloudwatch: CostSources::CloudWatchCharges.new,
        cost_explorer: CostSources::CostExplorerTotals.new,
        history: CostSources::MonthlyHistory.new
      }
    end
  end
end

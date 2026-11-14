require "test_helper"

class CostRefresherTest < ActiveSupport::TestCase
  setup { CostStore.reset! }
  teardown { CostStore.reset! }

  FakeFetcher = Struct.new(:outcome) do
    def fetch
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  test "a successful fetch is stored" do
    CostRefresher.refresh(:cloudwatch, FakeFetcher.new(:result_one))
    assert_equal :result_one, CostStore.read(:cloudwatch).result
    assert_nil CostStore.read(:cloudwatch).error
  end

  test "a failed fetch keeps the last good result and records only the error class" do
    CostRefresher.refresh(:cloudwatch, FakeFetcher.new(:good))
    CostRefresher.refresh(:cloudwatch, FakeFetcher.new(RuntimeError.new("details that must not be stored")))

    entry = CostStore.read(:cloudwatch)
    assert_equal :good, entry.result
    assert_equal "RuntimeError", entry.error
  end

  test "a failed fetch never raises" do
    assert_nothing_raised { CostRefresher.refresh(:cost_explorer, FakeFetcher.new(StandardError.new)) }
  end

  test "fetching runs only in the server, and is on by default only in production" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    development = ActiveSupport::EnvironmentInquirer.new("development")
    test_env = ActiveSupport::EnvironmentInquirer.new("test")

    assert CostRefresher.enabled?(env: {}, rails_env: production, server: true)
    assert_not CostRefresher.enabled?(env: { "COST_FETCH_ENABLED" => "false" }, rails_env: production, server: true)
    assert_not CostRefresher.enabled?(env: {}, rails_env: production, server: nil) # rails runner, console
    assert_not CostRefresher.enabled?(env: {}, rails_env: development, server: true)
    assert CostRefresher.enabled?(env: { "COST_FETCH_ENABLED" => "true" }, rails_env: development, server: true)
    assert_not CostRefresher.enabled?(env: { "COST_FETCH_ENABLED" => "true" }, rails_env: test_env, server: true)
  end

  test "not running during this test suite" do
    assert_not CostRefresher.enabled?
  end

  test "intervals default to the PRD values and can't go below the floor" do
    assert_equal 1800, CostRefresher.interval(:cloudwatch, env: {})
    assert_equal 21_600, CostRefresher.interval(:cost_explorer, env: {})
    assert_equal 86_400, CostRefresher.interval(:history, env: {})
    assert_equal 3600, CostRefresher.interval(:history, env: { "COST_REFRESH_HISTORY_SECONDS" => "60" })
    assert_equal 7200, CostRefresher.interval(:cost_explorer, env: { "COST_REFRESH_COST_EXPLORER_SECONDS" => "7200" })
    assert_equal 3600, CostRefresher.interval(:cost_explorer, env: { "COST_REFRESH_COST_EXPLORER_SECONDS" => "5" })
    assert_equal 21_600, CostRefresher.interval(:cost_explorer, env: { "COST_REFRESH_COST_EXPLORER_SECONDS" => "oops" })
  end
end

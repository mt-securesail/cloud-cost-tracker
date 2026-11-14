require "test_helper"

# Uses the AWS SDK's stubbed client: no test calls real AWS.
class MonthlyHistoryTest < ActiveSupport::TestCase
  def group(name, amount)
    { keys: [name], metrics: { "UnblendedCost" => { amount: amount, unit: "USD" } } }
  end

  def fetch(results, now:)
    client = Aws::CostExplorer::Client.new(stub_responses: true)
    client.stub_responses(:get_cost_and_usage, results_by_time: results)
    [CostSources::MonthlyHistory.new(client: client, clock: -> { now }).fetch, client]
  end

  test "the 3 complete months before this one, by service" do
    result, client = fetch([
      { time_period: { start: "2026-08-01", end: "2026-09-01" }, groups: [group("Amazon Route 53", "0.50")] },
      { time_period: { start: "2026-09-01", end: "2026-10-01" }, groups: [group("Amazon Route 53", "0.50"), group("Amazon Bedrock", "2.345")] },
      { time_period: { start: "2026-10-01", end: "2026-11-01" }, groups: [] }
    ], now: Time.utc(2026, 11, 14))

    params = client.api_requests.first[:params]
    assert_equal({ start: "2026-08-01", end: "2026-11-01" }, params[:time_period])
    assert_equal "MONTHLY", params[:granularity]
    assert_equal 1, client.api_requests.size

    assert_equal Date.new(2026, 11, 1), result.period_start
    assert_equal [Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1)], result.months.keys
    assert_equal BigDecimal("2.345"), result.months[Date.new(2026, 9, 1)]["Amazon Bedrock"]
    assert_empty result.months[Date.new(2026, 10, 1)]
  end

  test "in January the months come from the previous year" do
    _, client = fetch([], now: Time.utc(2027, 1, 5))
    assert_equal({ start: "2026-10-01", end: "2027-01-01" }, client.api_requests.first[:params][:time_period])
  end

  test "all 3 months are present even if AWS returns none" do
    result, = fetch([], now: Time.utc(2026, 11, 14))
    assert_equal 3, result.months.size
  end
end

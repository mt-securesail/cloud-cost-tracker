require "test_helper"

# Uses the AWS SDK's stubbed client: no test calls real AWS.
class CostExplorerTotalsTest < ActiveSupport::TestCase
  MID_MONTH = Time.utc(2026, 11, 14, 15)

  def client_with(groups:, forecast: { total: { amount: "40.00", unit: "USD" },
                                       forecast_results_by_time: [{ mean_value: "40.00",
                                                                    prediction_interval_lower_bound: "35.00",
                                                                    prediction_interval_upper_bound: "45.00" }] })
    client = Aws::CostExplorer::Client.new(stub_responses: true)
    client.stub_responses(:get_cost_and_usage, results_by_time: [{
      groups: groups.map { |name, amount| { keys: [name], metrics: { "UnblendedCost" => { amount: amount, unit: "USD" } } } }
    }])
    client.stub_responses(:get_cost_forecast, forecast)
    client
  end

  def fetch(client, now: MID_MONTH)
    CostSources::CostExplorerTotals.new(client: client, clock: -> { now }).fetch
  end

  def requests(client, operation)
    client.api_requests.select { |r| r[:operation_name] == operation }
  end

  test "sums month to date by service and returns the forecast" do
    client = client_with(groups: { "Amazon Elastic Compute Cloud - Compute" => "12.345", "Elastic Load Balancing" => "7.10" })
    result = fetch(client)

    assert_equal BigDecimal("19.45"), result.month_to_date
    assert_equal BigDecimal("7.10"), result.by_service["Elastic Load Balancing"]
    assert_equal BigDecimal("40.00"), result.forecast.mean
    assert_equal BigDecimal("35.00"), result.forecast.low
    assert_nil result.forecast_note
  end

  test "queries this month to tomorrow, and today to the period end" do
    client = client_with(groups: {})
    fetch(client)

    usage = requests(client, :get_cost_and_usage).first[:params]
    assert_equal({ start: "2026-11-01", end: "2026-11-15" }, usage[:time_period])
    assert_equal [{ type: "DIMENSION", key: "SERVICE" }], usage[:group_by]

    forecast = requests(client, :get_cost_forecast).first[:params]
    assert_equal({ start: "2026-11-14", end: "2026-12-01" }, forecast[:time_period])
  end

  test "makes exactly 2 Cost Explorer requests per fetch" do
    client = client_with(groups: { "Amazon Route 53" => "0.50" })
    fetch(client)
    assert_equal 2, client.api_requests.size
  end

  test "not enough data for a forecast falls back without failing the fetch" do
    client = client_with(groups: { "Amazon Route 53" => "0.50" }, forecast: "DataUnavailableException")
    result = fetch(client)

    assert_equal BigDecimal("0.50"), result.month_to_date
    assert_nil result.forecast
    assert_equal :insufficient_data, result.forecast_note
  end

  test "any other forecast error also falls back" do
    client = client_with(groups: { "Amazon Route 53" => "0.50" }, forecast: "LimitExceededException")
    result = fetch(client)
    assert_nil result.forecast
    assert_equal :error, result.forecast_note
  end

  test "the last day of the month skips the forecast request" do
    client = client_with(groups: { "Amazon Route 53" => "0.50" })
    result = fetch(client, now: Time.utc(2026, 11, 30, 12))

    assert_empty requests(client, :get_cost_forecast)
    assert_equal :last_day, result.forecast_note
  end

  test "a month-to-date failure raises, so the refresher keeps the last good data" do
    client = client_with(groups: {})
    client.stub_responses(:get_cost_and_usage, "AccessDeniedException")
    assert_raises(Aws::CostExplorer::Errors::AccessDeniedException) { fetch(client) }
  end
end

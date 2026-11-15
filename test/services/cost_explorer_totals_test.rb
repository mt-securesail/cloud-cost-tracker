require "test_helper"

# Uses the AWS SDK's stubbed client: no test calls real AWS.
class CostExplorerTotalsTest < ActiveSupport::TestCase
  MID_MONTH = Time.utc(2026, 11, 14, 15)

  DEFAULT_FORECAST = {
    total: { amount: "20.00", unit: "USD" },
    forecast_results_by_time: [
      { time_period: { start: "2026-11-14", end: "2026-11-15" }, mean_value: "10.00",
        prediction_interval_lower_bound: "8.00", prediction_interval_upper_bound: "12.50" },
      { time_period: { start: "2026-11-15", end: "2026-11-16" }, mean_value: "10.00",
        prediction_interval_lower_bound: "9.00", prediction_interval_upper_bound: "11.00" }
    ]
  }.freeze

  # days: { "2026-11-13" => { "Service" => "1.00" } }
  def client_with(days:, forecast: DEFAULT_FORECAST)
    client = Aws::CostExplorer::Client.new(stub_responses: true)
    client.stub_responses(:get_cost_and_usage, results_by_time: days.map do |day, groups|
      { time_period: { start: day, end: (Date.iso8601(day) + 1).iso8601 },
        groups: groups.map { |name, amount| { keys: [name], metrics: { "UnblendedCost" => { amount: amount, unit: "USD" } } } } }
    end)
    client.stub_responses(:get_cost_forecast, forecast)
    client
  end

  def fetch(client, now: MID_MONTH)
    CostSources::CostExplorerTotals.new(client: client, clock: -> { now }).fetch
  end

  def requests(client, operation)
    client.api_requests.select { |r| r[:operation_name] == operation }
  end

  test "sums month to date by service across days, and separately through yesterday" do
    client = client_with(days: {
      "2026-11-12" => { "Amazon Registrar" => "16.00", "Elastic Load Balancing" => "0.54" },
      "2026-11-13" => { "Elastic Load Balancing" => "0.54" },
      "2026-11-14" => { "Elastic Load Balancing" => "0.23" } # today, partial
    })
    result = fetch(client)

    assert_equal BigDecimal("17.31"), result.month_to_date
    assert_equal BigDecimal("17.08"), result.month_to_date_before_today
    assert_equal BigDecimal("1.31"), result.by_service["Elastic Load Balancing"]
    assert_nil result.forecast_note
  end

  test "forecast is AWS's daily forecast from today, with the daily bounds summed" do
    result = fetch(client_with(days: {}))
    assert_equal BigDecimal("20.00"), result.forecast.mean
    assert_equal BigDecimal("17.00"), result.forecast.low
    assert_equal BigDecimal("23.50"), result.forecast.high
  end

  test "no range when AWS leaves out the bounds" do
    forecast = { total: { amount: "20.00", unit: "USD" }, forecast_results_by_time: [{ mean_value: "20.00" }] }
    result = fetch(client_with(days: {}, forecast: forecast))
    assert_equal BigDecimal("20.00"), result.forecast.mean
    assert_nil result.forecast.low
  end

  test "asks for daily usage to tomorrow and a daily forecast from today to the period end" do
    client = client_with(days: {})
    fetch(client)

    usage = requests(client, :get_cost_and_usage).first[:params]
    assert_equal({ start: "2026-11-01", end: "2026-11-15" }, usage[:time_period])
    assert_equal "DAILY", usage[:granularity]
    assert_equal [{ type: "DIMENSION", key: "SERVICE" }], usage[:group_by]

    forecast = requests(client, :get_cost_forecast).first[:params]
    assert_equal({ start: "2026-11-14", end: "2026-12-01" }, forecast[:time_period])
    assert_equal "DAILY", forecast[:granularity]
  end

  test "makes exactly 2 Cost Explorer requests per fetch" do
    client = client_with(days: { "2026-11-13" => { "Amazon Route 53" => "0.50" } })
    fetch(client)
    assert_equal 2, client.api_requests.size
  end

  test "not enough data for a forecast falls back without failing the fetch" do
    client = client_with(days: { "2026-11-13" => { "Amazon Route 53" => "0.50" } }, forecast: "DataUnavailableException")
    result = fetch(client)

    assert_equal BigDecimal("0.50"), result.month_to_date
    assert_nil result.forecast
    assert_equal :insufficient_data, result.forecast_note
  end

  test "any other forecast error also falls back" do
    client = client_with(days: {}, forecast: "LimitExceededException")
    result = fetch(client)
    assert_nil result.forecast
    assert_equal :error, result.forecast_note
  end

  test "the last day of the month skips the forecast request" do
    client = client_with(days: {})
    result = fetch(client, now: Time.utc(2026, 11, 30, 12))

    assert_empty requests(client, :get_cost_forecast)
    assert_equal :last_day, result.forecast_note
  end

  test "a month-to-date failure raises, so the refresher keeps the last good data" do
    client = client_with(days: {})
    client.stub_responses(:get_cost_and_usage, "AccessDeniedException")
    assert_raises(Aws::CostExplorer::Errors::AccessDeniedException) { fetch(client) }
  end
end

require "test_helper"

# Uses the AWS SDK's stubbed client: no test calls real AWS.
class CloudWatchChargesTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 14, 15, 30)

  def fetch_with(timestamps:, values:, now: NOW)
    client = Aws::CloudWatch::Client.new(stub_responses: true)
    client.stub_responses(:get_metric_data, metric_data_results: [
      { id: "charges", timestamps: timestamps, values: values, status_code: "Complete" }
    ])
    result = CostSources::CloudWatchCharges.new(client: client, clock: -> { now }).fetch
    [result, client]
  end

  test "returns the most recent datapoint and its time" do
    result, = fetch_with(timestamps: [Time.utc(2026, 11, 14, 6), Time.utc(2026, 11, 14, 12), Time.utc(2026, 11, 13, 18)],
                         values: [30.1, 31.456, 29.0])
    assert_equal BigDecimal("31.46"), result.amount
    assert_equal Time.utc(2026, 11, 14, 12), result.as_of
  end

  test "asks for the account-total USD billing metric" do
    _, client = fetch_with(timestamps: [Time.utc(2026, 11, 14, 12)], values: [1.0])
    params = client.api_requests.last[:params]
    stat = params[:metric_data_queries].first[:metric_stat]
    assert_equal "AWS/Billing", stat[:metric][:namespace]
    assert_equal "EstimatedCharges", stat[:metric][:metric_name]
    assert_equal [{ name: "Currency", value: "USD" }], stat[:metric][:dimensions]
    assert_equal "Maximum", stat[:stat]
    # 1-minute buckets: "as of" is the minute AWS published the number.
    assert_equal 60, stat[:period]
  end

  test "a datapoint from last month is not this month's charges" do
    result, = fetch_with(timestamps: [Time.utc(2026, 10, 31, 22)], values: [95.0], now: Time.utc(2026, 11, 1, 3))
    assert_nil result.amount
    assert_nil result.as_of
  end

  test "no datapoints means no data yet" do
    result, = fetch_with(timestamps: [], values: [])
    assert_nil result.amount
  end
end

require "test_helper"

class CostSummaryTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 14, 15) # day 14 of 30

  setup { CostStore.reset! }
  teardown { CostStore.reset! }

  def explorer(mtd:, before_today: mtd, forecast: nil, note: nil)
    CostSources::CostExplorerTotals::Result.new(month_to_date: BigDecimal(mtd), by_service: {}, forecast: forecast, forecast_note: note,
                                                month_to_date_before_today: BigDecimal(before_today))
  end

  def history(months: {}, billing_forecast: nil, period_start: Date.new(2026, 11, 1))
    CostSources::MonthlyHistory::Result.new(billing_forecast: nil, period_start: period_start, months: months, billing_forecast: billing_forecast)
  end

  def forecast(mean, low = nil, high = nil)
    CostSources::CostExplorerTotals::Forecast.new(mean: BigDecimal(mean), low: low && BigDecimal(low), high: high && BigDecimal(high))
  end

  test "estimated total is costs through yesterday plus AWS's forecast from today" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "20.50", before_today: "20.00", forecast: forecast("10.00", "8.00", "13.00")), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal :forecast, estimate.method
    assert_equal BigDecimal("30.00"), estimate.amount
    assert_equal BigDecimal("28.00"), estimate.low
    assert_equal BigDecimal("33.00"), estimate.high
  end

  # Regression test for findings log #5, using the real figures from
  # 2026-11-15: AWS's monthly forecast (and Billing and Cost Management) said
  # $199.49, extrapolating month-over-month growth, while spending was a
  # steady ~$1.24 a day. Daily forecast for Nov 15-30: $19.77.
  test "the estimate follows the daily pattern, not month-over-month growth" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "35.66", before_today: "35.10", forecast: forecast("19.77")), at: NOW)
    CostStore.record_success(:history, history(billing_forecast: BigDecimal("199.49")), at: NOW)
    summary = CostSummary.new(now: NOW)

    assert_equal BigDecimal("54.87"), summary.estimated_total.amount
    assert_equal BigDecimal("199.49"), summary.billing_forecast
  end

  test "the estimate never ends below what's already been spent" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "40.00", before_today: "30.00", forecast: forecast("8.00", "6.00", "11.00")), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal BigDecimal("40.00"), estimate.amount
    assert_equal BigDecimal("40.00"), estimate.low
    assert_equal BigDecimal("41.00"), estimate.high
  end

  test "Billing's forecast from last month's history is not shown after rollover" do
    CostStore.record_success(:history, history(billing_forecast: BigDecimal("99"), period_start: Date.new(2026, 10, 1)), at: Time.utc(2026, 10, 31, 20))
    assert_nil CostSummary.new(now: Time.utc(2026, 11, 1, 1)).billing_forecast
  end

  test "without a forecast, a labeled simple projection is used" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "14.00", note: :insufficient_data), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal :projection, estimate.method
    assert_equal BigDecimal("30.00"), estimate.amount # 14 / 14 days * 30 days
    assert_equal :insufficient_data, estimate.note
  end

  test "on the last day the estimate is the month to date" do
    last_day = Time.utc(2026, 11, 30, 12)
    CostStore.record_success(:cost_explorer, explorer(mtd: "41.00", note: :last_day), at: last_day)
    estimate = CostSummary.new(now: last_day).estimated_total

    assert_equal :final, estimate.method
    assert_equal BigDecimal("41.00"), estimate.amount
  end

  test "Cost Explorer data fetched last month is not shown after rollover" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "99.00"), at: Time.utc(2026, 10, 31, 20))
    summary = CostSummary.new(now: Time.utc(2026, 11, 1, 1))

    assert_nil summary.estimated_total
    assert_not summary.cost_explorer_loaded?
  end

  test "a CloudWatch datapoint from last month is not shown after rollover" do
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("99"), as_of: Time.utc(2026, 10, 31, 22)),
                             at: Time.utc(2026, 10, 31, 23))
    summary = CostSummary.new(now: Time.utc(2026, 11, 1, 1))

    assert_nil summary.current_charges
    assert summary.cloudwatch_loaded?
  end

  test "headline time is the latest as-of across sources" do
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("31"), as_of: Time.utc(2026, 11, 14, 12)), at: NOW)
    CostStore.record_success(:cost_explorer, explorer(mtd: "20.00"), at: Time.utc(2026, 11, 14, 9))
    assert_equal Time.utc(2026, 11, 14, 12), CostSummary.new(now: NOW).last_updated_at
  end

  test "history fetched for last month's period is ignored after rollover" do
    stale = CostSources::MonthlyHistory::Result.new(billing_forecast: nil, period_start: Date.new(2026, 10, 1), months: { Date.new(2026, 7, 1) => {} })
    CostStore.record_success(:history, stale, at: Time.utc(2026, 10, 31, 20))
    summary = CostSummary.new(now: Time.utc(2026, 11, 1, 1))

    assert_not summary.history_loaded?
    assert_nil summary.history_as_of
  end

  test "breakdown combines this month by service with the history" do
    explorer_result = CostSources::CostExplorerTotals::Result.new(month_to_date: BigDecimal("1"), by_service: { "Amazon Route 53" => BigDecimal("1") },
                                                                 forecast: nil, forecast_note: nil,
                                                                 month_to_date_before_today: BigDecimal("0"))
    CostStore.record_success(:cost_explorer, explorer_result, at: NOW)
    history = CostSources::MonthlyHistory::Result.new(billing_forecast: nil, period_start: Date.new(2026, 11, 1),
                                                      months: { Date.new(2026, 10, 1) => { "Amazon Route 53" => BigDecimal("0.5") } })
    CostStore.record_success(:history, history, at: NOW)

    b = CostSummary.new(now: NOW).breakdown
    assert_equal [Date.new(2026, 10, 1)], b.months
    assert_equal BigDecimal("0.5"), b.rows.first.months[Date.new(2026, 10, 1)]
  end

  test "nothing loaded yet" do
    summary = CostSummary.new(now: NOW)
    assert_nil summary.last_updated_at
    assert_nil summary.estimated_total
    assert_nil summary.breakdown
    assert_not summary.cloudwatch_loaded?
  end

  INTERVALS = { cloudwatch: 30.minutes.to_i, cost_explorer: 6.hours.to_i, history: 1.day.to_i }.freeze

  test "a source is stale after two refresh intervals without a successful fetch" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "10.00"), at: NOW - 12.hours)
    assert_not CostSummary.new(now: NOW, intervals: INTERVALS).stale?(:cost_explorer)
    assert CostSummary.new(now: NOW + 1.minute, intervals: INTERVALS).stale?(:cost_explorer)
    assert_equal 12.hours.to_i, CostSummary.new(now: NOW, intervals: INTERVALS).stale_after(:cost_explorer)
  end

  test "a failed fetch keeps the last good data, which goes stale in time" do
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("5"), as_of: NOW - 3.hours), at: NOW - 2.hours)
    CostStore.record_failure(:cloudwatch, "Seahorse::Client::NetworkingError", at: NOW - 1.minute)
    summary = CostSummary.new(now: NOW, intervals: INTERVALS)

    assert_equal BigDecimal("5"), summary.current_charges
    assert summary.stale?(:cloudwatch)
    assert_not summary.stale?(:history), "a source that has never loaded is not stale, just loading"
  end

  test "as_of and loaded? per source" do
    CostStore.record_success(:history, CostSources::MonthlyHistory::Result.new(billing_forecast: nil, period_start: Date.new(2026, 11, 1), months: {}), at: NOW - 1.hour)
    summary = CostSummary.new(now: NOW, intervals: INTERVALS)
    assert summary.loaded?(:history)
    assert_equal NOW - 1.hour, summary.as_of(:history)
    assert_not summary.loaded?(:cloudwatch)
    assert_nil summary.as_of(:cloudwatch)
  end
end

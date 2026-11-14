require "test_helper"

class CostSummaryTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 14, 15) # day 14 of 30

  setup { CostStore.reset! }
  teardown { CostStore.reset! }

  def explorer(mtd:, forecast: nil, note: nil)
    CostSources::CostExplorerTotals::Result.new(month_to_date: BigDecimal(mtd), by_service: {}, forecast: forecast, forecast_note: note)
  end

  def forecast(mean, low = nil, high = nil)
    CostSources::CostExplorerTotals::Forecast.new(mean: BigDecimal(mean), low: low && BigDecimal(low), high: high && BigDecimal(high))
  end

  test "estimated total is AWS's whole-month forecast, not month to date plus forecast" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "20.00", forecast: forecast("30.00", "25.00", "36.00")), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal :forecast, estimate.method
    assert_equal BigDecimal("30.00"), estimate.amount
    assert_equal BigDecimal("25.00"), estimate.low
    assert_equal BigDecimal("36.00"), estimate.high
  end

  # Regression test for findings log #4, using the real figures from
  # 2026-11-14: Billing and Cost Management showed a $54 forecast, and the page
  # showed $88.14 because it added the month to date ($33.91) a second time.
  test "the month to date is not counted twice" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "33.91", forecast: forecast("54.23", "53.41", "55.06")), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal BigDecimal("54.23"), estimate.amount
    assert_equal BigDecimal("53.41"), estimate.low
    assert_equal BigDecimal("55.06"), estimate.high
  end

  test "the estimate never ends below what's already been spent" do
    CostStore.record_success(:cost_explorer, explorer(mtd: "40.00", forecast: forecast("38.00", "36.00", "41.00")), at: NOW)
    estimate = CostSummary.new(now: NOW).estimated_total

    assert_equal BigDecimal("40.00"), estimate.amount
    assert_equal BigDecimal("40.00"), estimate.low
    assert_equal BigDecimal("41.00"), estimate.high
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

  test "nothing loaded yet" do
    summary = CostSummary.new(now: NOW)
    assert_nil summary.last_updated_at
    assert_nil summary.estimated_total
    assert_not summary.cloudwatch_loaded?
  end
end

require "test_helper"

class BillingPeriodTest < ActiveSupport::TestCase
  test "mid-month period" do
    p = BillingPeriod.new(Date.new(2026, 11, 14))
    assert_equal Date.new(2026, 11, 1), p.start_date
    assert_equal Date.new(2026, 12, 1), p.end_date
    assert_equal Date.new(2026, 11, 30), p.last_date
    assert_equal 30, p.days_in_period
    assert_equal 14, p.day_number
    assert_not p.last_day?
    assert_equal Time.utc(2026, 11, 1), p.starts_at
  end

  test "first day of the month" do
    p = BillingPeriod.new(Date.new(2026, 11, 1))
    assert_equal 1, p.day_number
    assert_equal Date.new(2026, 11, 2), p.tomorrow
  end

  test "last day of the month" do
    p = BillingPeriod.new(Date.new(2026, 11, 30))
    assert p.last_day?
    assert_equal 30, p.day_number
    assert_equal Date.new(2026, 12, 1), p.tomorrow
  end

  test "December rolls over into the next year" do
    p = BillingPeriod.new(Date.new(2026, 12, 31))
    assert_equal Date.new(2027, 1, 1), p.end_date
    assert_equal 31, p.days_in_period
    assert p.last_day?
  end

  test "February in a leap year" do
    p = BillingPeriod.new(Date.new(2028, 2, 10))
    assert_equal 29, p.days_in_period
  end

  test "current uses the UTC date, not the local one" do
    # 11:30 PM on Nov 30 in New York is already Dec 1 in UTC.
    new_york = Time.new(2026, 11, 30, 23, 30, 0, "-05:00")
    assert_equal Date.new(2026, 12, 1), BillingPeriod.current(new_york).start_date
  end
end

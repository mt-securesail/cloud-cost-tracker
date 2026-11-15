require "test_helper"

class CostFormatHelperTest < ActionView::TestCase
  test "usd formatting" do
    assert_equal "$1,234.50", usd(BigDecimal("1234.5"))
    assert_equal "$0.01", usd(BigDecimal("0.005"))
    assert_equal "< $0.01", usd(BigDecimal("0.004"))
    assert_equal "$0.00", usd(BigDecimal("0"))
    assert_equal "—", usd(nil)
  end

  # Must match age() in app/javascript/dashboard.js.
  test "age" do
    now = Time.utc(2026, 11, 14, 12)
    assert_equal "just now", age(now - 59, now)
    assert_equal "just now", age(now + 30, now) # clock skew never shows a negative age
    assert_equal "1 min ago", age(now - 60, now)
    assert_equal "59 min ago", age(now - 3599, now)
    assert_equal "1 h ago", age(now - 3600, now)
    assert_equal "47 h ago", age(now - 48.hours + 1, now)
    assert_equal "2 days ago", age(now - 48.hours, now)
  end

  test "duration words" do
    assert_equal "1 hour", duration_words(3600)
    assert_equal "12 hours", duration_words(12 * 3600)
    assert_equal "90 minutes", duration_words(5400)
  end

  test "local time tag carries the exact time for the browser" do
    html = local_time_tag(Time.utc(2026, 11, 14, 18, 6))
    assert_dom_equal %(<time datetime="2026-11-14T18:06:00Z" data-local="">Sat, Nov 14, 2026 6:06 PM UTC</time>), html
  end
end


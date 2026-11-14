require "test_helper"

class CostFormatHelperTest < ActionView::TestCase
  test "usd formatting" do
    assert_equal "$1,234.50", usd(BigDecimal("1234.5"))
    assert_equal "$0.01", usd(BigDecimal("0.005"))
    assert_equal "< $0.01", usd(BigDecimal("0.004"))
    assert_equal "$0.00", usd(BigDecimal("0"))
    assert_equal "—", usd(nil)
  end
end

require "test_helper"

class ServiceBreakdownTest < ActiveSupport::TestCase
  AUG, SEP, OCT = Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1)

  def d(amount) = BigDecimal(amount.to_s)

  def twelve_services
    (1..12).to_h { |i| ["Service #{i.to_s.rjust(2, '0')}", d(100 - i)] }
  end

  test "top 10 by month-to-date cost, largest first, the rest in Other" do
    b = ServiceBreakdown.new(current: twelve_services)

    assert_equal 10, b.rows.size
    assert_equal "Service 01", b.rows.first.name
    assert_equal "Service 10", b.rows.last.name
    assert_equal d(89 + 88), b.other.current # services 11 and 12
    assert_equal twelve_services.values.sum, b.totals.current
  end

  test "every Bedrock model gets its own row, even outside the top 10" do
    current = twelve_services.merge(
      "Claude Sonnet 4.5 (Amazon Bedrock Edition)" => d("1.25"),
      "Claude Haiku 4.5 (Amazon Bedrock Edition)" => d("0.40")
    )
    b = ServiceBreakdown.new(current: current)

    names = b.rows.map(&:name)
    assert_equal 12, names.size
    assert_equal ["Claude Sonnet 4.5 (Amazon Bedrock Edition)", "Claude Haiku 4.5 (Amazon Bedrock Edition)"], names.last(2)
    assert b.rows.last.bedrock
    assert_not b.rows.first.bedrock
    # Bedrock models are never folded into Other.
    assert_equal d(89 + 88), b.other.current
  end

  test "a Bedrock model used only in an earlier month still gets a row" do
    history = { AUG => {}, SEP => { "Amazon Bedrock" => d("3.00") }, OCT => {} }
    b = ServiceBreakdown.new(current: { "Amazon Route 53" => d("0.50") }, history: history)

    row = b.rows.find { |r| r.name == "Amazon Bedrock" }
    assert row.bedrock
    assert_nil row.current
    assert_equal d("3.00"), row.months[SEP]
    assert_nil row.months[AUG]
  end

  test "comparison columns use the same rows, with Other and totals per month" do
    history = {
      AUG => { "Amazon Route 53" => d("0.50"), "Old Service" => d("9.00") },
      SEP => { "Amazon Route 53" => d("0.50") },
      OCT => {}
    }
    b = ServiceBreakdown.new(current: { "Amazon Route 53" => d("0.51") }, history: history)

    assert_equal [AUG, SEP, OCT], b.months
    assert_equal ["Amazon Route 53"], b.rows.map(&:name)
    # A service that only appears in earlier months goes into Other (PRD 6.4).
    assert_equal d("9.00"), b.other.months[AUG]
    assert_equal d("9.50"), b.totals.months[AUG]
    assert_equal d("0"), b.totals.months[OCT]
    assert_nil b.rows.first.months[OCT]
  end

  test "a Bedrock model that cost a fraction of a cent still gets a row" do
    b = ServiceBreakdown.new(current: { "Amazon Route 53" => d("0.50"), "Claude Haiku 4.5 (Amazon Bedrock Edition)" => d("0.004") })
    row = b.rows.find(&:bedrock)
    assert_equal "Claude Haiku 4.5 (Amazon Bedrock Edition)", row.name
    assert_equal d("0.004"), row.current
  end

  test "amounts that round to zero don't get rows" do
    b = ServiceBreakdown.new(current: { "Amazon Route 53" => d("0.50"), "AWS Glue" => d("0.000001") })
    assert_equal ["Amazon Route 53"], b.rows.map(&:name)
  end

  test "no Other row when everything is shown" do
    assert_nil ServiceBreakdown.new(current: { "Amazon Route 53" => d("0.50") }).other
  end

  test "share of this month's total" do
    b = ServiceBreakdown.new(current: { "A" => d("75"), "B" => d("25") })
    assert_equal 75, b.share(d("75"))
    assert_nil b.share(nil)
  end

  test "Bedrock detection" do
    assert ServiceBreakdown.bedrock?("Amazon Bedrock")
    assert ServiceBreakdown.bedrock?("Claude Sonnet 4.5 (Amazon Bedrock Edition)")
    assert_not ServiceBreakdown.bedrock?("Amazon Route 53")
  end
end

require "test_helper"

# Records whether any AWS SDK client is created while armed.
module AwsClientCreationTrap
  class << self
    attr_accessor :armed, :tripped
  end

  def new(...)
    AwsClientCreationTrap.tripped = true if AwsClientCreationTrap.armed
    super
  end
end
Seahorse::Client::Base.singleton_class.prepend(AwsClientCreationTrap)

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup { CostStore.reset! }
  teardown { CostStore.reset! }

  test "should get index" do
    get root_url
    assert_response :success
  end

  test "before the first fetch the page says so instead of failing" do
    get root_url
    assert_response :success
    assert_select "#current-charges", /Loading/
    assert_select "#estimated-total", /Loading/
    assert_match "Costs not loaded yet", response.body
  end

  test "shows the stored figures" do
    now = Time.now.utc
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("31.46"), as_of: now - 2.hours))
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("1234.5"), by_service: {}, forecast: nil, forecast_note: :insufficient_data
    ))

    get root_url
    assert_select "#current-charges", /\$31\.46/
    assert_select "#estimated-total", /\$[\d,]+\.\d{2}/
    assert_match "Costs last updated at", response.body
    assert_match "Projection (simple)", response.body
    assert_match "$1,234.50", response.body
  end

  test "shows the service table with Bedrock models as their own rows" do
    by_service = { "Amazon Elastic Load Balancing" => BigDecimal("9.10"),
                   "Claude Sonnet 4.5 (Amazon Bedrock Edition)" => BigDecimal("1.25") }
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("10.35"), by_service: by_service, forecast: nil, forecast_note: nil
    ))
    get root_url
    assert_select "#by-service tbody tr", 2
    assert_select "#by-service tr.bedrock th", /Claude Sonnet 4\.5 \(Amazon Bedrock Edition\)/
    assert_select "#by-service tfoot td", /\$10\.35/
  end

  test "service names from AWS are shown as text, never as HTML" do
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("1"), by_service: { "<script>alert(1)</script>" => BigDecimal("1") }, forecast: nil, forecast_note: nil
    ))
    get root_url
    assert_no_match "<script>alert(1)</script>", response.body
    assert_match "&lt;script&gt;alert(1)&lt;/script&gt;", response.body
  end

  test "a failed refresh shows a warning with the error class only" do
    CostStore.record_failure(:cost_explorer, "Aws::CostExplorer::Errors::AccessDeniedException")
    get root_url
    assert_response :success
    assert_match "Last refresh failed (AccessDeniedException)", response.body
  end

  test "page views never create an AWS client" do
    AwsClientCreationTrap.tripped = false
    AwsClientCreationTrap.armed = true
    get root_url
    assert_response :success
    assert_not AwsClientCreationTrap.tripped, "a page view created an AWS client"
  ensure
    AwsClientCreationTrap.armed = false
  end

  # Regression test for finding #7 (code injection via eval of a request param).
  # If anything evaluates the `expr` parameter as Ruby, the marker gets set and this fails.
  test "request params are never evaluated as code" do
    $eval_marker = nil
    get root_url, params: { expr: "$eval_marker = :executed" }
    assert_response :success
    assert_nil $eval_marker, "a request parameter was evaluated as Ruby code"
  end
end

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
      month_to_date: BigDecimal("1234.5"), by_service: {}, forecast: nil, month_to_date_before_today: BigDecimal("0"), forecast_note: :insufficient_data
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
      month_to_date: BigDecimal("10.35"), by_service: by_service, forecast: nil, month_to_date_before_today: BigDecimal("0"), forecast_note: nil
    ))
    get root_url
    assert_select "#by-service tbody tr", 2
    assert_select "#by-service tr.bedrock th", /Claude Sonnet 4\.5 \(Amazon Bedrock Edition\)/
    assert_select "#by-service tfoot td", /\$10\.35/
  end

  test "service names from AWS are shown as text, never as HTML" do
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("1"), by_service: { "<script>alert(1)</script>" => BigDecimal("1") }, forecast: nil, month_to_date_before_today: BigDecimal("0"), forecast_note: nil
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

  test "page views and summary polls never create an AWS client" do
    AwsClientCreationTrap.tripped = false
    AwsClientCreationTrap.armed = true
    get root_url
    assert_response :success
    get summary_path
    assert_response :success
    assert_not AwsClientCreationTrap.tripped, "a page view or poll created an AWS client"
  ensure
    AwsClientCreationTrap.armed = false
  end

  test "summary.json has the same figures as the page" do
    by_service = { "Amazon Route 53" => BigDecimal("1.00"), "Claude Haiku 4.5 (Amazon Bedrock Edition)" => BigDecimal("0.004") }
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("33.48"), as_of: Time.utc(2026, 11, 14, 18, 6)))
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("1.00"), by_service: by_service, forecast: nil, month_to_date_before_today: BigDecimal("0"), forecast_note: :insufficient_data
    ))

    get summary_path
    assert_response :success
    assert_equal "application/json", response.media_type
    json = response.parsed_body

    assert_equal "dev", json["version"]
    assert_equal "$33.48", json.dig("current_charges", "amount")
    assert_equal "2026-11-14T18:06:00.000Z", json.dig("sources", 0, "as_of")
    assert_equal "not loaded yet", json.dig("sources", 2, "placeholder")
    assert_equal ["Amazon Route 53", "Claude Haiku 4.5 (Amazon Bedrock Edition)"], json.dig("breakdown", "rows").map { |r| r["name"] }
    assert_equal "< $0.01", json.dig("breakdown", "rows", 1, "current")
    assert json.dig("breakdown", "rows", 1, "bedrock")
    assert_equal "Loading…", json.dig("breakdown", "history_message")

    get root_url
    assert_select "#current-charges", "$33.48"
    assert_select "#by-service tbody tr", 2
  end

  test "the estimate card also shows AWS Billing's forecast for comparison" do
    # Mid-month: on the last day the page shows the final month to date instead.
    travel_to Time.utc(2026, 11, 15, 12) do
      CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
        month_to_date: BigDecimal("35.66"), month_to_date_before_today: BigDecimal("35.10"), by_service: {},
        forecast: CostSources::CostExplorerTotals::Forecast.new(mean: BigDecimal("19.77"), low: nil, high: nil), forecast_note: nil
      ))
      CostStore.record_success(:history, CostSources::MonthlyHistory::Result.new(
        period_start: BillingPeriod.current(Time.now.utc).start_date, months: {}, billing_forecast: BigDecimal("199.49")
      ))
      get root_url
      assert_select "#estimated-total", "$54.87"
      assert_match "Month to date + AWS&#39;s daily forecast for the rest of the month", response.body
      assert_match "AWS Billing&#39;s forecast (based on month-to-month growth): $199.49", response.body
    end
  end

  test "summary.json escapes HTML in names from AWS" do
    CostStore.record_success(:cost_explorer, CostSources::CostExplorerTotals::Result.new(
      month_to_date: BigDecimal("1"), by_service: { "<script>alert(1)</script>" => BigDecimal("1") }, forecast: nil, month_to_date_before_today: BigDecimal("0"), forecast_note: nil
    ))
    get summary_path
    assert_no_match "<script>", response.body
    assert_equal "<script>alert(1)</script>", response.parsed_body.dig("breakdown", "rows", 0, "name")
  end

  test "stale data stays on the page with a warning" do
    CostStore.record_success(:cloudwatch, CostSources::CloudWatchCharges::Result.new(amount: BigDecimal("12.34"), as_of: 5.hours.ago.utc), at: 3.hours.ago.utc)
    get root_url
    assert_select "#current-charges", "$12.34"
    assert_select "#sources .stale", "Stale: no successful refresh in over 1 hour."
  end

  test "the page loads the dashboard script and falls back to a reload without JavaScript" do
    get root_url
    assert_select "script[src='/dashboard.js'][defer]"
    assert_select "noscript meta[http-equiv=refresh][content='300']"
    assert_select "#dashboard[data-version=dev][data-poll-seconds='300']"
  end

  # Rails' cross-origin JavaScript check would block <script src="/dashboard.js">
  # in production; it's off in tests unless forgery protection is turned on.
  test "dashboard.js is served as JavaScript with forgery protection on, as in production" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get dashboard_script_path
    assert_response :success
    assert_equal "text/javascript", response.media_type
    assert_includes response.body, "textContent"
    assert_not_includes response.body, "innerHTML ="
  ensure
    ActionController::Base.allow_forgery_protection = original
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

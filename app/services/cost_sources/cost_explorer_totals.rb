module CostSources
  # Month-to-date cost (by service) and AWS's daily forecast for the rest of
  # the month, from Cost Explorer (PRD F4, F10, section 6.3).
  #
  # Every Cost Explorer request costs $0.01, so this makes at most 2 requests per
  # fetch (more only if AWS paginates the service list), and the refresher runs
  # it every few hours, never per page view.
  class CostExplorerTotals
    # Forecast for today through the last day of the month (NOT including the
    # month to date). low/high: sums of AWS's daily 80% bounds, so the range
    # is somewhat wider than a true 80% range for the total.
    Forecast = Data.define(:mean, :low, :high)
    # forecast is nil when unavailable; forecast_note then says why.
    # by_service: { "Amazon EC2" => BigDecimal, ... }, unrounded, so a Bedrock
    # model that cost a fraction of a cent still shows up in the breakdown.
    # month_to_date_before_today: costs through yesterday, which the forecast
    # (starting today) is added to. Today's partial costs are in month_to_date.
    Result = Data.define(:month_to_date, :by_service, :forecast, :forecast_note, :month_to_date_before_today)

    def initialize(client: nil, clock: -> { Time.now.utc })
      @client = client
      @clock = clock
    end

    def fetch
      period = BillingPeriod.current(@clock.call)
      by_service, before_today = month_to_date_by_service(period)
      forecast, note = rest_of_month_forecast(period)

      Result.new(
        month_to_date: by_service.values.sum(BigDecimal("0")).round(2),
        by_service: by_service,
        forecast: forecast,
        forecast_note: note,
        month_to_date_before_today: before_today.round(2)
      )
    end

    private

    # Daily results (still 1 request), so the total through yesterday comes
    # from the same call. Returns [{ service => total }, total before today].
    def month_to_date_by_service(period)
      totals = Hash.new(BigDecimal("0"))
      before_today = BigDecimal("0")
      response = client.get_cost_and_usage(
        time_period: { start: period.start_date.iso8601, end: period.tomorrow.iso8601 },
        granularity: "DAILY",
        metrics: ["UnblendedCost"],
        group_by: [{ type: "DIMENSION", key: "SERVICE" }]
      )
      response.each_page do |page|
        page.results_by_time.each do |result|
          earlier_day = Date.iso8601(result.time_period.start) < period.today
          result.groups.each do |group|
            amount = BigDecimal(group.metrics.fetch("UnblendedCost").amount)
            totals[group.keys.first] += amount
            before_today += amount if earlier_day
          end
        end
      end
      [totals, before_today]
    end

    # DAILY granularity: AWS forecasts each remaining day from the recent
    # day-by-day pattern, and the total covers only today to the period end.
    # (MONTHLY granularity, which Billing and Cost Management shows, instead
    # returns the whole month, month to date included, and extrapolates
    # month-over-month growth: $199 vs about $55 here on 2026-11-15, findings
    # log #5. MonthlyHistory fetches that figure once a day for reference.)
    def rest_of_month_forecast(period)
      # The page shows the final month to date on the last day (PRD 6.3).
      return [nil, :last_day] if period.last_day?

      response = client.get_cost_forecast(
        time_period: { start: period.today.iso8601, end: period.end_date.iso8601 },
        metric: "UNBLENDED_COST",
        granularity: "DAILY",
        prediction_interval_level: 80
      )
      days = response.forecast_results_by_time
      forecast = Forecast.new(
        mean: BigDecimal(response.total.amount).round(2),
        low: sum_of(days.map(&:prediction_interval_lower_bound)),
        high: sum_of(days.map(&:prediction_interval_upper_bound))
      )
      [forecast, nil]
    rescue Aws::CostExplorer::Errors::DataUnavailableException
      # Common early in a month: AWS has too little data to forecast (PRD F10).
      [nil, :insufficient_data]
    rescue Aws::CostExplorer::Errors::ServiceError => e
      # Any other forecast failure: fall back to the simple projection, but keep
      # the month-to-date figures from the first call.
      Rails.logger.warn("cost_fetch source=cost_explorer api=GetCostForecast result=error error=#{e.class.name.demodulize}")
      [nil, :error]
    end

    # nil unless every day has a value.
    def sum_of(amounts)
      return nil if amounts.empty? || amounts.any?(&:nil?)

      amounts.sum(BigDecimal("0")) { |a| BigDecimal(a) }.round(2)
    end

    def client
      @client ||= Aws::CostExplorer::Client.new(region: "us-east-1", **AwsClientOptions::DEFAULTS)
    end
  end
end

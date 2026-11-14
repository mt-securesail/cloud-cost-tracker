module CostSources
  # Month-to-date cost (by service) and the forecast for the rest of the month,
  # from Cost Explorer (PRD F4, F10, section 6.3).
  #
  # Every Cost Explorer request costs $0.01, so this makes at most 2 requests per
  # fetch (more only if AWS paginates the service list), and the refresher runs
  # it every few hours, never per page view.
  class CostExplorerTotals
    Forecast = Data.define(:mean, :low, :high)
    # forecast is nil when unavailable; forecast_note then says why.
    # by_service: { "Amazon EC2" => BigDecimal, ... }, used by the breakdown table (PR B).
    Result = Data.define(:month_to_date, :by_service, :forecast, :forecast_note)

    def initialize(client: nil, clock: -> { Time.now.utc })
      @client = client
      @clock = clock
    end

    def fetch
      period = BillingPeriod.current(@clock.call)
      by_service = month_to_date_by_service(period)
      forecast, note = forecast_for_rest_of(period)

      Result.new(
        month_to_date: by_service.values.sum(BigDecimal("0")).round(2),
        by_service: by_service,
        forecast: forecast,
        forecast_note: note
      )
    end

    private

    def month_to_date_by_service(period)
      totals = Hash.new(BigDecimal("0"))
      response = client.get_cost_and_usage(
        time_period: { start: period.start_date.iso8601, end: period.tomorrow.iso8601 },
        granularity: "MONTHLY",
        metrics: ["UnblendedCost"],
        group_by: [{ type: "DIMENSION", key: "SERVICE" }]
      )
      response.each_page do |page|
        page.results_by_time.each do |result|
          result.groups.each do |group|
            totals[group.keys.first] += BigDecimal(group.metrics.fetch("UnblendedCost").amount)
          end
        end
      end
      totals.transform_values { |amount| amount.round(2) }
    end

    def forecast_for_rest_of(period)
      # Nothing left to forecast on the last day (PRD 6.3).
      return [nil, :last_day] if period.last_day?

      response = client.get_cost_forecast(
        time_period: { start: period.today.iso8601, end: period.end_date.iso8601 },
        metric: "UNBLENDED_COST",
        granularity: "MONTHLY",
        prediction_interval_level: 80
      )
      interval = response.forecast_results_by_time.first
      forecast = Forecast.new(
        mean: BigDecimal(response.total.amount).round(2),
        low: interval && BigDecimal(interval.prediction_interval_lower_bound).round(2),
        high: interval && BigDecimal(interval.prediction_interval_upper_bound).round(2)
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

    def client
      @client ||= Aws::CostExplorer::Client.new(region: "us-east-1", **AwsClientOptions::DEFAULTS)
    end
  end
end

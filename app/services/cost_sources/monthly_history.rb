module CostSources
  # Cost by service for the 3 complete months before the current one, from
  # Cost Explorer (PRD F7, section 6.4), plus AWS Billing's month-end forecast
  # for reference. Past months barely change, so the refresher runs this once
  # a day: 2 requests ($0.02), more only if AWS paginates.
  class MonthlyHistory
    MONTHS = 3

    # period_start: the billing period this was fetched for, so a result from
    # last month is ignored after rollover (R7).
    # months: { Date (first of month) => { "service name" => BigDecimal } },
    # oldest first, always all 3 months (empty hash if AWS returned nothing).
    # billing_forecast: AWS's MONTHLY-granularity forecast for this whole month,
    # the figure Billing and Cost Management shows; nil if unavailable.
    Result = Data.define(:period_start, :months, :billing_forecast)

    def initialize(client: nil, clock: -> { Time.now.utc })
      @client = client
      @clock = clock
    end

    def fetch
      period = BillingPeriod.current(@clock.call)
      first = period.start_date << MONTHS
      months = (0...MONTHS).to_h { |i| [first >> i, Hash.new(BigDecimal("0"))] }

      response = client.get_cost_and_usage(
        time_period: { start: first.iso8601, end: period.start_date.iso8601 },
        granularity: "MONTHLY",
        metrics: ["UnblendedCost"],
        group_by: [{ type: "DIMENSION", key: "SERVICE" }]
      )
      response.each_page do |page|
        page.results_by_time.each do |result|
          month = Date.iso8601(result.time_period.start).beginning_of_month
          next unless months.key?(month)

          result.groups.each do |group|
            months[month][group.keys.first] += BigDecimal(group.metrics.fetch("UnblendedCost").amount)
          end
        end
      end

      Result.new(
        period_start: period.start_date,
        months: months, # unrounded; rounded only for display
        billing_forecast: billing_forecast(period)
      )
    end

    private

    # The console's "forecasted month-end costs". It extrapolates
    # month-over-month growth, so it can be far from the daily-pattern
    # estimate the page leads with (findings log #5). Shown for comparison
    # only; a failure here never fails the history fetch.
    def billing_forecast(period)
      return nil if period.last_day?

      response = client.get_cost_forecast(
        time_period: { start: period.today.iso8601, end: period.end_date.iso8601 },
        metric: "UNBLENDED_COST",
        granularity: "MONTHLY"
      )
      BigDecimal(response.total.amount).round(2)
    rescue Aws::CostExplorer::Errors::ServiceError => e
      Rails.logger.warn("cost_fetch source=history api=GetCostForecast result=error error=#{e.class.name.demodulize}")
      nil
    end

    def client
      @client ||= Aws::CostExplorer::Client.new(region: "us-east-1", **AwsClientOptions::DEFAULTS)
    end
  end
end

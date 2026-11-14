module CostSources
  # Cost by service for the 3 complete months before the current one, from
  # Cost Explorer (PRD F7, section 6.4). Past months barely change, so the
  # refresher runs this once a day: 1 request ($0.01), more only if AWS
  # paginates.
  class MonthlyHistory
    MONTHS = 3

    # period_start: the billing period this was fetched for, so a result from
    # last month is ignored after rollover (R7).
    # months: { Date (first of month) => { "service name" => BigDecimal } },
    # oldest first, always all 3 months (empty hash if AWS returned nothing).
    Result = Data.define(:period_start, :months)

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
        months: months # unrounded; rounded only for display
      )
    end

    private

    def client
      @client ||= Aws::CostExplorer::Client.new(region: "us-east-1", **AwsClientOptions::DEFAULTS)
    end
  end
end

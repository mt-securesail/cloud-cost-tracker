module CostSources
  # Month-to-date estimated charges for the whole account, from the CloudWatch
  # billing metric AWS/Billing EstimatedCharges (PRD F3, section 6.2).
  #
  # Needs "Receive CloudWatch billing alerts" turned on in the management
  # account, or the metric doesn't exist. Billing metrics live only in us-east-1.
  # GetMetricData costs $0.01 per 1,000 metrics requested: effectively free here.
  class CloudWatchCharges
    # amount is nil when there's no datapoint for the current period yet
    # (for example in the first hours of a month, before AWS publishes one).
    Result = Data.define(:amount, :as_of)

    LOOKBACK = 2.days
    # Hourly buckets, so the "as of" time is within an hour of when AWS
    # actually updated the number.
    BUCKET_SECONDS = 3600

    def initialize(client: nil, clock: -> { Time.now.utc })
      @client = client
      @clock = clock
    end

    def fetch
      now = @clock.call
      period = BillingPeriod.current(now)

      response = client.get_metric_data(
        start_time: now - LOOKBACK,
        end_time: now,
        scan_by: "TimestampDescending",
        metric_data_queries: [{
          id: "charges",
          return_data: true,
          metric_stat: {
            metric: {
              namespace: "AWS/Billing",
              metric_name: "EstimatedCharges",
              # No ServiceName dimension: the account total.
              dimensions: [{ name: "Currency", value: "USD" }]
            },
            period: BUCKET_SECONDS,
            stat: "Maximum"
          }
        }]
      )

      series = response.metric_data_results.first
      points = series ? series.timestamps.zip(series.values) : []
      timestamp, value = points.max_by(&:first)

      # The metric resets at the start of each month. A datapoint from the
      # previous month must never be shown as this month's charges.
      return Result.new(amount: nil, as_of: nil) if timestamp.nil? || timestamp < period.starts_at

      Result.new(amount: BigDecimal(value.to_s).round(2), as_of: timestamp.utc)
    end

    private

    def client
      @client ||= Aws::CloudWatch::Client.new(region: "us-east-1", **AwsClientOptions::DEFAULTS)
    end
  end
end

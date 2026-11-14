# Everything the dashboard shows, computed from CostStore (PRD 4.1, section 6).
# Pure: reads the store and the clock, never calls AWS.
class CostSummary
  # method: :forecast (AWS's whole-month forecast), :projection (simple
  # linear projection, PRD F10), or :final (last day of the month).
  Estimate = Data.define(:amount, :method, :low, :high, :note)

  attr_reader :period, :now

  def initialize(now: Time.now.utc, store: CostStore)
    @now = now.utc
    @period = BillingPeriod.current(@now)
    @cloudwatch = store.read(:cloudwatch)
    @cost_explorer = store.read(:cost_explorer)
    @history = store.read(:history)
  end

  # --- Current charges (F3), from CloudWatch ---

  def current_charges
    cloudwatch_result&.amount
  end

  # When AWS last updated the number (the datapoint's time), not when we fetched it.
  def current_charges_as_of
    cloudwatch_result&.as_of
  end

  def cloudwatch_error
    @cloudwatch.error
  end

  # True once CloudWatch has been read at least once (even if it had no
  # datapoint for this month yet).
  def cloudwatch_loaded?
    !@cloudwatch.fetched_at.nil?
  end

  # --- Estimated total (F4, F10), from Cost Explorer ---

  def month_to_date
    explorer_result&.month_to_date
  end

  def estimated_total
    return nil unless explorer_result

    mtd = explorer_result.month_to_date
    forecast = explorer_result.forecast

    if period.last_day?
      Estimate.new(amount: mtd, method: :final, low: nil, high: nil, note: nil)
    elsif forecast
      # AWS's forecast for the current month already includes the month to
      # date, so it is the estimated total as is (findings log #4). It can't
      # end below what's already been spent.
      Estimate.new(amount: [forecast.mean, mtd].max, method: :forecast,
                   low: forecast.low && [forecast.low, mtd].max,
                   high: forecast.high && [forecast.high, mtd].max, note: nil)
    else
      projected = (mtd / period.day_number * period.days_in_period).round(2)
      Estimate.new(amount: projected, method: :projection, low: nil, high: nil, note: explorer_result.forecast_note)
    end
  end

  # Cost Explorer doesn't report its own refresh time, so this is when the app
  # last fetched it successfully (PRD 5).
  def cost_explorer_as_of
    explorer_result && @cost_explorer.fetched_at
  end

  def cost_explorer_error
    @cost_explorer.error
  end

  def cost_explorer_loaded?
    !explorer_result.nil?
  end

  # --- By service (F6) and 3-month comparison (F7) ---

  # nil until Cost Explorer's month to date has loaded. The comparison
  # columns are empty until the daily history fetch has loaded too.
  def breakdown
    return nil unless explorer_result

    ServiceBreakdown.new(current: explorer_result.by_service, history: history_result&.months)
  end

  def history_as_of
    history_result && @history.fetched_at
  end

  def history_error
    @history.error
  end

  def history_loaded?
    !history_result.nil?
  end

  # --- Headline (F5) ---

  # The most recent "as of" time across all sources.
  def last_updated_at
    [current_charges_as_of, cost_explorer_as_of, history_as_of].compact.max
  end

  private

  # A datapoint from an earlier month is last month's total, not this month's (R7).
  def cloudwatch_result
    result = @cloudwatch.result
    return nil if result&.as_of && result.as_of < period.starts_at

    result
  end

  # History fetched for an earlier period has the wrong 3 months (R7).
  def history_result
    result = @history.result
    return nil if result.nil? || result.period_start != period.start_date

    result
  end

  # Ignore a result fetched in an earlier billing period: right after month
  # rollover it describes last month (R7). The next fetch replaces it.
  def explorer_result
    fetched_at = @cost_explorer.fetched_at
    return nil if fetched_at.nil? || fetched_at < period.starts_at

    @cost_explorer.result
  end
end

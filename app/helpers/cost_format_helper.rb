# Consistent formatting for amounts, dates, and times (PRD N5).
# Times are shown in UTC for now; local-time display comes with the page's
# JavaScript in a later PR.
module CostFormatHelper
  def usd(amount)
    amount.nil? ? "—" : number_to_currency(amount, unit: "$", precision: 2)
  end

  def format_date(date)
    date.strftime("%a, %b %-d, %Y")
  end

  def format_time(time)
    time.utc.strftime("%a, %b %-d, %Y %-l:%M %p UTC")
  end

  def age(time, now)
    "#{distance_of_time_in_words(time, now)} ago"
  end

  # "Mon, Nov 9, 2026 3:00 PM UTC (about 2 hours ago)", or a placeholder.
  def as_of(time, now, loaded:)
    return "not loaded yet" unless loaded
    return "no data yet this period" if time.nil?

    "#{format_time(time)} (#{age(time, now)})"
  end

  # Only the error class name, never its message (which can contain details).
  def refresh_failure(error)
    return if error.blank?

    "Last refresh failed (#{error.to_s.demodulize}); retrying at the next interval."
  end

  ESTIMATE_LABELS = {
    forecast: "Month to date + AWS forecast for the rest of the month",
    final: "Last day of the month: month to date",
    projection: "Projection (simple): month to date ÷ days so far × days in month"
  }.freeze

  FORECAST_NOTES = {
    insufficient_data: "AWS forecast unavailable: not enough data yet this month.",
    error: "AWS forecast unavailable right now.",
    last_day: nil
  }.freeze

  def estimate_label(estimate)
    ESTIMATE_LABELS.fetch(estimate.method)
  end

  def forecast_note(estimate)
    FORECAST_NOTES[estimate.note]
  end
end

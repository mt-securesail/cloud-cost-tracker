# Consistent formatting for amounts, dates, and times (PRD N5).
# Times render in UTC on the server; app/javascript/dashboard.js rewrites every
# <time data-local> into the browser's time zone, and keeps the "ago" text
# current with the same rules as #age.
module CostFormatHelper
  def usd(amount)
    return "—" if amount.nil?
    # Real but tiny costs (such as a short Bedrock test) would otherwise show as $0.00.
    return "< $0.01" if amount.positive? && amount < BigDecimal("0.005")

    number_to_currency(amount, unit: "$", precision: 2)
  end

  def format_date(date)
    date.strftime("%a, %b %-d, %Y")
  end

  def format_time(time)
    time.utc.strftime("%a, %b %-d, %Y %-l:%M %p UTC")
  end

  # Must match age() in app/javascript/dashboard.js.
  def age(time, now)
    seconds = [(now - time).to_i, 0].max
    if seconds < 60 then "just now"
    elsif seconds < 1.hour then "#{seconds / 60} min ago"
    elsif seconds < 48.hours then "#{seconds / 3600} h ago"
    else "#{seconds / 1.day} days ago"
    end
  end

  def local_time_tag(time)
    tag.time(format_time(time), datetime: time.utc.iso8601, data: { local: "" })
  end

  def age_tag(time, now)
    tag.span("(#{age(time, now)})", class: "muted", data: { since: time.utc.iso8601 })
  end

  # "2 hours", "1 hour", "30 minutes".
  def duration_words(seconds)
    seconds = seconds.to_i
    (seconds % 3600).zero? ? pluralize(seconds / 3600, "hour") : pluralize(seconds / 60, "minute")
  end

  # Only the error class name, never its message (which can contain details).
  def refresh_failure(error)
    return if error.blank?

    "Last refresh failed (#{error.to_s.demodulize}); retrying at the next interval."
  end

  ESTIMATE_LABELS = {
    forecast: "Month to date + AWS's daily forecast for the rest of the month",
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

# The dashboard's data as one hash: the page renders it server-side
# (app/views/home/index.html.erb), and GET /summary.json returns the same hash
# for app/javascript/dashboard.js to render in place (PRD R1). Amounts and
# labels are formatted here, once, so both always show the same text.
# Times stay as Time objects (ISO 8601 in JSON); the browser formats them.
module SummaryPayloadHelper
  SOURCE_LABELS = {
    cloudwatch: "Current charges (CloudWatch)",
    cost_explorer: "Estimated total and by service (Cost Explorer)",
    history: "Previous 3 months (Cost Explorer)"
  }.freeze

  NOT_LOADED = "Costs not loaded yet. The first fetch runs when the app starts; this page updates every 5 minutes."
  COMPARISON_FOOTNOTE = "* Month to date. Rows are this month's top 10 services plus every Bedrock model; " \
                        "other services are in \"Other\"."

  def summary_payload(summary, version:)
    s = summary
    {
      version: version,
      now: s.now,
      last_updated_at: s.last_updated_at,
      not_loaded_text: NOT_LOADED,
      sources: SOURCE_LABELS.map { |key, label| source_payload(s, key, label) },
      current_charges: current_charges_payload(s),
      estimated_total: estimated_total_payload(s),
      breakdown: breakdown_payload(s),
      period: {
        today: format_date(s.period.today),
        range: "#{format_date(s.period.start_date)} – #{format_date(s.period.last_date)}",
        day: "#{s.period.day_number} of #{s.period.days_in_period}"
      }
    }
  end

  private

  def source_payload(s, key, label)
    as_of = s.as_of(key)
    placeholder = if !s.loaded?(key) then "not loaded yet"
                  elsif as_of.nil? then "no data yet this period"
                  end
    stale = "Stale: no successful refresh in over #{duration_words(s.stale_after(key))}." if s.stale?(key)
    { key: key, label: label, as_of: as_of, placeholder: placeholder, stale: stale }
  end

  def current_charges_payload(s)
    amount = if !s.cloudwatch_loaded? then "Loading…"
             elsif s.current_charges.nil? then "No data yet this period"
             else usd(s.current_charges)
             end
    { amount: amount, warning: refresh_failure(s.cloudwatch_error) }
  end

  def estimated_total_payload(s)
    estimate = s.estimated_total
    details = []
    if estimate
      details << estimate_label(estimate)
      details << "Likely range: #{usd(estimate.low)} – #{usd(estimate.high)}" if estimate.low && estimate.high
      details << "Month to date (Cost Explorer): #{usd(s.month_to_date)}"
      details << forecast_note(estimate) if forecast_note(estimate)
    end
    {
      title: "Estimated total for #{s.period.start_date.strftime('%B')}",
      amount: estimate ? usd(estimate.amount) : "Loading…",
      details: details,
      warning: refresh_failure(s.cost_explorer_error)
    }
  end

  def breakdown_payload(s)
    b = s.breakdown
    return nil unless b

    totals = b.totals
    history_failure = refresh_failure(s.history_error)
    {
      rows: (b.rows + [b.other].compact).map do |row|
        pct = b.share(row.current)
        { name: row.name, bedrock: row.bedrock, current: usd(row.current), share: pct ? "#{pct}%" : "–",
          months: b.months.map { |m| usd(row.months[m]) } }
      end,
      total: { current: usd(totals.current), months: b.months.map { |m| usd(totals.months[m]) } },
      months: b.months.map { |m| m.strftime("%b") },
      current_month: s.period.start_date.strftime("%b"),
      # Shown instead of the comparison table until the history has loaded.
      history_message: b.months.empty? ? (history_failure || "Loading…") : nil,
      history_warning: b.months.empty? ? nil : history_failure,
      footnote: COMPARISON_FOOTNOTE
    }
  end
end

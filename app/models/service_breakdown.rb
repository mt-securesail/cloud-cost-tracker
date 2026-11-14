# The by-service rows shared by the "this month" table (PRD F6) and the
# 3-month comparison (F7).
#
# Rows: the top 10 services by month-to-date cost, plus every Amazon Bedrock
# model that cost anything in any shown month, even outside the top 10 (one
# row per model: Cost Explorer lists each model as its own service, such as
# "Claude Sonnet 4.5 (Amazon Bedrock Edition)"). Everything else is "Other".
class ServiceBreakdown
  TOP_N = 10
  ZERO = BigDecimal("0")

  # current: month to date (nil if none). months: { Date => amount or nil }.
  Row = Data.define(:name, :current, :months, :bedrock)

  def self.bedrock?(name)
    name.to_s.match?(/bedrock/i)
  end

  # current: { name => amount } for this month to date.
  # history: { Date => { name => amount } }, or nil if not loaded yet.
  def initialize(current:, history: nil)
    @current = current
    @history = history || {}
  end

  def months
    @history.keys.sort
  end

  def rows
    @rows ||= shown_names.map { |name| row_for(name, bedrock: self.class.bedrock?(name)) }
  end

  # nil when nothing falls outside the shown rows.
  def other
    hidden = all_names - shown_names
    return nil if hidden.empty?

    Row.new(
      name: "Other",
      current: sum(@current, hidden),
      months: months.to_h { |m| [m, sum(@history[m], hidden)] },
      bedrock: false
    )
  end

  def totals
    Row.new(
      name: "Total",
      current: @current.values.sum(ZERO),
      months: months.to_h { |m| [m, @history[m].values.sum(ZERO)] },
      bedrock: false
    )
  end

  # Share of this month's total, as a percentage (nil if the total is zero).
  def share(amount)
    total = totals.current
    return nil if amount.nil? || total.zero?

    (amount / total * 100).round(0)
  end

  private

  def all_names
    (@current.keys + @history.values.flat_map(&:keys)).uniq
  end

  def shown_names
    @shown_names ||= begin
      top = by_current_cost(@current.keys.select { |n| positive?(@current[n]) }).first(TOP_N)
      bedrock = all_names.select { |n| self.class.bedrock?(n) && ever_positive?(n) }
      top + by_current_cost(bedrock - top)
    end
  end

  def by_current_cost(names)
    names.sort_by { |n| [-(@current[n] || ZERO), n] }
  end

  def row_for(name, bedrock:)
    Row.new(
      name: name,
      current: positive_or_nil(@current[name], exact: bedrock),
      months: months.to_h { |m| [m, positive_or_nil(@history[m][name], exact: bedrock)] },
      bedrock: bedrock
    )
  end

  def sum(amounts, names)
    names.sum(ZERO) { |n| amounts.fetch(n, ZERO) }
  end

  # Amounts that round to $0.00 count as no cost, so they show as "–".
  # Bedrock models use exact amounts instead: a test scan can cost a fraction
  # of a cent, and you still want to see that the model was used.
  def positive?(amount, exact: false)
    return false if amount.nil?

    (exact ? amount : amount.round(2)).positive?
  end

  def positive_or_nil(amount, exact: false)
    positive?(amount, exact: exact) ? amount : nil
  end

  def ever_positive?(name)
    positive?(@current[name], exact: true) || @history.values.any? { |services| positive?(services[name], exact: true) }
  end
end

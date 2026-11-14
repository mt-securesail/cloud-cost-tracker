# The AWS billing period: the current calendar month in UTC (PRD 6.1).
# AWS bills by UTC calendar month, so every date here is a UTC date.
class BillingPeriod
  attr_reader :today, :start_date, :end_date # end_date is exclusive

  def self.current(now = Time.now.utc)
    new(now.utc.to_date)
  end

  def initialize(today)
    @today = today
    @start_date = today.beginning_of_month
    @end_date = @start_date.next_month
  end

  # Midnight UTC on the first day of the period.
  def starts_at
    Time.utc(start_date.year, start_date.month, start_date.day)
  end

  def last_date
    end_date - 1
  end

  def days_in_period
    (end_date - start_date).to_i
  end

  # 1 on the first day of the month.
  def day_number
    (today - start_date).to_i + 1
  end

  def last_day?
    today == last_date
  end

  def tomorrow
    today + 1
  end
end

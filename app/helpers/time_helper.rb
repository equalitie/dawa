module TimeHelper
  TIME_FORMATS = {
    time: "%l:%M%P",                        # 1:30 pm

    day: "%b %e, %l:%M%P",                  # Jan 1, 1:30pm
    day_long: "%B %e, %l:%M%P",             # January 1, 1:30pm

    date: "%b %e %Y, %l:%M%P",              # Jan 1 2025, 1:30pm
    date_long: "%B %e %Y, %l:%M%P",         # January 1 2025, 1:30pm

    weekday: "%a %b %e, %l:%M%P",           # Wed Jan 1, 1:30pm
    weekdate: "%a %b %e %Y, %l:%M%P",       # Wed Jan 1 2025, 1:30pm

    year: "%Y-%m-%d",                        # 2025-05-01
    stamp: "%Y-%m-%d %l:%M%P %Z"             # 2025-05-01 1:30pm Pacific Standard Time
  }.freeze

  DATE_FORMATS = {
    time: "%b %e",                          # Jan 1

    day: "%b %e",                           # Jan 1
    day_long: "%B %e",                      # January 1

    date: "%b %e %Y",                       # Jan 1 2025
    date_long: "%B %e %Y",                  # January 1 2025

    weekday: "%a %b %e",                    # Wed Jan 1
    weekdate: "%a %b %e %Y",                # Wed Jan 1 2025

    year: "%Y-%m-%d",                       # 2025-05-01
    stamp: "%Y-%m-%d"
  }

  #
  # displays str (or block) with time tooltip
  #
  def time_tooltip(time, str = nil)
    return "" unless time
    content_tag(:time, "data-bs-toggle": "tooltip", "data-bs-title": format_time(time, :stamp)) do
      if str
        str
      elsif block_given?
        yield
      end
    end
  end

  #
  # display time ago in words, with full timestamp in the tooltip
  #
  def time_ago(time)
    if time
      time_tooltip(time, time_ago_in_words(time))
    end
  end

  #
  # This is the main helper one should use to display a single time value.
  #
  # It tries its best to auto guess what the best way to display a time or date.
  #
  def datetime(time, reference_time = Time.now, long: false)
    return "" unless time
    if same_day?(time, reference_time)
      display_time(time, :time)
    elsif same_year?(time, reference_time)
      long ? display_date(time, :day_long) : display_date(time, :day)
    else
      long ? display_date(time, :date_long) : display_date(time, :date)
    end
  end

  def display_time(time, format = :time)
    return "" unless time
    time_tooltip(time, format_time(time, format))
  end

  def display_date(time, format = :day)
    return "" unless time
    time_tooltip(time, format_date(time, format))
  end

  def display_month(time, reference_time = Time.now)
    if same_year?(time, reference_time)
      time.strftime("%B")
    else
      time.strftime("%B %Y")
    end
  end

  def format_date(date, format)
    if date
      if DATE_FORMATS[format]
        date.strftime(DATE_FORMATS[format])
      else
        I18n.localize date, format: format
      end
    end
  end

  def format_time(time, format)
    if time
      if time.is_a?(Date)
        format_date(time, format)
      elsif TIME_FORMATS[format]
        time.strftime(TIME_FORMATS[format])
      else
        I18n.localize time, format: format
      end
    end
  end

  def display_time_range(first, second, date = nil)
    if second.nil?
      datetime(first, date)
    else
      safe_join [ datetime(first, date), " &ndash; ".html_safe, datetime(second, date) ]
    end
  end

  #
  # Displays the range of two dates. It tries to show the most compact version
  # needed to convey all the information. The date param is the reference date
  # that the range is relative to. For example, if the date is a different
  # year than the range specified, then the year is included in the display,
  # otherwise it is only shown when the range spans a year boundary.
  #
  def display_date_range(first, second, date = Time.now)
    if first == second || second.nil?
      display_date(first)
    else
      same_month = same_month?(first, second)
      same_year = same_year?(first, second)
      if same_month && same_year
        if same_year?(first, date)
          "%s %s&ndash;%s".html_safe % [
            t('date.month_names')[first.month],
            first.day,
            second.day
          ]
        else
          "%s %s&ndash;%s, %s".html_safe % [
            t('date.month_names')[first.month],
            first.day,
            second.day,
            first.year
          ]
        end
      elsif !same_month && same_year
        if same_year?(first, date)
          "%s %s &ndash; %s %s".html_safe % [
            t('date.month_names')[first.month],
            first.day,
            t('date.month_names')[second.month],
            second.day
          ]
        else
          "%s %s &ndash; %s %s, %s".html_safe % [
            t('date.month_names')[first.month],
            first.day,
            t('date.month_names')[second.month],
            second.day,
            first.year
          ]
        end
      else
        "%s %s, %s &ndash; %s %s, %s".html_safe % [
          t('date.month_names')[first.month],
          first.day,
          first.year,
          t('date.month_names')[second.month],
          second.day,
          second.year
        ]
      end
    end
  end

  def display_week_range(date)
    week_start = date.beginning_of_week
    week_end = date.end_of_week
    display_date_range(week_start, week_end)
  end

  # def local(time)
  #  time.in_local_zone(current_zone)
  # end

  #
  # returns true if time1 and time2 are from the same years,
  # according to the timezone in time1.
  #
  def same_year?(time1, time2)
    if !time1.is_a?(Date) && !time2.is_a?(Date) && time1.zone != time2.zone
      time2 = time2.in_time_zone(ActiveSupport::TimeZone[time1.zone])
    end
    time1.year == time2.year
  end

  #
  # returns true if time1 and time2 are from the same month,
  # according to the timezone in time1.
  #
  def same_month?(time1, time2)
    if !time1.is_a?(Date) && !time2.is_a?(Date) && time1.zone != time2.zone
      time2 = time2.in_time_zone(ActiveSupport::TimeZone[time1.zone])
    end
    time1.year == time2.year && time1.month == time2.month
  end

  #
  # returns true if time1 and time2 are from the same day,
  # according to the timezone in time1.
  #
  def same_day?(time1, time2)
    if !time1.is_a?(Date) && !time2.is_a?(Date) && time1.zone != time2.zone
      time2 = time2.in_time_zone(ActiveSupport::TimeZone[time1.zone])
    end
    time1.year == time2.year && time1.month == time2.month && time1.day == time2.day
  end
end

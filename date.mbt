///|
/// Date values are UTC epoch milliseconds; no ambient locale or system zone.
pub fn default_date_format() -> String {
  "yyyy-MM-dd'T'HH:mm:ss"
}

///|
priv enum DatePart {
  Literal(String)
  Field(Char, Int32)
}

///|
fn date_parts(pattern : String) -> Array[DatePart] raise ArffError {
  if pattern.is_empty() || pattern.length() > 256 {
    raise Invalid("date format must contain 1..256 UTF-16 units")
  }
  let chars : Array[Char] = []
  for ch in pattern {
    chars.push(ch)
  }
  let parts = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\'' {
      let out = StringBuilder()
      i += 1
      if i < chars.length() && chars[i] == '\'' {
        out.write_char('\'')
        i += 1
      } else {
        let mut closed = false
        while i < chars.length() {
          let d = chars[i]
          i += 1
          if d == '\'' {
            if i < chars.length() && chars[i] == '\'' {
              out.write_char('\'')
              i += 1
            } else {
              closed = true
              break
            }
          } else {
            out.write_char(d)
          }
        }
        if !closed {
          raise Invalid("unclosed date format literal")
        }
      }
      parts.push(Literal(out.to_string()))
    } else if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
      let start = i
      while i < chars.length() && chars[i] == c {
        i += 1
      }
      let n = i - start
      // SimpleDateFormat treats most run lengths as minimum padding. Run
      // length only changes the textual form of M/E; X is explicitly 1..3.
      let supported = match c {
        'y'
        | 'Y'
        | 'w'
        | 'W'
        | 'F'
        | 'G'
        | 'M'
        | 'L'
        | 'd'
        | 'D'
        | 'E'
        | 'H'
        | 'h'
        | 'K'
        | 'k'
        | 'a'
        | 'm'
        | 's'
        | 'S'
        | 'u'
        | 'z'
        | 'Z' => n >= 1
        'X' => n >= 1 && n <= 3
        _ => false
      }
      if !supported {
        raise Unsupported(
          "date field outside deterministic GregorianCalendar profile: " +
          c.to_string(),
        )
      }
      // Calendar stamps are retained while parsing, so consistent repeated
      // fields and mixed 12/24-hour clocks remain representable.
      parts.push(Field(c, n))
    } else {
      parts.push(Literal(c.to_string()))
      i += 1
    }
  }
  parts
}

///|
fn date_floor_div(value : Int32, divisor : Int32) -> Int32 {
  let quotient = value / divisor
  let remainder = value % divisor
  if value < 0 && remainder != 0 {
    quotient - 1
  } else {
    quotient
  }
}

///|
fn leap(year : Int32) -> Bool {
  year % 4 == 0 && (year < 1582 || year % 100 != 0 || year % 400 == 0)
}

///|
fn month_days(year : Int32, month : Int32) -> Int32 {
  match month {
    2 => if leap(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn days_from_date(year : Int32, month : Int32, day : Int32) -> Int32 {
  if year < 1582 || (year == 1582 && (month < 10 || (month == 10 && day <= 4))) {
    let a = (14 - month) / 12
    let y = year + 4800 - a
    let m = month + 12 * a - 3
    return day +
      (153 * m + 2) / 5 +
      365 * y +
      date_floor_div(y, 4) -
      32083 -
      2440588
  }
  let y = if month <= 2 { year - 1 } else { year }
  let era = y / 400
  let yoe = y - era * 400
  let mp = month + (if month > 2 { -3 } else { 9 })
  let doy = (153 * mp + 2) / 5 + day - 1
  era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
}

///|
fn date_from_days(days : Int32) -> (Int32, Int32, Int32) {
  if days < -141427 {
    let c = days + 2440588 + 32082
    let d = date_floor_div(4 * c + 3, 1461)
    let e = c - date_floor_div(1461 * d, 4)
    let m = date_floor_div(5 * e + 2, 153)
    return (
      d - 4800 + date_floor_div(m, 10),
      m + 3 - 12 * date_floor_div(m, 10),
      e - date_floor_div(153 * m + 2, 5) + 1,
    )
  }
  let z = days + 719468
  let era = if z >= 0 { z / 146097 } else { (z - 146096) / 146097 }
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = mp + (if mp < 10 { 3 } else { -9 })
  (yoe + era * 400 + (if month <= 2 { 1 } else { 0 }), month, day)
}

///|
fn date_lower_ascii(code : UInt16) -> UInt16 {
  if code >= 65 && code <= 90 {
    code + 32
  } else {
    code
  }
}

///|
fn date_name_index(
  text : String,
  start : Int32,
  names : Array[String],
) -> (Int32, Int32) {
  for index, name in names {
    if start + name.length() <= text.length() {
      let mut equal = true
      for j = 0; j < name.length(); j = j + 1 {
        if date_lower_ascii(text[start + j]) != date_lower_ascii(name[j]) {
          equal = false
          break
        }
      }
      if equal {
        return (index, name.length())
      }
    }
  }
  (-1, 0)
}

///|
fn month_names(short : Bool) -> Array[String] {
  if short {
    [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
      "Dec",
    ]
  } else {
    [
      "January", "February", "March", "April", "May", "June", "July", "August", "September",
      "October", "November", "December",
    ]
  }
}

///|
fn weekday_names(short : Bool) -> Array[String] {
  if short {
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  } else {
    [
      "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]
  }
}

///|
fn weekday_index(days : Int32) -> Int32 {
  ((days + 4) % 7 + 7) % 7
}

///|
fn first_week_start(year : Int32) -> Int32 {
  let jan1 = days_from_date(year, 1, 1)
  jan1 - weekday_index(jan1)
}

///|
fn week_year_and_number(days : Int32) -> (Int32, Int32) {
  let (calendar_year, _, _) = date_from_days(days)
  let start = first_week_start(calendar_year)
  if days < start {
    let week_year = calendar_year - 1
    (week_year, (days - first_week_start(week_year)) / 7 + 1)
  } else {
    let next = first_week_start(calendar_year + 1)
    if days >= next {
      (calendar_year + 1, (days - next) / 7 + 1)
    } else {
      (calendar_year, (days - start) / 7 + 1)
    }
  }
}

///|
// Java accepts both long and short text names regardless of formatting width.
// Try long names first so a short prefix does not consume only part of a name.
fn date_text_name(text : String, start : Int32, month : Bool) -> (Int32, Int32) {
  let full = if month { month_names(false) } else { weekday_names(false) }
  let found = date_name_index(text, start, full)
  if found.0 >= 0 {
    found
  } else {
    let short = if month { month_names(true) } else { weekday_names(true) }
    date_name_index(text, start, short)
  }
}

///|
fn date_digits(
  text : String,
  start : Int32,
  count : Int32,
) -> Int32 raise ArffError {
  if count < 1 || start + count > text.length() {
    raise Invalid("truncated date field")
  }
  let mut value = 0
  for i = start; i < start + count; i = i + 1 {
    let c = text[i].to_int() - 48
    if c < 0 || c > 9 {
      raise Invalid("date field requires digits")
    }
    if value > (2147483647 - c) / 10 {
      raise Invalid("date field exceeds signed 32-bit range")
    }
    value = value * 10 + c
  }
  value
}

///|
/// Parse English-locale Java date patterns; values are UTC epoch milliseconds.
/// Abbreviated years use SimpleDateFormat's rolling 80-year start.
pub fn parse_date(text : String, pattern : String) -> Double raise ArffError {
  parse_date_window(text, pattern, date_century_start())
}

///|
fn date_century_start() -> Double {
  let now = @env.now().to_double()
  let days = (now / 86400000.0).to_int()
  let (year, month, day) = date_from_days(days)
  let start_year = year - 80
  let start_day = if day > month_days(start_year, month) {
    month_days(start_year, month)
  } else {
    day
  }
  days_from_date(start_year, month, start_day).to_double() * 86400000.0 +
  now -
  days.to_double() * 86400000.0
}

///|
fn parse_date_window(
  text : String,
  pattern : String,
  century_start : Double,
) -> Double raise ArffError {
  let parts = date_parts(pattern)
  let mut pos = 0
  let (start_year, _, _) = date_from_days(
    @double.floor(century_start / 86400000.0).to_int(),
  )
  let mut ambiguous_year = false
  let mut ambiguous_week_year = false
  let mut year = 1970
  let mut week_year = 1970
  let mut week_number = 1
  let mut year_stamp = -1
  let mut has_calendar_year = false
  let mut week_year_stamp = -1
  let mut has_week_year = false
  let mut has_week_number = false
  let mut week_of_month = 0
  let mut has_week_of_month = false
  let mut weekday_ordinal = 0
  let mut has_weekday_ordinal = false
  let mut month = 1
  let mut day = 1
  let mut day_of_year = 0
  let mut has_day_of_year = false
  let mut has_month = false
  let mut has_day = false
  let mut weekday = -1
  let mut day_stamp = -1
  let mut week_stamp = -1
  let mut week_month_stamp = -1
  let mut weekday_ordinal_stamp = -1
  let mut doy_stamp = -1
  let mut hour = 0
  let mut hour24 : Int32? = None
  let mut hour12 : Int32? = None
  let mut stamp24 = -1
  let mut stamp12 = -1
  let mut stamp_ampm = -1
  let mut ampm = -1
  let mut minute = 0
  let mut second = 0
  let mut millis = 0
  let mut zone : DateZone = { id: "UTC", raw: None, dst: None, }
  let mut before_common_era = false
  for index, part in parts {
    match part {
      Literal(s) =>
        for code in s.code_units() {
          if pos >= text.length() || text[pos] != code {
            raise Invalid("date literal mismatch")
          }
          pos += 1
        }
      Field(c, n) =>
        if c == 'E' {
          let (found, width) = date_text_name(text, pos, false)
          if found < 0 {
            raise Invalid("invalid English weekday name")
          }
          weekday = found
          pos += width
        } else if (c == 'M' || c == 'L') && n >= 3 {
          let (found, width) = date_text_name(text, pos, true)
          if found < 0 {
            raise Invalid("invalid English month name")
          }
          month = found + 1
          has_month = true
          pos += width
        } else if c == 'G' {
          let (ad, ad_width) = date_name_index(text, pos, ["AD"])
          if ad >= 0 {
            before_common_era = false
            pos += ad_width
          } else {
            let (bc, bc_width) = date_name_index(text, pos, ["BC"])
            if bc >= 0 {
              before_common_era = true
              pos += bc_width
            } else {
              raise Invalid("expected AD or BC era")
            }
          }
        } else if c == 'a' {
          let names = ["AM", "PM"]
          let (found, width) = date_name_index(text, pos, names)
          if found < 0 {
            raise Invalid("expected AM or PM")
          }
          ampm = found
          stamp_ampm = index
          pos += width
        } else if c == 'z' || c == 'Z' || c == 'X' {
          let (offset, consumed) = date_parse_zone(text, pos, c, n, zone)
          zone = offset
          pos += consumed
        } else {
          // NumberFormat skips leading spaces even with adjacent numeric fields.
          while pos < text.length() && (text[pos] == 32 || text[pos] == 9) {
            pos += 1
          }
          let mut width = n
          let adjacent = if index + 1 < parts.length() {
            match parts[index + 1] {
              Field(next, count) =>
                next != 'X' &&
                next != 'Z' &&
                next != 'E' &&
                next != 'a' &&
                !((next == 'M' || next == 'L') && count >= 3) &&
                next != 'z' &&
                next != 'G'
              _ => false
            }
          } else {
            false
          }
          if !adjacent {
            width = 0
            while pos + width < text.length() &&
                  text[pos + width] >= 48 &&
                  text[pos + width] <= 57 {
              width += 1
            }
            if width == 0 {
              raise Invalid("date field requires digits")
            }
          }
          let v = date_digits(text, pos, width)
          pos += width
          match c {
            'Y' => {
              ambiguous_week_year = n <= 2 && width == 2
              week_year = if ambiguous_week_year {
                let candidate = start_year / 100 * 100 + v
                if candidate < start_year {
                  candidate + 100
                } else {
                  candidate
                }
              } else {
                v
              }
              has_week_year = true
              week_year_stamp = index
            }
            'w' => {
              week_number = v
              has_week_number = true
              week_stamp = index
            }
            'W' => {
              week_of_month = v
              has_week_of_month = true
              week_month_stamp = index
            }
            'F' => {
              weekday_ordinal = v
              has_weekday_ordinal = true
              weekday_ordinal_stamp = index
            }
            'y' => {
              has_calendar_year = true
              ambiguous_year = n <= 2 && width == 2
              year = if ambiguous_year {
                let candidate = start_year / 100 * 100 + v
                if candidate < start_year {
                  candidate + 100
                } else {
                  candidate
                }
              } else {
                v
              }
              year_stamp = index
            }
            'M' | 'L' => {
              month = v
              has_month = true
            }
            'd' => {
              day = v
              has_day = true
              day_stamp = index
            }
            'u' => {
              if v < 1 || v > 7 {
                raise Invalid("weekday outside 1..7")
              }
              weekday = v % 7
            }
            'D' => {
              day_of_year = v
              has_day_of_year = true
              doy_stamp = index
            }
            'E' => ()
            'H' | 'h' | 'K' | 'k' => {
              hour = v
              if c == 'H' || c == 'k' {
                if (c == 'H' && v > 23) || (c == 'k' && (v < 1 || v > 24)) {
                  raise Invalid("invalid 24-hour clock value")
                }
                hour24 = Some(if c == 'k' && v == 24 { 0 } else { v })
                stamp24 = index
              } else {
                if (c == 'h' && (v < 1 || v > 12)) || (c == 'K' && v > 11) {
                  raise Invalid("invalid 12-hour clock value")
                }
                hour12 = Some(v % 12)
                stamp12 = index
              }
            }
            'm' => minute = v
            's' => second = v
            'S' => millis = v
            _ => ()
          }
        }
    }
  }
  // Weka calls DateFormat.parse(String), whose ParsePosition permits a suffix.
  // Field parsing itself must still consume every required pattern component.
  if year < 1 || year > 300000 || week_year < 1 || week_year > 300000 {
    raise Invalid("year outside exact-millisecond calendar envelope")
  }
  let stamp_half = if stamp12 > stamp_ampm { stamp12 } else { stamp_ampm }
  hour = if stamp24 >= stamp_half {
    hour24.unwrap_or(0)
  } else {
    hour12.unwrap_or(0) + (if ampm < 0 { 0 } else { ampm }) * 12
  }
  if (hour24 is Some(v) && v != hour) ||
    (hour12 is Some(v) && v != hour % 12) ||
    (ampm >= 0 && ampm != hour / 12) {
    raise Invalid("conflicting hour fields")
  }
  // Resolve the exact pivot instant before validating century-sensitive fields.
  if (ambiguous_year && year == start_year) ||
    (ambiguous_week_year && week_year == start_year) {
    let effective_year = if before_common_era { 1 - year } else { year }
    let effective_week_year = if before_common_era {
      1 - week_year
    } else {
      week_year
    }
    let candidate_days = if has_week_year && has_week_number {
      first_week_start(effective_week_year) + (week_number - 1) * 7 + weekday
    } else if has_day_of_year {
      days_from_date(effective_year, 1, 1) + day_of_year - 1
    } else if has_week_of_month {
      let first = days_from_date(effective_year, month, 1)
      first - weekday_index(first) + (week_of_month - 1) * 7 + weekday
    } else if has_weekday_ordinal {
      let first = days_from_date(effective_year, month, 1)
      first +
      (weekday - weekday_index(first) + 7) % 7 +
      (weekday_ordinal - 1) * 7
    } else {
      days_from_date(effective_year, month, day)
    }
    let wall = candidate_days.to_double() * 86400000.0 +
      (hour * 3600000 + minute * 60000 + second * 1000 + millis).to_double()
    let candidate = wall - date_zone_offset(zone, wall).to_double() * 1000.0
    if candidate < century_start {
      if ambiguous_year {
        year += 100
      }
      if ambiguous_week_year {
        week_year += 100
      }
    }
  }
  if before_common_era {
    year = 1 - year
  }
  if before_common_era {
    week_year = 1 - week_year
  }

  let calendar_choice = [
    year_stamp, doy_stamp, day_stamp, week_month_stamp, weekday_ordinal_stamp,
  ].fold(init=-1, fn(best, next) { if next > best { next } else { best } })
  let use_week_year = has_week_year && week_year_stamp > calendar_choice
  if use_week_year {
    if week_number < 1 || week_number > 53 {
      raise Invalid("week date outside supported range")
    }
    let selected_year = if week_year_stamp >= 0 { week_year } else { year }
    let dow = if weekday < 0 { 0 } else { weekday }
    let actual_days = first_week_start(selected_year) +
      (week_number - 1) * 7 +
      dow
    let (actual_year, actual_month, actual_day) = date_from_days(actual_days)
    let (wy, wn) = week_year_and_number(actual_days)
    if wy != selected_year ||
      wn != week_number ||
      (selected_year == 1 && actual_year == 0) {
      raise Invalid("invalid week-of-year date")
    }
    year = actual_year
    month = actual_month
    day = actual_day
  } else if has_week_year && week_year_stamp > calendar_choice {
    // A lone Y/w uses Calendar's week fields with the cleared Sunday weekday.
    let wy = if week_year_stamp > year_stamp { week_year } else { year }
    let wn = if week_stamp >= 0 { week_number } else { 1 }
    let actual_days = first_week_start(wy) + (wn - 1) * 7
    let (ty, tm, td) = date_from_days(actual_days)
    year = ty
    month = tm
    day = td
  } else {
    // Missing fields follow Calendar.clear(): 1970, January and midnight.
    // A supplied weekday without a day chooses its first occurrence in month;
    // W/F/w choose Sunday if the weekday itself was omitted.
    if has_day_of_year {
      let target = days_from_date(year, 1, 1) + day_of_year - 1
      let (ty, tm, td) = date_from_days(target)
      if ty != year || (has_month && tm != month) || (has_day && td != day) {
        raise Invalid("day-of-year conflicts with calendar date")
      }
      month = tm
      day = td
    } else if !has_day {
      let dow = if weekday < 0 { 0 } else { weekday }
      let first = days_from_date(year, month, 1)
      let target = if has_week_of_month {
        first - weekday_index(first) + (week_of_month - 1) * 7 + dow
      } else if has_weekday_ordinal || (weekday >= 0 && !has_week_number) {
        let ordinal = if has_weekday_ordinal { weekday_ordinal } else { 1 }
        first + (dow - weekday_index(first) + 7) % 7 + (ordinal - 1) * 7
      } else if has_week_number {
        first_week_start(year) + (week_number - 1) * 7 + dow
      } else {
        first
      }
      let (ty, tm, td) = date_from_days(target)
      if (has_calendar_year && ty != year && !(year == 1 && ty == 0)) ||
        ((has_month || has_week_of_month || has_weekday_ordinal) && tm != month) {
        raise Invalid("week fields conflict with calendar date")
      }
      year = ty
      month = tm
      day = td
    }
    let resolved = days_from_date(year, month, day)
    let first = days_from_date(year, month, 1)
    if (
        has_week_number &&
        (week_number < 1 || week_year_and_number(resolved).1 != week_number)
      ) ||
      (
        has_week_of_month &&
        (
          week_of_month < 1 ||
          (resolved - (first - weekday_index(first))) / 7 + 1 != week_of_month
        )
      ) ||
      (
        has_weekday_ordinal &&
        (weekday_ordinal < 1 || (resolved - first) / 7 + 1 != weekday_ordinal)
      ) {
      raise Invalid("week fields conflict with calendar date")
    }
  }
  if month < 1 ||
    month > 12 ||
    day < 1 ||
    day > month_days(year, month) ||
    (year == 1582 && month == 10 && day >= 5 && day <= 14) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    millis > 999 {
    raise Invalid("invalid Gregorian date/time")
  }
  // In the cutover month Calendar's strict W/F selector cannot resolve the
  // skipped civil days. An explicit day without a weekday instead validates
  // the derived week fields, and is not subject to selector rejection.
  if year == 1582 &&
    month == 10 &&
    (has_week_of_month || has_weekday_ordinal) &&
    (!has_day || weekday >= 0) {
    let sequence = if has_week_of_month {
      week_of_month
    } else {
      weekday_ordinal
    }
    if weekday < 1 ||
      weekday > 4 ||
      sequence != 1 ||
      (has_week_of_month && has_weekday_ordinal && weekday_ordinal != 1) {
      raise Invalid("week fields invalid at Gregorian cutover")
    }
  }
  let days = days_from_date(year, month, day)
  // Strict GregorianCalendar validates an explicitly supplied weekday against
  // an explicit calendar date; a weekday without a day remains a selector.
  if has_day && weekday >= 0 && weekday_index(days) != weekday {
    raise Invalid("weekday conflicts with calendar date")
  }
  let wall = days.to_double() * 86400000.0 +
    (hour * 3600000 + minute * 60000 + second * 1000 + millis).to_double()
  let value = wall - date_zone_offset(zone, wall).to_double() * 1000.0
  let normalized = date_zone_normalized_wall(zone, value)
  if normalized != wall &&
    date_format_at(normalized, parts, 0) != date_format_at(wall, parts, 0) {
    raise Invalid("date fields changed by timezone normalization")
  }
  if value < -9007199254740991.0 || value > 9007199254740991.0 {
    raise Invalid("date exceeds exact-millisecond calendar range")
  }
  value
}

///|
fn padded_date(value : Int32, width : Int32) -> String {
  let text = value.to_string()
  let out = StringBuilder()
  for i = text.length(); i < width; i = i + 1 {
    out.write_char('0')
  }
  out.write_string(text)
  out.to_string()
}

///|
fn date_format_at(
  value : Double,
  parts : Array[DatePart],
  zone : Int32,
) -> String raise ArffError {
  let value = value + zone.to_double() * 60000.0
  if !finite(value) || value < -9007199254740991.0 || value > 9007199254740991.0 {
    raise Invalid("date exceeds exact-millisecond calendar range")
  }
  let mut days = (value / 86400000.0).to_int()
  if days.to_double() * 86400000.0 > value {
    days -= 1
  }
  let rem = value - days.to_double() * 86400000.0
  if rem != rem.to_int().to_double() {
    raise Invalid("date must contain whole milliseconds")
  }
  let rest = rem.to_int()
  let (y, m, d) = date_from_days(days)
  let out = StringBuilder()
  for part in parts {
    match part {
      Literal(s) => out.write_string(s)
      Field(c, n) =>
        match c {
          'X' => out.write_string(date_format_zone(zone, c, n))
          'G' => out.write_string(if y <= 0 { "BC" } else { "AD" })
          'z' => out.write_string(date_format_zone(zone, c, n))
          'Z' => out.write_string(date_format_zone(zone, c, n))
          'E' => out.write_string(weekday_names(n <= 3)[weekday_index(days)])
          'M' | 'L' if n >= 3 => out.write_string(month_names(n == 3)[m - 1])
          'a' => out.write_string(if rest / 3600000 < 12 { "AM" } else { "PM" })
          _ => {
            let hour = rest / 3600000
            let v = match c {
              'y' => {
                let year_of_era = if y <= 0 { 1 - y } else { y }
                if n == 2 {
                  year_of_era % 100
                } else {
                  year_of_era
                }
              }
              'Y' => {
                let (wy, _) = week_year_and_number(days)
                let year_of_era = if wy <= 0 { 1 - wy } else { wy }
                if n == 2 {
                  year_of_era % 100
                } else {
                  year_of_era
                }
              }
              'w' => week_year_and_number(days).1
              'W' => {
                let first = days_from_date(y, m, 1)
                (days - (first - weekday_index(first))) / 7 + 1
              }
              'F' => {
                let first = days_from_date(y, m, 1)
                let first_matching = first +
                  (weekday_index(days) - weekday_index(first) + 7) % 7
                (days - first_matching) / 7 + 1
              }
              'M' | 'L' => m
              'd' => d
              'D' => days - days_from_date(y, 1, 1) + 1
              'u' => (weekday_index(days) + 6) % 7 + 1
              'H' => hour
              'k' => if hour == 0 { 24 } else { hour }
              'h' => if hour % 12 == 0 { 12 } else { hour % 12 }
              'K' => hour % 12
              'm' => rest / 60000 % 60
              's' => rest / 1000 % 60
              'S' => rest % 1000
              _ => 0
            }
            out.write_string(padded_date(v, n))
          }
        }
    }
  }
  out.to_string()
}

///|
pub fn format_date(value : Double, pattern : String) -> String raise ArffError {
  let parts = date_parts(pattern)
  let utc = date_format_at(value, parts, 0)
  if (try parse_date(utc, pattern) == value catch {
      _ => false
    }) {
    return utc
  }
  let mut has_zone = false
  let mut quantum = 86400000
  for part in parts {
    if part is Field(c, _) {
      match c {
        'z' | 'Z' | 'X' => has_zone = true
        'H' | 'h' | 'K' | 'k' => if quantum > 3600000 { quantum = 3600000 }
        'm' => if quantum > 60000 { quantum = 60000 }
        's' => if quantum > 1000 { quantum = 1000 }
        'S' => quantum = 1
        _ => ()
      }
    }
  }
  if has_zone {
    // A date-only z/Z/X pattern may represent local midnight, not UTC midnight.
    // Try the smallest fixed offset that preserves every supplied millisecond.
    for magnitude = 1; magnitude <= 1439; magnitude = magnitude + 1 {
      for zone in [magnitude, -magnitude] {
        let shifted = value + zone.to_double() * 60000.0
        if shifted % quantum.to_double() != 0.0 {
          continue
        }
        let text = date_format_at(value, parts, zone) catch { _ => continue }
        if (try parse_date(text, pattern) == value catch {
            _ => false
          }) {
          return text
        }
      }
    }
  }
  raise Invalid("date pattern would lose timestamp precision")
}

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
/// Mirror java.util.Calendar.selectFields for date fields in a strict
/// SimpleDateFormat parse. -1 denotes a field that was never set.
fn date_calendar_selection(
  month_stamp : Int32,
  day_stamp : Int32,
  wom_stamp : Int32,
  dowim_stamp : Int32,
  doy_stamp : Int32,
  woy_stamp : Int32,
  dow_stamp : Int32,
) -> Int32 {
  let aggregate = fn(a : Int32, b : Int32) -> Int32 {
    if a < 0 || b < 0 {
      -1
    } else if a > b {
      a
    } else {
      b
    }
  }
  let mut wom = aggregate(wom_stamp, dow_stamp)
  let mut dowim = aggregate(dowim_stamp, dow_stamp)
  let mut woy = aggregate(woy_stamp, dow_stamp)
  let mut dom = day_stamp
  let mut best = dom
  if wom > best {
    best = wom
  }
  if dowim > best {
    best = dowim
  }
  if doy_stamp > best {
    best = doy_stamp
  }
  if woy > best {
    best = woy
  }
  if best < 0 {
    wom = wom_stamp
    dowim = if dowim_stamp > dow_stamp { dowim_stamp } else { dow_stamp }
    woy = woy_stamp
    best = if wom > dowim { wom } else { dowim }
    if woy > best {
      best = woy
    }
    if best < 0 {
      dom = month_stamp
      best = dom
    }
  }
  if best == dom ||
    (best == wom && wom_stamp >= woy_stamp) ||
    (best == dowim && dowim_stamp >= woy_stamp) {
    if best == dom {
      return 0
    }
    if wom == dowim {
      return if wom_stamp >= dowim_stamp { 1 } else { 2 }
    }
    return if best == wom { 1 } else { 2 }
  }
  if best == doy_stamp {
    3
  } else {
    4
  }
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
fn date_floor_div64(value : Int64, divisor : Int64) -> Int64 {
  let quotient = value / divisor
  let remainder = value % divisor
  if value < 0L && remainder != 0L {
    quotient - 1L
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
fn days_from_date(year : Int32, month : Int32, day : Int32) -> Int64 {
  if year < 1582 || (year == 1582 && (month < 10 || (month == 10 && day <= 4))) {
    let a = (14 - month) / 12
    let y = (year + 4800 - a).to_int64()
    let m = (month + 12 * a - 3).to_int64()
    return day.to_int64() +
      (153L * m + 2L) / 5L +
      365L * y +
      date_floor_div64(y, 4L) -
      32083L -
      2440588L
  }
  let y = (if month <= 2 { year - 1 } else { year }).to_int64()
  let era = y / 400L
  let yoe = y - era * 400L
  let mp = (month + (if month > 2 { -3 } else { 9 })).to_int64()
  let doy = (153L * mp + 2L) / 5L + day.to_int64() - 1L
  era * 146097L + yoe * 365L + yoe / 4L - yoe / 100L + doy - 719468L
}

///|
fn date_from_days(days : Int64) -> (Int32, Int32, Int32) {
  if days < -141427L {
    // Keep the inverse Julian conversion in 64-bit intermediates: the
    // GregorianCalendar-compatible Int32 day envelope spans several million
    // BC years, where multiplying the epoch day by four overflows Int32.
    let c = days + 2440588L + 32082L
    let d = date_floor_div64(4L * c + 3L, 1461L)
    let e = c - date_floor_div64(1461L * d, 4L)
    let m = date_floor_div64(5L * e + 2L, 153L)
    return (
      (d - 4800L + date_floor_div64(m, 10L)).to_int(),
      (m + 3L - 12L * date_floor_div64(m, 10L)).to_int(),
      (e - date_floor_div64(153L * m + 2L, 5L) + 1L).to_int(),
    )
  }
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = doy - (153L * mp + 2L) / 5L + 1L
  let month = mp + (if mp < 10L { 3L } else { -9L })
  (
    (yoe + era * 400L + (if month <= 2L { 1L } else { 0L })).to_int(),
    month.to_int(),
    day.to_int(),
  )
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
fn weekday_index(days : Int64) -> Int32 {
  (((days + 4L) % 7L + 7L) % 7L).to_int()
}

///|
fn first_week_start(year : Int32) -> Int64 {
  let jan1 = days_from_date(year, 1, 1)
  jan1 - weekday_index(jan1).to_int64()
}

///|
fn week_year_and_number(days : Int64) -> (Int32, Int32) {
  let (calendar_year, _, _) = date_from_days(days)
  let start = first_week_start(calendar_year)
  if days < start {
    let week_year = calendar_year - 1
    (week_year, ((days - first_week_start(week_year)) / 7L + 1L).to_int())
  } else {
    let next = first_week_start(calendar_year + 1)
    if days >= next {
      (calendar_year + 1, ((days - next) / 7L + 1L).to_int())
    } else {
      (calendar_year, ((days - start) / 7L + 1L).to_int())
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
// Java 17 DecimalFormat accepts Character.digit(char, 10), not only ASCII.
// Every BMP decimal digit set consists of ten consecutive code units. Java's
// char-based parser rejects supplementary-plane digits (surrogate pairs).
fn date_decimal_digit(code : UInt16) -> Int32 {
  let code = code.to_int()
  for
    zero in [
      0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6,
      0x0C66, 0x0CE6, 0x0D66, 0x0DE6, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0,
      0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620,
      0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10,
    ] {
    if code >= zero && code < zero + 10 {
      return code - zero
    }
  }
  -1
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
    let c = date_decimal_digit(text[i])
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
  let days = (now / 86400000.0).to_int64()
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
    @double.floor(century_start / 86400000.0).to_int64(),
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
  let mut week_of_month_stamp = -1
  let mut weekday_ordinal = 0
  let mut has_weekday_ordinal = false
  let mut month = 1
  let mut day = 1
  let mut day_of_year = 0
  let mut has_day_of_year = false
  let mut has_month = false
  let mut month_stamp = -1
  let mut has_day = false
  let mut weekday = -1
  let mut weekday_stamp = -1
  let mut day_stamp = -1
  let mut week_stamp = -1
  let mut weekday_ordinal_stamp = -1
  let mut doy_stamp = -1
  let mut hour = 0
  let mut hour24 : Int32? = None
  let mut hour24_valid = true
  let mut hour12 : Int32? = None
  let mut hour12_valid = true
  let mut ampm = -1
  let mut minute = 0
  let mut second = 0
  let mut millis = 0
  let mut zone : DateZone = { id: "UTC", raw: None, dst: None, }
  let mut before_common_era = false
  let mut has_era = false
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
          weekday_stamp = index
          pos += width
        } else if (c == 'M' || c == 'L') && n >= 3 {
          let (found, width) = date_text_name(text, pos, true)
          if found < 0 {
            raise Invalid("invalid English month name")
          }
          month = found + 1
          has_month = true
          month_stamp = index
          pos += width
        } else if c == 'G' {
          has_era = true
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
          let negative = pos < text.length() && text[pos] == 45
          let number_start = pos
          if negative {
            pos += 1
          }
          // An adjacent field width includes a possible minus sign, as Java's
          // obeyCount parsing limits the complete numeric token.
          let mut width = n - (if negative { 1 } else { 0 })
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
                  date_decimal_digit(text[pos + width]) >= 0 {
              width += 1
            }
            if width == 0 {
              raise Invalid("date field requires digits")
            }
          }
          let v = date_digits(text, pos, width)
          if negative && v != 0 {
            raise Invalid("negative date field")
          }
          pos += width
          let numeric_width = pos - number_start
          match c {
            'Y' => {
              ambiguous_week_year = n <= 2 && numeric_width == 2 && !negative
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
              week_of_month_stamp = index
            }
            'F' => {
              weekday_ordinal = v
              has_weekday_ordinal = true
              weekday_ordinal_stamp = index
            }
            'y' => {
              has_calendar_year = true
              ambiguous_year = n <= 2 && numeric_width == 2 && !negative
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
              month_stamp = index
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
              weekday_stamp = index
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
                // CalendarBuilder keeps the last H/k stamp; an earlier
                // out-of-range value may be superseded before strict resolve.
                hour24_valid = if c == 'H' {
                  v <= 23
                } else {
                  v >= 1 && v <= 24
                }
                hour24 = Some(if c == 'k' && v == 24 { 0 } else { v })
              } else {
                hour12_valid = if c == 'h' {
                  v >= 1 && v <= 12
                } else {
                  v <= 11
                }
                hour12 = Some(v % 12)
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
  if year < 1 || year > 292278995 || week_year < 1 || week_year > 292278995 {
    raise Invalid("year outside Java Date long-millisecond calendar envelope")
  }
  // CalendarBuilder resolves H/k as the 24-hour field group even when an
  // AM/PM or h/K token follows it. The 12-hour fields remain consistency
  // constraints, not a competing value that can override an explicit H/k.
  hour = hour24.unwrap_or(
    hour12.unwrap_or(0) + (if ampm < 0 { 0 } else { ampm }) * 12,
  )
  if (hour24 is Some(_) && !hour24_valid) ||
    (hour12 is Some(_) && !hour12_valid) {
    raise Invalid("invalid clock field value")
  }
  // Every explicitly supplied clock field must agree with the resolved time.
  if (hour24 is Some(value) && value != hour) ||
    (hour12 is Some(value) && value != hour % 12) ||
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
      first_week_start(effective_week_year) +
      (week_number - 1).to_int64() * 7L +
      weekday.to_int64()
    } else if has_day_of_year {
      days_from_date(effective_year, 1, 1) + (day_of_year - 1).to_int64()
    } else if has_week_of_month {
      let first = days_from_date(effective_year, month, 1)
      first -
      weekday_index(first).to_int64() +
      (week_of_month - 1).to_int64() * 7L +
      weekday.to_int64()
    } else if has_weekday_ordinal {
      let first = days_from_date(effective_year, month, 1)
      first +
      ((weekday - weekday_index(first) + 7) % 7).to_int64() +
      ((if has_weekday_ordinal { weekday_ordinal } else { 1 }) - 1).to_int64() *
      7L
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
  // GregorianCalendar cannot resolve a BC calendar date as week-year 1 AD.
  // Without an explicit BC era, Y=1 plus D must not silently borrow year 0.
  if !before_common_era &&
    !has_calendar_year &&
    !has_month &&
    !has_week_number &&
    has_week_year &&
    has_day_of_year &&
    week_year == 1 {
    raise Invalid("week-year 1 day-of-year crosses the era boundary")
  }
  if has_week_year &&
    !has_calendar_year &&
    !has_week_number &&
    has_day_of_year &&
    week_year == 1582 {
    raise Invalid(
      "week-year/day-of-year combination is unresolved at Gregorian cutover",
    )
  }
  // CalendarBuilder keeps Y as a week-year, but when a later weekday-group
  // selector competes with D it resolves D in the adjacent calendar year
  // whose resulting week-year matches Y. Y+D alone is not a complete date.
  if has_calendar_year &&
    has_week_year &&
    has_day_of_year &&
    week_year_stamp > year_stamp {
    raise Invalid("calendar year, week-year, and day-of-year conflict")
  }
  if has_week_year &&
    has_day_of_year &&
    !has_week_number &&
    weekday_stamp < 0 &&
    (has_weekday_ordinal || has_week_of_month) {
    raise Invalid("month-week field needs a weekday with week-year/day-of-year")
  }
  if !has_calendar_year && has_week_year && has_day_of_year && !has_week_number {
    let later_weekday_selector = day_stamp > doy_stamp ||
      weekday_stamp > doy_stamp ||
      weekday_ordinal_stamp > doy_stamp ||
      week_of_month_stamp > doy_stamp
    if !later_weekday_selector {
      raise Invalid("week-year and day-of-year do not select a complete date")
    }
    let this_year_days = days_from_date(week_year, 1, 1) +
      (day_of_year - 1).to_int64()
    let prior_year_days = days_from_date(week_year - 1, 1, 1) +
      (day_of_year - 1).to_int64()
    let selected_days = if week_year_and_number(this_year_days).0 == week_year {
      year = week_year
      this_year_days
    } else if week_year > 1 &&
      week_year_and_number(prior_year_days).0 == week_year {
      year = week_year - 1
      prior_year_days
    } else {
      raise Invalid("day-of-year falls outside the selected week-year")
    }
    if week_year_and_number(selected_days).1 != 1 {
      raise Invalid("week-year/day-of-year does not resolve within week one")
    }
    if weekday_stamp >= 0 && weekday_index(selected_days) != weekday {
      raise Invalid("weekday conflicts with selected day-of-year")
    }
  }

  // CalendarBuilder treats Y as the week-year family, which takes precedence
  // over day-of-month and weekday-ordinal fields even if those tokens occur
  // later in the pattern. Calendar year and day-of-year remain competing
  // calendar-date fields and retain stamp ordering.
  if has_week_year &&
    has_week_number &&
    has_day_of_year &&
    week_year_stamp > doy_stamp &&
    (!has_calendar_year || week_year_stamp > year_stamp) {
    let selected_week = if has_week_number { week_number } else { 1 }
    let selected_weekday = if weekday < 0 { 0 } else { weekday }
    let selected_days = first_week_start(week_year) +
      (selected_week - 1).to_int64() * 7L +
      selected_weekday.to_int64()
    let (selected_calendar_year, _, _) = date_from_days(selected_days)
    let selected_day_of_year = selected_days -
      days_from_date(selected_calendar_year, 1, 1) +
      1L
    if selected_day_of_year != day_of_year.to_int64() {
      raise Invalid("day-of-year conflicts with week-year fields")
    }
  }
  let calendar_choice = [year_stamp, doy_stamp].fold(init=-1, fn(best, next) {
    if next > best {
      next
    } else {
      best
    }
  })
  let use_week_year = has_week_year &&
    has_week_number &&
    week_year_stamp > calendar_choice
  if use_week_year {
    if week_number < 1 || week_number > 53 {
      raise Invalid("week date outside supported range")
    }
    let selected_year = if week_year_stamp >= 0 { week_year } else { year }
    let dow = if weekday < 0 { 0 } else { weekday }
    let actual_days = first_week_start(selected_year) +
      (week_number - 1).to_int64() * 7L +
      dow.to_int64()
    let (actual_year, actual_month, actual_day) = date_from_days(actual_days)
    let (wy, wn) = week_year_and_number(actual_days)
    let resolved = days_from_date(actual_year, actual_month, actual_day)
    let first = days_from_date(actual_year, actual_month, 1)
    let week_of_month_value = (
        resolved - (first - weekday_index(first).to_int64())
      ) /
      7L +
      1L
    let day_of_year_value = resolved - days_from_date(actual_year, 1, 1) + 1L
    if wy != selected_year ||
      wn != week_number ||
      (selected_year == 1 && actual_year == 0) ||
      (
        has_weekday_ordinal &&
        (resolved - first) / 7L + 1L != weekday_ordinal.to_int64()
      ) ||
      (has_week_of_month && week_of_month_value != week_of_month.to_int64()) ||
      (has_day_of_year && day_of_year_value != day_of_year.to_int64()) {
      raise Invalid("invalid or conflicting week-of-year date")
    }
    year = actual_year
    month = actual_month
    day = actual_day
  } else if has_week_year && week_year_stamp > calendar_choice {
    // A week year without w resolves within week one. A supplied weekday
    // selects the corresponding day; W/F cannot resolve without a calendar
    // month in strict GregorianCalendar parsing.
    let wy = if week_year_stamp > year_stamp { week_year } else { year }
    let wn = if week_stamp >= 0 { week_number } else { 1 }
    let dow = if weekday < 0 { 0 } else { weekday }
    let actual_days = first_week_start(wy) +
      (wn - 1).to_int64() * 7L +
      dow.to_int64()
    let (ty, tm, td) = date_from_days(actual_days)
    if wy == 1 && ty == 0 {
      raise Invalid("week-year date falls before the AD era")
    }
    let resolved = days_from_date(ty, tm, td)
    let first = days_from_date(ty, tm, 1)
    let resolved_day_of_year = resolved - days_from_date(ty, 1, 1) + 1L
    if has_day_of_year && resolved_day_of_year != day_of_year.to_int64() {
      raise Invalid("day-of-year conflicts with selected week-year")
    }
    if (
        has_weekday_ordinal &&
        (resolved - first) / 7L + 1L != weekday_ordinal.to_int64()
      ) ||
      (
        has_week_of_month &&
        (resolved - (first - weekday_index(first).to_int64())) / 7L + 1L !=
        week_of_month.to_int64()
      ) {
      raise Invalid("week fields conflict with week-year date")
    }
    year = ty
    month = tm
    day = td
  } else {
    // Preserve requested calendar values so non-lenient Weka semantics can
    // reject fields that normalize during GregorianCalendar.computeTime().
    let requested_year = year
    let requested_month = month
    let requested_day = day
    // Missing fields follow Calendar.clear(): 1970, January and midnight.
    // A supplied weekday without a day chooses its first occurrence in month;
    // W/F/w choose Sunday if the weekday itself was omitted.
    let selected = date_calendar_selection(
      month_stamp, day_stamp, week_of_month_stamp, weekday_ordinal_stamp, doy_stamp,
      week_stamp, weekday_stamp,
    )
    let week_year_day_of_year = has_week_year &&
      has_day_of_year &&
      !has_week_number
    if selected == 3 || week_year_day_of_year {
      let target = days_from_date(year, 1, 1) + (day_of_year - 1).to_int64()
      let (ty, tm, td) = date_from_days(target)
      let day_of_month_wins = has_day && doy_stamp < day_stamp
      if ty != year ||
        (has_month && tm != month) ||
        (has_day && td != day) ||
        (!has_month && day_of_month_wins && tm != 1) {
        raise Invalid("day-of-year conflicts with calendar date")
      }
      if weekday_stamp >= 0 && weekday_index(target) != weekday {
        raise Invalid("weekday conflicts with day-of-year")
      }
      month = tm
      day = td
    } else if !has_day || selected != 0 {
      let dow = if weekday < 0 { 0 } else { weekday }
      let first = days_from_date(year, month, 1)
      let target = if selected == 1 {
        first -
        weekday_index(first).to_int64() +
        (week_of_month - 1).to_int64() * 7L +
        dow.to_int64()
      } else if selected == 2 {
        let ordinal = if has_weekday_ordinal { weekday_ordinal } else { 1 }
        first +
        ((dow - weekday_index(first) + 7) % 7).to_int64() +
        (ordinal - 1).to_int64() * 7L
      } else if selected == 4 {
        first_week_start(year) +
        (week_number - 1).to_int64() * 7L +
        dow.to_int64()
      } else {
        first
      }
      if has_month && year == 1582 && month == 10 && !has_week_number {
        let cutover_first = days_from_date(1582, 10, 1)
        let civil_offset = target - cutover_first
        if civil_offset >= 4L && civil_offset <= 13L {
          raise Invalid("weekday selector lands in the Gregorian cutover gap")
        }
      }
      let (ty, tm, td) = date_from_days(target)
      if (
          has_calendar_year && ty != year && !(!has_era && year == 1 && ty == 0)
        ) ||
        (has_month && selected != 4 && tm != month) {
        raise Invalid("week fields conflict with calendar date")
      }
      year = ty
      month = tm
      day = td
    }
    if (
        has_calendar_year &&
        year != requested_year &&
        !(!has_era && requested_year == 1 && year == 0)
      ) ||
      (has_month && month != requested_month) ||
      (has_day && day != requested_day) {
      raise Invalid("explicit calendar field changed during strict resolution")
    }
    let resolved = days_from_date(year, month, day)
    let resolved_doy = resolved - days_from_date(year, 1, 1) + 1L
    if has_day_of_year && resolved_doy != day_of_year.to_int64() {
      raise Invalid("day-of-year conflicts with selected calendar date")
    }
    let first = days_from_date(year, month, 1)
    if (
        has_week_number &&
        (week_number < 1 || week_year_and_number(resolved).1 != week_number)
      ) ||
      (
        has_week_of_month &&
        (
          week_of_month < 1 ||
          (resolved - (first - weekday_index(first).to_int64())) / 7L + 1L !=
          week_of_month.to_int64()
        )
      ) ||
      (
        has_weekday_ordinal &&
        (
          weekday_ordinal < 1 ||
          (resolved - first) / 7L + 1L != weekday_ordinal.to_int64()
        )
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
    !has_week_number &&
    !has_week_year &&
    (has_week_of_month || has_weekday_ordinal) &&
    (!has_day || weekday >= 0) &&
    (
      !has_day_of_year ||
      doy_stamp < (if has_week_of_month { week_of_month_stamp } else { -1 }) ||
      doy_stamp < weekday_ordinal_stamp
    ) {
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
  if value < -9223372036854775808.0 || value > 9223372036854775808.0 {
    raise Invalid("date exceeds Java Date long-millisecond range")
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
  if !finite(value) ||
    value < -9223372036854775808.0 ||
    value > 9223372036854775808.0 {
    raise Invalid("date exceeds Java Date long-millisecond range")
  }
  // Java casts a double at +2^63 to Long.MAX_VALUE (saturating). The
  // nearest representable Double cannot encode Long.MAX_VALUE itself.
  let positive_long_edge = value == 9223372036854775808.0
  let mut days = if positive_long_edge {
    9223372036854775807L / 86400000L
  } else {
    (value / 86400000.0).to_int64()
  }
  if !positive_long_edge && days.to_double() * 86400000.0 > value {
    days -= 1L
  }
  let rem = if positive_long_edge {
    (9223372036854775807L % 86400000L).to_double()
  } else {
    value - days.to_double() * 86400000.0
  }
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
                ((days - (first - weekday_index(first).to_int64())) / 7L + 1L).to_int()
              }
              'F' => {
                let first = days_from_date(y, m, 1)
                let first_matching = first +
                  (weekday_index(days) - weekday_index(first) + 7).to_int64() %
                  7L
                ((days - first_matching) / 7L + 1L).to_int()
              }
              'M' | 'L' => m
              'd' => d
              'D' => (days - days_from_date(y, 1, 1) + 1L).to_int()
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

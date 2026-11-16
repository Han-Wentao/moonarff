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
  let seen : Map[Char, Bool] = Map([])
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
      let supported = match c {
        'y' => n == 4
        'M' => n >= 1 && n <= 4
        'd' | 'H' | 'h' | 'K' | 'k' | 'm' | 's' => n == 1 || n == 2
        'D' => n >= 1 && n <= 3
        'E' => n >= 1 && n <= 4
        'a' => n == 1
        'S' => n >= 1 && n <= 3
        'Z' => n == 1
        'X' => n >= 1 && n <= 3
        _ => false
      }
      if !supported {
        raise Unsupported(
          "date field outside deterministic GregorianCalendar profile: " +
          c.to_string(),
        )
      }
      if seen.contains(c) ||
        (c == 'Z' && seen.contains('X')) ||
        (c == 'X' && seen.contains('Z')) {
        raise Invalid("duplicate date field")
      }
      if c == 'H' || c == 'h' || c == 'K' || c == 'k' {
        for clock in ['H', 'h', 'K', 'k'] {
          if seen.contains(clock) {
            raise Invalid("multiple hour fields in date pattern")
          }
        }
      }
      seen[c] = true
      parts.push(Field(c, n))
    } else {
      parts.push(Literal(c.to_string()))
      i += 1
    }
  }
  parts
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
    return day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083 - 2440588
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
    let d = (4 * c + 3) / 1461
    let e = c - 1461 * d / 4
    let m = (5 * e + 2) / 153
    return (d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
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
    value = value * 10 + c
  }
  value
}

///|
/// Parse deterministic English-locale Java date patterns; values are UTC epoch milliseconds.
pub fn parse_date(text : String, pattern : String) -> Double raise ArffError {
  let parts = date_parts(pattern)
  let mut pos = 0
  let mut year = 1970
  let mut month = 1
  let mut day = 1
  let mut day_of_year = 0
  let mut has_day_of_year = false
  let mut has_month = false
  let mut has_day = false
  let mut weekday = -1
  let mut hour = 0
  let mut hour_kind = 'H'
  let mut ampm = -1
  let mut minute = 0
  let mut second = 0
  let mut millis = 0
  let mut zone = 0
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
        } else if c == 'M' && n >= 3 {
          let (found, width) = date_text_name(text, pos, true)
          if found < 0 {
            raise Invalid("invalid English month name")
          }
          month = found + 1
          has_month = true
          pos += width
        } else if c == 'a' {
          let names = ["AM", "PM"]
          let (found, width) = date_name_index(text, pos, names)
          if found < 0 {
            raise Invalid("expected AM or PM")
          }
          ampm = found
          pos += width
        } else if c == 'X' || c == 'Z' {
          if pos < text.length() && text[pos] == 90 && c == 'X' {
            pos += 1
            continue
          }
          if pos >= text.length() || (text[pos] != 43 && text[pos] != 45) {
            raise Invalid("date timezone offset required")
          }
          let sign = if text[pos] == 45 { -1 } else { 1 }
          pos += 1
          let zh = date_digits(text, pos, 2)
          pos += 2
          let mut zm = 0
          if c == 'Z' || n >= 2 {
            if c == 'X' && n == 3 {
              if pos >= text.length() || text[pos] != 58 {
                raise Invalid("timezone colon required")
              }
              pos += 1
            }
            zm = date_digits(text, pos, 2)
            pos += 2
          }
          if zh > 23 || zm > 59 {
            raise Invalid("invalid date timezone offset")
          }
          zone = sign * (zh * 60 + zm)
        } else {
          let mut width = n
          let adjacent = if index + 1 < parts.length() {
            match parts[index + 1] {
              Field(next, count) =>
                next != 'X' &&
                next != 'Z' &&
                next != 'E' &&
                next != 'a' &&
                !(next == 'M' && count >= 3)
              _ => false
            }
          } else {
            false
          }
          if !adjacent {
            width = 0
            let cap = if c == 'y' {
              4
            } else if c == 'S' || c == 'D' {
              3
            } else {
              2
            }
            while width < cap &&
                  pos + width < text.length() &&
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
            'y' => year = v
            'M' => {
              month = v
              has_month = true
            }
            'd' => {
              day = v
              has_day = true
            }
            'D' => {
              day_of_year = v
              has_day_of_year = true
            }
            'E' => ()
            'H' | 'h' | 'K' | 'k' => {
              hour = v
              hour_kind = c
            }
            'm' => minute = v
            's' => second = v
            'S' => millis = v
            _ => ()
          }
        }
    }
  }
  if pos != text.length() {
    raise Invalid("date has trailing data")
  }
  if hour_kind == 'h' || hour_kind == 'K' {
    if ampm < 0 {
      raise Invalid("12-hour clock requires AM/PM")
    }
    if (hour_kind == 'h' && (hour < 1 || hour > 12)) ||
      (hour_kind == 'K' && hour > 11) {
      raise Invalid("invalid 12-hour clock value")
    }
    hour = hour % 12 + ampm * 12
  } else if ampm >= 0 {
    raise Invalid("AM/PM requires a 12-hour clock")
  } else if hour_kind == 'k' {
    if hour < 1 || hour > 24 {
      raise Invalid("invalid 1..24 hour")
    }
    if hour == 24 {
      hour = 0
    }
  }
  if year < 1 || year > 9999 {
    raise Invalid("year outside supported range")
  }
  if has_day_of_year {
    let actual_days = days_from_date(year, 1, 1) + day_of_year - 1
    let (actual_year, actual_month, actual_day) = date_from_days(actual_days)
    if actual_year != year ||
      (has_month && actual_month != month) ||
      (has_day && actual_day != day) {
      raise Invalid("day-of-year conflicts with calendar date")
    }
    month = actual_month
    day = actual_day
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
  let days = days_from_date(year, month, day)
  if weekday >= 0 && weekday_index(days) != weekday {
    raise Invalid("weekday does not match calendar date")
  }
  let value = days.to_double() * 86400000.0 +
    (hour * 3600000 + minute * 60000 + second * 1000 + millis - zone * 60000).to_double()
  if value < -62135769600000.0 || value > 253402300799999.0 {
    raise Invalid("date outside supported years 0001..9999")
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
pub fn format_date(value : Double, pattern : String) -> String raise ArffError {
  if !finite(value) || value < -62135769600000.0 || value > 253402300799999.0 {
    raise Invalid("date outside supported years 0001..9999")
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
  for part in date_parts(pattern) {
    match part {
      Literal(s) => out.write_string(s)
      Field(c, n) =>
        match c {
          'X' => out.write_string("Z")
          'Z' => out.write_string("+0000")
          'E' => out.write_string(weekday_names(n <= 3)[weekday_index(days)])
          'M' if n >= 3 => out.write_string(month_names(n == 3)[m - 1])
          'a' => out.write_string(if rest / 3600000 < 12 { "AM" } else { "PM" })
          _ => {
            let hour = rest / 3600000
            let v = match c {
              'y' => y
              'M' => m
              'd' => d
              'D' => days - days_from_date(y, 1, 1) + 1
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
  let text = out.to_string()
  // Reject lossy serialization: a date-only format cannot silently drop time, nor S truncate precision.
  if parse_date(text, pattern) != value {
    raise Invalid("date pattern would lose timestamp precision")
  }
  text
}

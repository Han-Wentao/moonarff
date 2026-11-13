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
        'M' | 'd' | 'H' | 'm' | 's' => n == 1 || n == 2
        'S' => n >= 1 && n <= 3
        'Z' => n == 1
        'X' => n >= 1 && n <= 3
        _ => false
      }
      if !supported {
        raise Unsupported(
          "date field outside deterministic numeric GregorianCalendar profile: " +
          c.to_string(),
        )
      }
      if seen.contains(c) ||
        (c == 'Z' && seen.contains('X')) ||
        (c == 'X' && seen.contains('Z')) {
        raise Invalid("duplicate date field")
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
/// Strict Java GregorianCalendar cutover dates, with fixed numeric offsets. Missing fields use 1970-01-01.
pub fn parse_date(text : String, pattern : String) -> Double raise ArffError {
  let parts = date_parts(pattern)
  let mut pos = 0
  let mut year = 1970
  let mut month = 1
  let mut day = 1
  let mut hour = 0
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
        if c == 'X' || c == 'Z' {
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
          // Java numeric fields use count as minimum output width. An adjacent
          // numeric field fixes input width; a delimiter allows natural digits.
          let adjacent = if index + 1 < parts.length() {
            match parts[index + 1] {
              Field(next, _) => next != 'X' && next != 'Z'
              _ => false
            }
          } else {
            false
          }
          if !adjacent {
            width = 0
            let cap = if c == 'y' { 4 } else if c == 'S' { 3 } else { 2 }
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
            'M' => month = v
            'd' => day = v
            'H' => hour = v
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
  if year < 1 ||
    year > 9999 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > month_days(year, month) ||
    (year == 1582 && month == 10 && day >= 5 && day <= 14) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 {
    raise Invalid("invalid Gregorian date/time")
  }
  let value = days_from_date(year, month, day).to_double() * 86400000.0 +
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
          _ => {
            let v = match c {
              'y' => y
              'M' => m
              'd' => d
              'H' => rest / 3600000
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

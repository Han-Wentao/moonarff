///|
test "Weka timezone names and numeric offsets share z and Z parsing" {
  for
    (name, offset) in [
      ("PDT", -420),
      ("PST", -480),
      ("Eastern Standard Time", -300),
      ("India Standard Time", 330),
      ("UTC", 0),
      ("GMT+8:00", 480),
      ("+0800", 480),
    ] {
    for field in ["z", "Z"] {
      assert_eq(
        parse_date("1970-01-01 " + name, "yyyy-MM-dd " + field),
        -offset.to_double() * 60000.0,
      )
    }
  }
}

///|
test "Weka parse position accepts suffix and numeric leading spaces" {
  assert_eq(parse_date("2024-02-29suffix", "yyyy-MM-dd"), 1709164800000.0)
  assert_eq(parse_date(" 2024- 2- 29", "yyyy-MM-dd"), 1709164800000.0)
}

///|
test "Weka partial calendar fields and consistent combinations" {
  for
    (pattern, text, expected) in [
      ("w", "2", 259200000.0),
      ("E", "Mon", 345600000.0),
      ("u", "1", 345600000.0),
      ("W", "2", 259200000.0),
      ("F", "2", 864000000.0),
      ("yyyy-w-u", "2024-2-1", 1704672000000.0),
      ("yyyy-MM-dd-w-u", "2024-01-08-2-1", 1704672000000.0),
      ("yyyy-w", "2024-2", 1704585600000.0),
      ("yyyy-MM-W", "2024-02-2", 1707004800000.0),
      ("yyyy-MM-E", "2024-02-Thu", 1706745600000.0),
    ] {
    assert_eq(parse_date(text, pattern), expected)
  }
}

///|
test "zone-only date precision can be preserved by canonical offset" {
  for
    (pattern, text) in [
      ("yyyy-MM-dd z", "2024-01-01 GMT"),
      ("yyyy-MM-dd Z", "2024-07-01 +0800"),
      ("yyyy-MM-dd XXX XXX", "1970-01-01 Z +08:00"),
    ] {
    let value = parse_date(text, pattern)
    assert_eq(parse_date(format_date(value, pattern), pattern), value)
  }
}

///|
test "exact millisecond boundaries are symmetric" {
  for value in [-9007199254740991.0, 9007199254740991.0] {
    let pattern = "yyyy-MM-dd G HH:mm:ss.SSS"
    assert_eq(parse_date(format_date(value, pattern), pattern), value)
  }
}

///|
test "Weka aliases use their standard raw offsets instead of daylight offsets" {
  assert_eq(parse_date("2024-01-01 WET", "yyyy-MM-dd z"), 1704067200000.0)
  assert_eq(
    parse_date("2024-07-01 SGT", "yyyy-MM-dd z"),
    1719792000000.0 - 8.0 * 3600000.0,
  )
}

///|
test "Weka timezone aliases preserve exact JDK Unicode and acceptance" {
  assert_eq(
    parse_date("2024-01-01 Dumont-d’Urville Time", "yyyy-MM-dd z"),
    1704031200000.0,
  )
  let ascii_dumont_rejected = try {
    ignore(parse_date("2024-01-01 Dumont-d'Urville Time", "yyyy-MM-dd z"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(ascii_dumont_rejected)
  let unsupported_reunion_alias_rejected = try {
    ignore(parse_date("2024-01-01 Reunion Time", "yyyy-MM-dd z"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(unsupported_reunion_alias_rejected)
}

///|
test "Weka first calendar week may begin in the prior era" {
  assert_eq(parse_date("1-1-1", "yyyy-w-u"), -62136201600000.0)
  let week_year_rejected = try {
    ignore(parse_date("1-1-1", "YYYY-w-u"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(week_year_rejected)
}

///|
test "Weka strict timezone normalization rechecks supplied fields" {
  // Independent Attribute.parseDate results, Java 17.0.2 / Weka 3.8.6.
  for
    (pattern, text, expected) in [
      ("yyyy-MM-dd z", "1940-07-01 Argentina Standard Time", -931032000000.0),
      ("yyyy-MM-dd z", "2024-03-10 Cuba Standard Time", 1710046800000.0),
      (
        "yyyy-MM-dd HH:mm:ss.SSS z", "1900-08-20 12:00:00.000 HADT", -2188948402000.0,
      ),
      (
        "yyyy-MM-dd HH:mm z", "2024-03-10 02:30 Pacific Standard Time", 1710066600000.0,
      ),
      (
        "yyyy-MM-dd HH:mm z", "2024-03-10 02:30 Pacific Daylight Time", 1710063000000.0,
      ),
      (
        "yyyy-MM-dd HH:mm z", "1940-07-01 00:00 Argentina Standard Time", -931032000000.0,
      ),
      (
        "yyyy-MM-dd HH:mm z", "2024-03-10 00:00 Cuba Standard Time", 1710046800000.0,
      ),
    ] {
    assert_eq(parse_date(text, pattern), expected)
  }
  for
    (pattern, text) in [
      (
        "yyyy-MM-dd HH:mm:ss.SSS z", "1900-08-20 12:00:00.000 Alaska Daylight Time",
      ),
      (
        "yyyy-MM-dd HH:mm:ss.SSS z", "1900-01-01 12:00:00.000 New Zealand Daylight Time",
      ),
      ("yyyy-MM-dd z", "2011-12-30 Apia Standard Time"),
      ("yyyy-MM-dd z", "2011-12-30 Apia Daylight Time"),
    ] {
    let rejected = try {
      ignore(parse_date(text, pattern))
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

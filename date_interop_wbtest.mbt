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
test "exact millisecond boundaries match Weka formatting and parsing" {
  let pattern = "yyyy-MM-dd G HH:mm:ss.SSS"
  for
    (value, expected) in [
      (-9007199254740992.0, "283452-01-16 BC 15:00:59.008"),
      (-9007199254740991.0, "283452-01-16 BC 15:00:59.009"),
      (9007199254740991.0, "287396-10-12 AD 08:59:00.991"),
      (9007199254740992.0, "287396-10-12 AD 08:59:00.992"),
    ] {
    assert_eq(format_date(value, pattern), expected)
    assert_eq(parse_date(expected, pattern), value)
  }
}

///|
test "Weka Date formatting saturates Java long extrema exactly" {
  let pattern = "yyyy-MM-dd G HH:mm:ss.SSS"
  for
    (value, expected) in [
      (-9223372036854775808.0, "292269055-12-02 BC 16:47:04.192"),
      (-9223372036854774784.0, "292269055-12-02 BC 16:47:05.216"),
      (9223372036854774784.0, "292278994-08-17 AD 07:12:54.784"),
      (9223372036854775808.0, "292278994-08-17 AD 07:12:55.807"),
    ] {
    assert_eq(format_date(value, pattern), expected)
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

///|
test "Weka dates retain the declared 5000000-year calendar envelope" {
  for
    text in [
      "285000-01-01 BC", "285000-12-31 BC", "285000-01-01 AD", "285000-12-31 AD",
      "299999-01-01 BC", "299999-12-31 BC", "300000-01-01 BC", "300000-12-31 BC",
      "300000-01-01 AD", "300000-12-31 AD", "1000000-01-01 BC", "1000000-01-01 AD",
      "5000000-01-01 BC", "5000000-01-01 AD",
    ] {
    let value = parse_date(text, "yyyy-MM-dd G")
    assert_eq(
      parse_date(format_date(value, "yyyy-MM-dd G"), "yyyy-MM-dd G"),
      value,
    )
  }
}

///|

///|
test "Weka day-of-year resolves the Gregorian cutover date" {
  assert_eq(
    parse_date("Oct/AD.1-Z.1582.278", "MMM/G.W-XXX.y.DDD"),
    -12219292800000.0,
  )
}

///|
test "Weka day-of-year and day-of-month field precedence" {
  // Java/Weka CalendarBuilder honors pattern stamp order: a later D can
  // resolve the date after an earlier d, while a later d must agree with the
  // default or explicit month.
  assert_eq(parse_date("2024 29 060", "yyyy d D"), 1709164800000.0)
  assert_eq(parse_date("2024 2 29 060", "yyyy M d D"), 1709164800000.0)
  let conflict = try {
    ignore(parse_date("2024 060 29", "yyyy D d"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(conflict)
}

///|
test "Weka day-of-year resolves with the sole week-year fallback" {
  // Java 17 / Weka 3.8.6 Attribute.parseDate; D is the later date selector.
  assert_eq(parse_date("00.2038-1-5.Z.1", "mm.Y-D-u.XX.F"), 2145916800000.0)
}

///|
test "Weka week-year day-of-year resolves with month and weekday selectors" {
  assert_eq(
    parse_date("Fri.1 +0000/2038:JanFriday", "E.D Z/Y:MMMEEEE"),
    2145916800000.0,
  )
}

///|
test "Weka rejects week-year day-of-year with conflicting weekday" {
  // Java 17 / Weka 3.8.6 rejects this BCE-boundary case: the matching
  // prior calendar year would cross from week-year 1 AD into the BC era.
  let rejected = try {
    ignore(parse_date("00.1-3-1.Z.1", "mm.Y-D-u.XX.F"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "Weka week-year and day-of-year need a later weekday selector" {
  let rejected = try {
    ignore(parse_date("2038-1-0:00", "Y-D-S:mm"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(parse_date("59.1970-365-3.Z.5", "mm.Y-D-u.XX.F"), -82860000.0)
  assert_eq(parse_date("5 1:2038.1", "u D:Y.d"), 2145916800000.0)
}

///|
test "Weka rejects week-year and day-of-year during cutover year" {
  let rejected = try {
    ignore(parse_date("00.1582-278-5.Z.1", "mm.Y-D-u.XX.F"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "Weka calendar selectors respect the 1582 cutover gap" {
  let gap_rejected = try {
    ignore(parse_date("Fri/10-1582", "E/L-y"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(gap_rejected)
}

///|
test "Weka year-family selection follows parsed field stamps" {
  assert_eq(parse_date("2024 2024 060", "Y y D"), 1709164800000.0)
  assert_eq(parse_date("2024 060 2024", "Y D y"), 1709164800000.0)
  assert_eq(parse_date("060 2024 2024", "D Y y"), 1709164800000.0)
  let week_year_conflict = try {
    ignore(parse_date("2024 2024 060", "y Y D"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(week_year_conflict)
  let day_year_conflict = try {
    ignore(parse_date("2024 060 4", "Y D u"))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(day_year_conflict)
}

///|
test "Weka strict calendar selection honors week fields and explicit era" {
  assert_eq(parse_date("5x01:Z", "W'x'ww:XX"), -345600000.0)
  assert_eq(parse_date("5923/5:1", "mmH/W:w"), -259260000.0)
  let era_conflict = try {
    ignore(parse_date("01x196923 AD-23", "ww'x'yHH G-H"))
    false
  } catch {
    ArffError::Invalid(_) => true
    _ => false
  }
  assert_true(era_conflict)
}

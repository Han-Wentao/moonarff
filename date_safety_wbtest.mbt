///|
test "date numeric overflow must not wrap into a valid calendar field" {
  let cases = [
    ("4294969266-01-01", "yyyy-MM-dd"),
    ("1970-4294967297-01", "yyyy-MM-dd"),
    ("1970-01-4294967297", "yyyy-MM-dd"),
    ("1970-01-01 4294967296:00:00", "yyyy-MM-dd HH:mm:ss"),
    ("1970-01-01 00:4294967296:00", "yyyy-MM-dd HH:mm:ss"),
    ("1970-01-01 00:00:4294967296", "yyyy-MM-dd HH:mm:ss"),
    ("1970-01-01 00:00:00.4294967296", "yyyy-MM-dd HH:mm:ss.SSS"),
    ("2024-4294967356", "yyyy-DDD"),
    ("2024-2147483647", "yyyy-DDD"),
  ]
  for (text, pattern) in cases {
    let rejected = try {
      ignore(parse_date(text, pattern))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    }
    assert_true(rejected, msg="must reject overflowing date: " + text)
  }
}

///|
test "date overflow rejection is shared by dense sparse and chunked entry points" {
  let header = "@relation dates\n@attribute d date 'yyyy-MM-dd'\n@data\n"
  for row in ["'4294969266-01-01'", "{0 '1970-4294967297-01'}"] {
    let source = header + row + "\n"
    assert_true(
      try {
        ignore(parse(source))
        false
      } catch {
        _ => true
      },
    )
    let reader = StreamReader::new()
    let mut emitted = 0
    let rejected = try {
      for ch in source {
        reader.feed(ch.to_string(), fn(_) { emitted += 1 })
      }
      reader.finish(fn(_) { emitted += 1 })
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    assert_eq(emitted, 0)
    assert_true(
      try {
        reader.finish(fn(_) { () })
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "day of year bounds respect leap years and the Gregorian cutover" {
  for
    (text, pattern) in [
      ("2023-000", "yyyy-DDD"),
      ("2023-366", "yyyy-DDD"),
      ("2024-367", "yyyy-DDD"),
      ("1582-356", "yyyy-DDD"),
    ] {
    assert_true(
      try {
        ignore(parse_date(text, pattern))
        false
      } catch {
        _ => true
      },
    )
  }
  for
    (text, want) in [
      ("2023-365", "2023-12-31"),
      ("2024-366", "2024-12-31"),
      ("1582-355", "1582-12-31"),
    ] {
    assert_eq(format_date(parse_date(text, "yyyy-DDD"), "yyyy-MM-dd"), want)
  }
}

///|
test "two digit years use the rolling pivot and era is explicit" {
  for
    (text, want) in [
      ("45-01-01 AD", "2045-01-01"),
      ("46-01-01 AD", "2046-01-01"),
      ("00-01-01 AD", "2000-01-01"),
      ("99-01-01 AD", "1999-01-01"),
    ] {
    assert_eq(
      format_date(
        parse_date_window(
          text,
          "yy-MM-dd G",
          parse_date("1946-11-25", "yyyy-MM-dd"),
        ),
        "yyyy-MM-dd",
      ),
      want,
    )
  }
  assert_eq(
    format_date(parse_date("2024-02-29 AD", "yyyy-MM-dd G"), "yy-MM-dd G"),
    "24-02-29 AD",
  )
  for
    (text, expected_epoch) in [
      ("9999-01-01 BC", -377680233600000.0),
      ("9999-12-31 BC", -377648784000000.0),
      ("0001-01-01 BC", -62167392000000.0),
      ("0044-03-15 BC", -63517996800000.0),
      ("0001-12-31 BC", -62135856000000.0),
    ] {
    let value = parse_date(text, "yyyy-MM-dd G")
    assert_eq(value, expected_epoch)
    assert_eq(format_date(value, "yyyy-MM-dd G"), text)
  }
  assert_true(
    try {
      ignore(parse_date("0000-01-01 AD", "yyyy-MM-dd G"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "abbreviated year parsing only pivots exactly two digits" {
  for pattern in ["yy-MM-dd", "y-MM-dd"] {
    assert_eq(
      format_date(parse_date("3-01-02", pattern), "yyyy-MM-dd"),
      "0003-01-02",
    )
  }
  assert_eq(
    format_date(parse_date("003-01-02", "yy-MM-dd"), "yyyy-MM-dd"),
    "0003-01-02",
  )
}

///|
test "numeric ISO weekday validates and formats calendar dates" {
  for
    (text, want) in [
      ("1970-01-01 4", "1970-01-01 Thu"),
      ("2024-02-29 4", "2024-02-29 Thu"),
      ("2024-03-01 5", "2024-03-01 Fri"),
    ] {
    assert_eq(
      format_date(parse_date(text, "yyyy-MM-dd u"), "yyyy-MM-dd EEE"),
      want,
    )
  }
  assert_true(
    try {
      ignore(parse_date("2024-02-29 5", "yyyy-MM-dd u"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "US week year and week number round trip with ISO weekday field" {
  for
    (text, want) in [
      ("2021-W01-5", "2021-01-01"),
      ("2023-W01-7", "2023-01-01"),
      ("2020-W01-3", "2020-01-01"),
    ] {
    let timestamp = parse_date(text, "YYYY-'W'ww-u")
    assert_eq(format_date(timestamp, "yyyy-MM-dd"), want)
    assert_eq(format_date(timestamp, "YYYY-'W'ww-u"), text)
  }
  assert_true(
    try {
      ignore(parse_date("2021-W54-5", "YYYY-'W'ww-u"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "timezone name field accepts deterministic UTC and GMT offsets" {
  for
    (text, want) in [
      ("1970-01-01 GMT", "1970-01-01T00:00:00Z"),
      ("1970-01-01 GMT+08:00", "1969-12-31T16:00:00Z"),
      ("1970-01-01 GMT-05:30", "1970-01-01T05:30:00Z"),
    ] {
    assert_eq(
      format_date(parse_date(text, "yyyy-MM-dd z"), "yyyy-MM-dd'T'HH:mm:ssX"),
      want,
    )
  }
  assert_true(
    try {
      ignore(parse_date("2024-01-01 NotATimeZone", "yyyy-MM-dd z"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "week of month and weekday ordinal follow Sunday-first calendar fields" {
  for
    (pattern, text, want) in [
      ("yyyy-MM-W-u", "2024-01-1-1", "2024-01-01"),
      ("yyyy-MM-W-u", "2024-01-2-1", "2024-01-08"),
      ("yyyy-MM-F-u", "2024-02-4-4", "2024-02-22"),
      ("yyyy-MM-F-u", "2024-02-5-4", "2024-02-29"),
    ] {
    let timestamp = parse_date(text, pattern)
    assert_eq(format_date(timestamp, "yyyy-MM-dd"), want)
    assert_eq(format_date(timestamp, pattern), text)
  }
  assert_true(
    try {
      ignore(parse_date("2024-02-5-1", "yyyy-MM-F-u"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(parse_date("2024-02-1-1", "yyyy-MM-W-u"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "Gregorian cutover formatting respects strict Weka representability" {
  for
    (date, wom, ordinal) in [
      ("1582-10-01", "1582-10-1-1", "1582-10-1-1"),
      ("1582-10-04", "1582-10-1-4", "1582-10-1-4"),
      ("1582-10-15", "1582-10-1-5", "1582-10-1-5"),
      ("1582-10-16", "1582-10-1-6", "1582-10-1-6"),
      ("1582-10-17", "1582-10-2-7", "1582-10-1-7"),
      ("1582-10-21", "1582-10-2-4", "1582-10-2-4"),
      ("1582-10-31", "1582-10-4-7", "1582-10-3-7"),
    ] {
    let timestamp = parse_date(date, "yyyy-MM-dd")
    assert_eq(format_date(timestamp, "yyyy-MM-dd"), date)
    for (pattern, expected) in [("yyyy-MM-W-u", wom), ("yyyy-MM-F-u", ordinal)] {
      // Java formats these fields even when its strict parser rejects them.
      // The public writer promises lossless output, not merely nonempty text.
      assert_eq(date_format_at(timestamp, date_parts(pattern), 0), expected)
      if date == "1582-10-01" || date == "1582-10-04" {
        assert_eq(format_date(timestamp, pattern), expected)
        assert_eq(parse_date(expected, pattern), timestamp)
      } else {
        assert_true(
          try {
            ignore(parse_date(expected, pattern))
            false
          } catch {
            ArffError::Invalid(_) => true
            _ => false
          },
        )
        assert_true(
          try {
            ignore(format_date(timestamp, pattern))
            false
          } catch {
            ArffError::Invalid(_) => true
            _ => false
          },
        )
      }
    }
  }
}

///|
test "week-year field overrides older calendar year" {
  assert_eq(parse_date("2021-2021-W01-5", "yyyy-YYYY-'W'ww-u"), 1609459200000.0)
}

///|
test "selected week-year ignores lower-priority month and day fields" {
  assert_eq(
    format_date(parse_date("2023 10 8", "Y M w"), "yyyy-MM-dd"),
    "2023-02-19",
  )
  assert_eq(
    format_date(parse_date("2023 28 8", "Y d w"), "yyyy-MM-dd"),
    "2023-02-19",
  )
  assert_eq(
    format_date(parse_date("2024 9 29", "Y w d"), "yyyy-MM-dd"),
    "2024-02-25",
  )
}

///|
test "Weka week-year combination honors matching day-of-year and week selectors" {
  assert_eq(parse_date("4.52024:12-12.09", "u.Fy:HH-H.ww"), 1709208000000.0)
  assert_eq(parse_date("9/60 2024/4/February", "w/D Y/u/MMMM"), 1709164800000.0)
  assert_eq(parse_date("09x202412 AD-12", "ww'x'yHH G-H"), -62099352000000.0)
  assert_true(
    try {
      ignore(parse_date("2024:29:9x20245", "yyyy:dd:w'x'YF"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "abbreviated year pivot compares month day time and timezone" {
  let start = parse_date(
    "1946-11-25T12:30:15.123Z", "yyyy-MM-dd'T'HH:mm:ss.SSSX",
  )
  for pattern in ["y-MM-dd'T'HH:mm:ss.SSSX", "yy-MM-dd'T'HH:mm:ss.SSSX"] {
    for
      (text, want) in [
        ("46-01-01T00:00:00.000Z", "2046-01-01T00:00:00.000"),
        ("46-12-01T00:00:00.000Z", "1946-12-01T00:00:00.000"),
        ("46-11-25T12:30:15.122Z", "2046-11-25T12:30:15.122"),
        ("46-11-25T12:30:15.123Z", "1946-11-25T12:30:15.123"),
        ("46-11-25T13:00:00.000+01", "2046-11-25T12:00:00.000"),
      ] {
      assert_eq(
        format_date(
          parse_date_window(text, pattern, start),
          "yyyy-MM-dd'T'HH:mm:ss.SSS",
        ),
        want,
      )
    }
  }
  assert_eq(
    format_date(
      parse_date_window("46-12-01 BC", "yy-MM-dd G", start),
      "yyyy-MM-dd G",
    ),
    "2046-12-01 BC",
  )
  assert_eq(
    format_date(
      parse_date_window("46-W01-2", "YY-'W'ww-u", start),
      "yyyy-MM-dd",
    ),
    "2046-01-02",
  )
  assert_eq(
    format_date(
      parse_date_window("46-W49-1", "YY-'W'ww-u", start),
      "yyyy-MM-dd",
    ),
    "1946-12-02",
  )
}

///|
test "date reader keeps its century start across records" {
  let reader = Reader::new(
    "@relation r\n@attribute d date 'yy-MM-dd'\n@data\n46-01-01\n46-12-01\n",
  )
  let stream = StreamReader::new()
  let pivot = date_century_start()
  assert_true((reader.budget.date_start - pivot).abs() < 10000.0)
  assert_true((stream.budget.date_start - pivot).abs() < 10000.0)
  assert_true(reader.next() is Some(_))
  assert_true(reader.next() is Some(_))
}

///|
test "repeated SimpleDateFormat fields are parsed in source order" {
  assert_eq(
    parse_date("2024-02-29 2024", "yyyy-MM-dd yyyy"),
    parse_date("2024-02-29", "yyyy-MM-dd"),
  )
  assert_eq(
    parse_date("2024-02-29 03 February", "yyyy-MM-dd MM MMMM"),
    parse_date("2024-02-29", "yyyy-MM-dd"),
  )
  assert_eq(
    parse_date("2024-02-29 01 02 03", "yyyy-MM-dd HH mm HH"),
    parse_date("2024-02-29T03:02:00", "yyyy-MM-dd'T'HH:mm:ss"),
  )
  assert_true(
    try {
      ignore(parse_date("2024-02-29 2023", "yyyy-MM-dd yyyy"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

///|
test "date years beyond four digits remain exact through epoch milliseconds" {
  for text in ["10000-01-01", "99999-01-01", "280000-01-01"] {
    let value = parse_date(text, "yyyy-MM-dd")
    assert_eq(format_date(value, "yyyy-MM-dd"), text)
  }
  let bc = parse_date("280000-01-01 BC", "yyyy-MM-dd G")
  assert_eq(format_date(bc, "yyyy-MM-dd G"), "280000-01-01 BC")
}

///|
test "Weka DecimalFormat Unicode decimal digits and signed zero" {
  // Java 17 DecimalFormat's Character.digit(char, 10) accepts these BMP
  // Unicode decimal digit blocks for Locale.US date fields.
  let zeroes : Array[UInt16] = [
    0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6,
    0x0C66, 0x0CE6, 0x0D66, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810,
    0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0,
    0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10,
  ]
  for zero in zeroes {
    let text = StringBuilder()
    for digit in [2, 0, 2, 4] {
      text.write_char((zero.to_int() + digit).unsafe_to_char())
    }
    text.write_char('-')
    for digit in [0, 2] {
      text.write_char((zero.to_int() + digit).unsafe_to_char())
    }
    text.write_char('-')
    for digit in [2, 9] {
      text.write_char((zero.to_int() + digit).unsafe_to_char())
    }
    assert_eq(parse_date(text.to_string(), "yyyy-MM-dd"), 1709164800000.0)
  }
  assert_eq(
    parse_date("2024-02-29 ١٢:٣٤:٥٦.٧٨٩", "yyyy-MM-dd HH:mm:ss.SSS"),
    1709210096789.0,
  )
  assert_eq(
    parse_date("2024-02-29 -0:-0:-0.-0", "yyyy-MM-dd HH:mm:ss.SSS"),
    1709164800000.0,
  )
  for
    (text, pattern) in [
      ("-1-01-01", "yyyy-MM-dd"),
      ("2024-01--1", "yyyy-MM-dd"),
      ("2024-01-01 -1:00:00", "yyyy-MM-dd HH:mm:ss"),
    ] {
    assert_true(
      try {
        ignore(parse_date(text, pattern))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "date calendar covers Java long millisecond endpoints" {
  let pattern = "yyyy-MM-dd G HH:mm:ss.SSS"
  for
    (text, want) in [
      ("292269055-12-02 BC 16:47:04.192", "292269055-12-02 BC 16:47:04.192"),
      ("285190822-08-22 BC 08:00:00.000", "285190822-08-22 BC 08:00:00.000"),
      ("285200616-07-24 AD 16:00:00.000", "285200616-07-24 AD 16:00:00.000"),
      ("292278994-08-17 AD 07:12:55.806", "292278994-08-17 AD 07:12:55.807"),
    ] {
    let value = parse_date(text, pattern)
    assert_eq(format_date(value, pattern), want)
  }
  assert_true(
    try {
      ignore(parse_date("292278995-01-01 AD", "yyyy-MM-dd G"))
      false
    } catch {
      ArffError::Invalid(_) => true
      _ => false
    },
  )
}

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

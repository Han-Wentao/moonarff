///|
test "date epochs zones leap days and precision" {
  let p = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
  assert_eq(parse_date("1970-01-01T08:00:00.123+08:00", p), 123.0)
  assert_eq(parse_date("1969-12-31T23:59:59.999Z", p), -1.0)
  assert_eq(format_date(-1.0, p), "1969-12-31T23:59:59.999Z")
  assert_eq(parse_date("2000-02-29", "yyyy-MM-dd"), 951782400000.0)
  assert_eq(parse_date("19700101", "yyyyMMdd"), 0.0)
  assert_eq(parse_date("1970-1-1 8:0:0 +0800", "yyyy-M-d H:m:s Z"), 0.0)
  for
    text in [
      "1900-02-29", "2000-13-01", "2001-04-31", "0000-01-01", "2020-01-01extra",
    ] {
    assert_true(
      try {
        ignore(parse_date(text, "yyyy-MM-dd"))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(format_date(1.0, "yyyy-MM-dd"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "date ARFF default custom and sparse zero" {
  let d = parse(
    "@relation dates\n@attribute d date\n@attribute day date 'yyyy-MM-dd'\n@data\n'1970-01-01T00:00:00','2024-02-29'\n?,?\n{}, {2.5}\n",
  )
  assert_eq(d.rows[0].values[0], DateValue(0.0))
  assert_eq(d.rows[2].weight, 2.5)
  assert_eq(d.rows[2].values, [DateValue(0.0), DateValue(0.0)])
  assert_eq(parse(write(d)), d)
  assert_eq(parse(write_sparse(d)), d)
}

///|
test "relational nested schema empty missing and weighted instances" {
  let source = "@relation bags\n@attribute id numeric\n@attribute bag relational\n @attribute x numeric\n @attribute name string\n@end bag\n@data\n1,'2,hello\\n3,\\\"comma,value\\\",{0.25}',{2.5}\n2,''\n3,?\n"
  let d = parse(source)
  assert_eq(d.rows[0].weight, 2.5)
  match d.rows[0].values[1] {
    Relation(rows) => {
      assert_eq(rows.length(), 2)
      assert_eq(rows[1].weight, 0.25)
      assert_eq(rows[1].values[1], Label("comma,value"))
    }
    _ => fail("expected relation")
  }
  assert_eq(d.rows[1].values[1], Relation([]))
  assert_eq(d.rows[2].values[1], Missing)
  assert_eq(parse(write(d)), d)
  assert_eq(parse(write_sparse(d)), d)
  let child = "@relation r\n@attribute a relational\n@attribute b relational\n@attribute n numeric\n@end b\n@end a\n@data\n'\\\"7\\\"'\n"
  let nested = parse(child)
  assert_eq(parse(write(nested)), nested)
  assert_eq(parse(write_sparse(nested)), nested)
}

///|
test "relational declaration errors and nested global budgets" {
  for
    text in [
      "@relation r\n@attribute a relational\n@end b\n@data\n", "@relation r\n@attribute a relational\n@end a\n@data\n",
      "@relation r\n@attribute a relational\n@attribute n numeric\n@data\n",
    ] {
    assert_true(
      try {
        ignore(parse(text))
        false
      } catch {
        _ => true
      },
    )
  }
  let text = "@relation r\n@attribute a relational\n@attribute n numeric\n@end a\n@data\n'1\\n2'\n"
  let limits = Limits::{ ..Limits::default(), max_rows: 2, }
  assert_true(
    try {
      ignore(parse(text, limits~))
      false
    } catch {
      _ => true
    },
  )
  let limits = Limits::{ ..Limits::default(), max_cells: 2, }
  assert_true(
    try {
      ignore(parse(text, limits~))
      false
    } catch {
      _ => true
    },
  )
  let limits = Limits::{ ..Limits::default(), max_attributes: 1, }
  assert_true(
    try {
      ignore(parse(text, limits~))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "weights finite signed preserved and malformed rejected" {
  let header = "@relation r\n@attribute n numeric\n@data\n"
  let d = parse(header + "1,{0}\n{0 2},{-0.5}\n3,{1}\n")
  assert_eq(d.rows.map(fn(r) { r.weight }), [0.0, -0.5, 1.0])
  assert_eq(parse(write(d)), d)
  assert_eq(parse(write_sparse(d)), d)
  assert_eq(project(d, ["n"]).rows[1].weight, -0.5)
  for text in ["1,{NaN}", "1,{1e999}", "1,{2,3}", "1,{2} trailing", "1,{}"] {
    assert_true(
      try {
        ignore(parse(header + text))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "Weka Gregorian cutover and numeric millisecond widths" {
  assert_eq(parse_date("1500-01-01", "yyyy-MM-dd"), -14830992000000.0)
  assert_eq(format_date(-14830992000000.0, "yyyy-MM-dd"), "1500-01-01")
  assert_eq(
    parse_date("1582-10-15", "yyyy-MM-dd") -
    parse_date("1582-10-04", "yyyy-MM-dd"),
    86400000.0,
  )
  assert_true(
    try {
      ignore(parse_date("1582-10-10", "yyyy-MM-dd"))
      false
    } catch {
      _ => true
    },
  )
  for
    p in [
      "yyyy-MM-dd'T'HH:mm:ss.S", "yyyy-MM-dd'T'HH:mm:ss.SS", "yyyy-MM-dd'T'HH:mm:ss.SSS",
    ] {
    for v in [1.0, 12.0, 123.0, -1.0] {
      assert_eq(parse_date(format_date(v, p), p), v)
    }
  }
}

///|
test "date feature pipeline and weighted records refuse silent loss" {
  let d = parse(
    "@relation r\n@attribute d date 'yyyy-MM-dd'\n@attribute c {a,b}\n@data\n1970-01-01,a\n?,b\n",
  )
  let plan = fit_features(d.schema)
  let features = encode_features(plan, d)
  assert_eq(decode_features(plan, features), d)
  d.rows[0] = { ..d.rows[0], weight: 2.0, }
  assert_true(
    try {
      ignore(encode_features(plan, d))
      false
    } catch {
      _ => true
    },
  )
  match profile(d).columns[0] {
    DateProfile(s) => {
      assert_eq(s.count, 1)
      assert_eq(s.missing, 1)
    }
    _ => fail("expected date profile")
  }
}

///|
test "nested rows are deeply copied by projection and concatenation" {
  let d = parse(
    "@relation r\n@attribute bag relational\n@attribute n numeric\n@end bag\n@data\n'1,{2}',{3}\n",
  )
  let projected = project(d, ["bag"])
  match projected.rows[0].values[0] {
    Relation(children) => children[0].values[0] = Number(99.0)
    _ => fail("relation expected")
  }
  assert_eq(d.rows[0].weight, 3.0)
  match d.rows[0].values[0] {
    Relation(children) => {
      assert_eq(children[0].values[0], Number(1.0))
      assert_eq(children[0].weight, 2.0)
    }
    _ => fail("relation expected")
  }
  let joined = concatenate(d, d)
  assert_eq(joined.rows.length(), 2)
  assert_eq(parse(write(joined)), joined)
}

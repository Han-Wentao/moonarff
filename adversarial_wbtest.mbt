///|
test "adversarial grammar and unsupported constructs fail deterministically" {
  let header = "@relation r\n@attribute x numeric\n@data\n"
  for
    row in [
      ",", "1,", "1 2", "{0}", "{0 1,0 2}", "{1 1}", "{-1 2}", "{2147483648 2}",
      "{0 1,}", "{0 1} trailing", "NaN", "Infinity", "1e", "--1", ".", "0x10", "1_000",
      "'1'junk",
    ] {
    let rejected = try {
      let _ = parse(header + row)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for
    source in [
      "@relation r\n@attribute x date 'yyyy-QQ'\n@data\n", "@relation r\n@attribute x relational\n@data\n",
      "@relation r\n@attribute x {a,a}\n@data\n", "@relation r\n@attribute x numeric\n@attribute x numeric\n@data\n",
    ] {
    let rejected = try {
      let _ = parse(source)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "limits apply to rows expanded sparse cells and data validation" {
  let source = "@relation r\n@attribute x numeric\n@attribute y numeric\n@data\n{}\n{}\n"
  for
    limits in [
      { ..Limits::default(), max_rows: 1, },
      { ..Limits::default(), max_cells: 3, },
      { ..Limits::default(), max_attributes: 1, },
      { ..Limits::default(), max_input: 10, },
    ] {
    let rejected = try {
      let _ = parse(source, limits~)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let empty = parse("@relation r\n@attribute x numeric\n@data\n", limits={
    ..Limits::default(),
    max_rows: 0,
    max_cells: 0,
  })
  assert_eq(empty.rows.length(), 0)
}

///|
test "round trips decimal scales comments escapes and CRLF" {
  let header = "% leading\r\n@RELATION 'r %'\r\n@ATTRIBUTE x REAL\r\n@ATTRIBUTE t STRING\r\n@DATA\r\n"
  for
    numeric in [
      "-0", "1e-300", "1e300", "1.2345678901234567", "-9.87654321012345e-100", "+.5",
      "1.",
    ] {
    let data = parse(
      header + numeric + ",'quote\\'comma,percent%newline\\n' % tail\r\n",
    )
    assert_eq(parse(write(data)), data)
    assert_eq(parse(write_sparse(data)), data)
  }
}

///|
test "missing feature payloads and masks are jointly validated" {
  let data = parse("@relation r\n@attribute c {a,b}\n@data\n?\n")
  let plan = fit_features(data.schema)
  let batch = encode_features(plan, data)
  batch.values[0][0] = 1.0
  let rejected = try {
    validate_features(plan, batch)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  batch.values[0][0] = 0.0
  batch.missing.clear()
  let rejected = try {
    let _ = decode_features(plan, batch)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "sparse zero defaults are distinct from missing" {
  let d = parse(
    "@relation r\n@attribute n numeric\n@attribute c {zero,one}\n@data\n{}\n{0 ?,1 one}\n",
  )
  assert_true(d.rows[0].values == [Number(0.0), Label("zero")])
  assert_true(d.rows[1].values == [Missing, Label("one")])
}

///|
test "sparse indices and delimiters are constrained" {
  let h = "@relation r\n@attribute n numeric\n@attribute c {zero,one}\n@data\n"
  for
    row in [
      "{1 one,0 2}", "{0 2,0 3}", "{2 1}", "{-1 2}", "{0 2,}", "{0}", "{0 2", "{99999999999999999999999 0}",
    ] {
    assert_true(
      try {
        ignore(parse(h + row))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "sparse strings require explicit values" {
  let h = "@relation r\n@attribute s string\n@data\n"
  assert_true(parse(h + "{0 'x'}").rows[0].values == [Label("x")])
  assert_true(
    try {
      ignore(parse(h + "{}"))
      false
    } catch {
      _ => true
    },
  )
}

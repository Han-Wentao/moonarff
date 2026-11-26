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
test "sparse dictionary zero resolves across later explicit string" {
  let h = "@relation r\n@attribute s string\n@data\n"
  let data = parse(h + "{}\n{0 'later'}\n")
  assert_true(data.rows[0].values == [Label("later")])
  assert_true(data.rows[1].values == [Label("later")])
  assert_eq(parse(write(data)), data)
}

///|
test "sparse dictionary zero remains explicit when its dictionary is empty" {
  let data = parse("@relation r\n@attribute s string\n@data\n{}\n{}\n")
  assert_true(data.rows[0].values == [DictionaryZero])
  let sparse = write_sparse(data)
  assert_true(sparse.contains("{}"))
  assert_eq(parse(sparse), data)
  assert_true(
    try {
      ignore(write(data))
      false
    } catch {
      _ => true
    },
  )
}

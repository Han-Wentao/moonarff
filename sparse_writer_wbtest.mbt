///|
test "sparse writer retains missing text and signed zero" {
  let source = "@relation r\n@attribute x numeric\n@attribute c {a,b}\n@attribute t string\n@data\n0,a,'?'\n-0.0,?,''\n?,b,?\n"
  let data = parse(source)
  let encoded = write_sparse(data)
  assert_true(encoded.contains("{2 '?'}"))
  assert_eq(parse(encoded), data)
  match parse(encoded).rows[1].values[0] {
    Number(n) => assert_true(1.0 / n < 0.0)
    _ => fail("negative zero lost")
  }
}

///|
test "empty sparse row preserves defaults" {
  let data = parse(
    "@relation r\n@attribute x numeric\n@attribute c {a,b}\n@data\n0,a\n",
  )
  assert_true(write_sparse(data).contains("{}"))
  assert_eq(parse(write_sparse(data)), data)
}

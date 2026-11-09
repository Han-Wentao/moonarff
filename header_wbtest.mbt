///|
test "header names types nominal order and case folding" {
  let r = read_schema(
    "@ReLaTiOn 'a b'\r\n@attribute 'x y' integer\n@attribute c {'?', yes,'a,b'}\n@attribute s STRING\n@DATA\n",
  )
  assert_eq(r.relation, "a b")
  assert_true(r.attributes[0].kind == Numeric)
  assert_true(r.attributes[1].kind == Nominal(["?", "yes", "a,b"]))
}

///|
test "header rejects malformed grammar and unsupported attribute kinds" {
  for
    source in [
      "@attribute x numeric\n@data", "@relation x\n@data", "@relation x\n@attribute x {a,}\n@data",
      "@relation x\n@attribute x date\n@data", "@relation x\n@attribute x numeric\n@attribute x string\n@data",
    ] {
    let bad = try {
      ignore(read_schema(source))
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
}

///|
test "Weka numeric lexical forms are interpreted by the ARFF reader" {
  let data = parse(
    "@relation n\n@attribute x numeric\n@data\n0x1.0p2\n1d\n 1 \nNaN\nInfinity\n",
  )
  assert_eq(data.rows[0].values, [Number(4.0)])
  assert_eq(data.rows[1].values, [Number(1.0)])
  assert_eq(data.rows[2].values, [Number(1.0)])
  assert_eq(data.rows[3].values, [Missing])
  assert_eq(data.rows[4].values, [Number(@double.infinity)])
}

///|
test "hexadecimal IEEE-754 boundary rounding preserves all bits" {
  let cases : Array[(String, UInt64)] = [
    ("0x1.fffffffffffffp1023", 0x7fefffffffffffffUL),
    ("0x1p1024", 0x7ff0000000000000UL),
    ("-0x1p1024", 0xfff0000000000000UL),
    ("0x0p1024", 0UL),
    ("0x1p-1074", 1UL),
    ("0x1p-1075", 0UL),
    ("-0x1p-1075", 0x8000000000000000UL),
    ("0x1.00000000000008p0", 0x3ff0000000000000UL),
    ("0x1.00000000000018p0", 0x3ff0000000000002UL),
    ("0x1.0000000000000800001p0", 0x3ff0000000000001UL),
    ("0x0.fffffffffffff8p-1022", 0x0010000000000000UL),
    ("0x0.fffffffffffff7p-1022", 0x000fffffffffffffUL),
    ("0x3p-1075", 2UL),
    ("0x5p-1075", 2UL),
    ("0x1.fffffffffffff8p1023", 0x7ff0000000000000UL),
  ]
  for pair in cases {
    let (text, bits) = pair
    assert_eq(decimal(text).reinterpret_as_uint64(), bits)
    let full = parse(
      "@relation hex\n@attribute n numeric\n@data\n" + text + "\n",
    )
    match full.rows[0].values[0] {
      Number(value) => assert_eq(value.reinterpret_as_uint64(), bits)
      _ => fail("numeric value expected")
    }
  }
}

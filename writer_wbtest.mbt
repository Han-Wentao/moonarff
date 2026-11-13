///|
test "dense serialization roundtrip quotes escapes and Unicode" {
  let d = Dataset::{
    schema: {
      relation: "汉字 🍎",
      attributes: [
        { name: "n", kind: Numeric, },
        { name: "s", kind: Text, },
        { name: "c", kind: Nominal(["?", "a,b"]), },
      ],
    },
    rows: [
      {
        weight: 1.0,
        values: [Number(-2.25e10), Label("a'\\\n\t% 🍎"), Label("?")],
      },
      { weight: 1.0, values: [Missing, Label(""), Missing], },
    ],
  }
  assert_true(parse(write(d)) == d)
  assert_eq(write(parse(write(d))), write(d))
}

///|
test "writer rejects invalid typed data before emitting" {
  let d = Dataset::{
    schema: { relation: "r", attributes: [{ name: "x", kind: Numeric, }], },
    rows: [{ weight: 1.0, values: [Label("1")], }],
  }
  assert_true(
    try {
      ignore(write(d))
      false
    } catch {
      _ => true
    },
  )
}

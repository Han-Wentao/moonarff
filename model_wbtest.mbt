///|
test "typed schema validation and missing cells" {
  let schema = Schema::{
    relation: "sample",
    attributes: [
      { name: "x", kind: Numeric, },
      { name: "class", kind: Nominal(["yes", "no"]), },
    ],
  }
  validate({ schema, rows: [{ weight: 1.0, values: [Number(2.0), Missing], }], })
  assert_eq(schema.index_of("class"), Some(1))
  assert_eq(schema.index_of("absent"), None)
}

///|
test "reject invalid domain and incompatible cells" {
  let schema = Schema::{
    relation: "r",
    attributes: [{ name: "class", kind: Nominal(["yes"]), }],
  }
  let bad = try {
    validate_record(schema, { weight: 1.0, values: [Label("no")], })
    false
  } catch {
    _ => true
  }
  assert_true(bad)
  let duplicate = try {
    validate_schema({
      relation: "r",
      attributes: [{ name: "a", kind: Nominal(["x", "x"]), }],
    })
    false
  } catch {
    _ => true
  }
  assert_true(duplicate)
}

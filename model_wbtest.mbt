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

///|
test "dictionary defaults reject malformed public input without indexing" {
  let schema = Schema::{
    relation: "r",
    attributes: [{ name: "s", kind: Text, }],
  }
  let short = try {
    ignore(resolve_dictionary_defaults(schema, [{ values: [], weight: 1.0, }]))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(short)
}

///|
test "dictionary defaults validate nested values schema and aggregate budgets" {
  let schema = Schema::{
    relation: "r",
    attributes: [
      { name: "children", kind: Relational([{ name: "s", kind: Text, }]), },
    ],
  }
  for
    values in [
      [Relation([{ values: [], weight: 1.0, }])],
      [Relation([{ values: [Number(1.0)], weight: 1.0, }])],
    ] {
    let rejected = try {
      ignore(resolve_dictionary_defaults(schema, [{ values, weight: 1.0, }]))
      false
    } catch {
      Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
  let bad_schema = try {
    ignore(resolve_dictionary_defaults({ relation: "", attributes: [], }, []))
    false
  } catch {
    Invalid(_) => true
    _ => false
  }
  assert_true(bad_schema)
  let rows = [
    {
      values: [Relation([{ values: [Label("x")], weight: 1.0, }])],
      weight: 1.0,
    },
  ]
  let small = Limits::{ ..Limits::default(), max_cells: 1, }
  let over_budget = try {
    ignore(resolve_dictionary_defaults(schema, rows, limits=small))
    false
  } catch {
    Limit(_) => true
    _ => false
  }
  assert_true(over_budget)
}

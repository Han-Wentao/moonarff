///|
test "feature plan uses declaration order and isolates source mutations" {
  let schema = read_schema(
    "@relation r\n@attribute c {z,a,unused}\n@attribute n numeric\n@data\n",
  )
  let plan = fit_features(schema)
  assert_eq(plan.width(), 4)
  assert_eq(plan.columns()[0].category, Some("z"))
  match schema.attributes[0].kind {
    Nominal(xs) => xs[0] = "changed"
    _ => fail("nominal")
  }
  assert_eq(plan.columns()[0].category, Some("z"))
  let copy = plan.columns()
  copy.clear()
  assert_eq(plan.width(), 4)
}

///|
test "feature planning bounds expansion and rejects implicit string encoding" {
  let schema = read_schema("@relation r\n@attribute c {a,b,c}\n@data\n")
  let rejected = try {
    let _ = fit_features(schema, limits={
      ..Limits::default(),
      max_attributes: 2,
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let text = read_schema("@relation r\n@attribute t string\n@data\n")
  let rejected = try {
    let _ = fit_features(text)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

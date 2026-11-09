///|
test "encoding distinguishes missing categories from the first label" {
  let data = parse(
    "@relation r\n@attribute c {a,b,z}\n@attribute n numeric\n@data\na,0\n?,?\nb,3\n",
  )
  let plan = fit_features(data.schema)
  let batch = encode_features(plan, data)
  assert_eq(batch.values[0], [1.0, 0.0, 0.0, 0.0])
  assert_eq(batch.values[1], [0.0, 0.0, 0.0, 0.0])
  assert_eq(batch.missing[1], [true, true, true, true])
  validate_features(plan, batch)
  batch.values[0][1] = 1.0
  let rejected = try {
    validate_features(plan, batch)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "feature schema mismatch and expanded budgets are rejected" {
  let a = parse("@relation r\n@attribute c {a,b}\n@data\na\n")
  let b = parse("@relation r\n@attribute c {b,a}\n@data\na\n")
  let plan = fit_features(a.schema)
  let rejected = try {
    let _ = encode_features(plan, b)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    let _ = encode_features(plan, a, limits={
      ..Limits::default(),
      max_cells: 1,
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

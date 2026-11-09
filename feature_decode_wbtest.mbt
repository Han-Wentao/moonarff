///|
test "feature round trip preserves missing and all declared categories" {
  let data = parse(
    "@relation 'train set'\n@attribute n numeric\n@attribute c {'?',b,unused}\n@data\n-0.0,'?'\n?,?\n42,b\n",
  )
  let plan = fit_features(data.schema)
  let restored = decode_features(plan, encode_features(plan, data))
  assert_eq(restored, data)
  assert_eq(restored.schema.attributes[1].kind, Nominal(["?", "b", "unused"]))
}

///|
test "decoder rejects ambiguous or malformed feature groups" {
  let data = parse("@relation r\n@attribute c {a,b}\n@data\na\n")
  let plan = fit_features(data.schema)
  let batch = encode_features(plan, data)
  batch.values[0][0] = 0.0
  let rejected = try {
    let _ = decode_features(plan, batch)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  batch.values[0][0] = 1.0
  batch.missing[0][1] = true
  let rejected = try {
    let _ = decode_features(plan, batch)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

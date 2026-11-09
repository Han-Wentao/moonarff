///|
test "CSV uses stable positional names and explicit category metadata" {
  let data = parse(
    "@relation r\n@attribute 'a,b' {'',x}\n@attribute n numeric\n@data\n'',0\n?,?\n",
  )
  let plan = fit_features(data.schema)
  let csv = features_csv(plan, encode_features(plan, data))
  assert_eq(csv, "f0,f1,f2\r\n1,0,0\r\n,,\r\n")
  assert_true(feature_dictionary_csv(plan).contains("f0,\"a,b\",true,\"\""))
  assert_true(feature_dictionary_csv(plan).contains("f2,\"n\",false,\"\""))
  let rejected = try {
    let _ = features_csv(plan, encode_features(plan, data), limits={
      ..Limits::default(),
      max_input: 2,
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "simultaneous rename allows swaps and rejects collisions" {
  let data = parse(
    "@relation r\n@attribute a numeric\n@attribute b {x,y,z}\n@data\n1,x\n2,?\n",
  )
  let renamed = rename(
    data,
    Map([("a", "b"), ("b", "a")]),
    relation=Some("new"),
  )
  assert_eq(renamed.schema.attributes[0].name, "b")
  assert_eq(renamed.schema.relation, "new")
  let rejected = try {
    let _ = rename(data, Map([("a", "b")]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let coded = recode_nominal(data, "b", Map([("x", "X"), ("z", "Z")]))
  assert_eq(coded.schema.attributes[1].kind, Nominal(["X", "y", "Z"]))
  assert_eq(coded.rows[0].values[1], Label("X"))
  assert_eq(coded.rows[1].values[1], Missing)
  let rejected = try {
    let _ = recode_nominal(data, "b", Map([("x", "y")]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

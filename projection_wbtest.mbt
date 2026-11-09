///|
test "projection reorders schema and rows without aliasing domains" {
  let data = parse(
    "@relation r\n@attribute n numeric\n@attribute c {a,b}\n@data\n1,a\n2,b\n",
  )
  let selected = project(data, ["c", "n"])
  assert_eq(selected.rows[0].values, [Label("a"), Number(1.0)])
  match selected.schema.attributes[0].kind {
    Nominal(labels) => labels[0] = "changed"
    _ => fail("nominal")
  }
  assert_eq(data.schema.attributes[1].kind, Nominal(["a", "b"]))
  assert_eq(slice_rows(data, 1, 2).rows[0].values[0], Number(2.0))
  assert_eq(slice_rows(data, 2, 2).rows.length(), 0)
}

///|
test "projection rejects duplicate and unknown names" {
  let data = parse("@relation r\n@attribute n numeric\n@data\n1\n")
  let rejected = try {
    let _ = project(data, ["n", "n"])
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    let _ = project(data, ["absent"])
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    let _ = slice_rows(data, -1, 0)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

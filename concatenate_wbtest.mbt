///|
test "concatenate requires ordered domains unless union is explicit" {
  let a = parse("@relation a\n@attribute x {a,b}\n@data\na\n")
  let b = parse("@relation b\n@attribute x {b,c,a}\n@data\nc\n")
  let rejected = try {
    let _ = concatenate(a, b)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let merged = concatenate(a, b, union_domains=true)
  assert_eq(merged.schema.attributes[0].kind, Nominal(["a", "b", "c"]))
  assert_eq(merged.rows[1].values[0], Label("c"))
  assert_eq(parse(write_sparse(merged)), merged)
  let limits = { ..Limits::default(), max_rows: 1, }
  let rejected = try {
    let _ = concatenate(a, a, limits~)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

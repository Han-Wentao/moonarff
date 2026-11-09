///|
test "decoded token budget counts UTF-16 not escaped source length" {
  let limits = { ..Limits::default(), max_token: 10, }
  let data = parse(
    "@relation r\n@attribute x string\n@data\n'\\n\\n\\n\\n\\n\\n'\n",
    limits~,
  )
  assert_eq(parse(write(data, limits~), limits~), data)
  let scanner = Scanner::new("'😀😀'", limits={ ..limits, max_token: 3, })
  let rejected = try {
    let _ = scanner.next()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "serialization rejects expanded output before unbounded accumulation" {
  let data = parse("@relation r\n@attribute t string\n@data\n'abc'\n'abc'\n")
  let rejected = try {
    let _ = write(data, limits={ ..Limits::default(), max_input: 10, })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    let _ = parse("", limits={
      ..Limits::default(),
      max_attributes: 2147483647,
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

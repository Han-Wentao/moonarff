///|
test "reader snapshots cannot corrupt live width and errors are terminal" {
  let reader = Reader::new("@relation r\n@attribute x numeric\n@data\nbad\n2\n")
  let snapshot = reader.schema()
  snapshot.attributes.clear()
  assert_eq(reader.schema().attributes.length(), 1)
  let rejected = try {
    let _ = reader.next()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let rejected = try {
    let _ = reader.next()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "unquoted embedded quotes and leading escapes are rejected" {
  for text in ["ab'cd", "\\abc"] {
    let scanner = Scanner::new(text)
    let rejected = try {
      let _ = scanner.next()
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

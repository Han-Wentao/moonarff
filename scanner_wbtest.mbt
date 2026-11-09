///|
test "scanner quotes comments escaped delimiters and Unicode" {
  let s = Scanner::new("% ignored\r\n'汉字 🍎, %' , '?' ")
  assert_true(s.next().kind == Newline)
  let t = s.next()
  assert_eq(t.text, "汉字 🍎, %")
  assert_eq(t.line, 2)
  assert_true(t.quoted)
  assert_true(s.next().kind == Comma)
  assert_eq(s.next().text, "?")
  assert_true(s.next().kind == End)
}

///|
test "scanner rejects malformed escapes and raw quoted newlines" {
  for input in ["'a\\z'", "'x\ny'", "'x'junk"] {
    let bad = try {
      ignore(Scanner::new(input).next())
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
}

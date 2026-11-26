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
test "scanner rejects truncated escapes and raw quoted newlines" {
  for input in ["'a\\", "'x\ny'", "'x'junk"] {
    let bad = try {
      ignore(Scanner::new(input).next())
      false
    } catch {
      _ => true
    }
    assert_true(bad)
  }
}

///|
test "scanner matches Java escape decoding used by Weka" {
  let scanner = Scanner::new("'\\q' '\\a' '\\v' '\\101' '\\377'")
  assert_eq(scanner.next().text, "q")
  assert_eq(scanner.next().text, "\u{0007}")
  assert_eq(scanner.next().text, "\u{000B}")
  assert_eq(scanner.next().text, "A")
  assert_eq(scanner.next().text, "\u{00FF}")
}

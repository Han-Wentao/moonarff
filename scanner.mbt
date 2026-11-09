///|
pub(all) enum TokenKind {
  Word
  Comma
  Open
  Close
  Newline
  End
} derive(Eq)

///|
pub extend TokenKind with Eq::{equal, not_equal}

///|
pub(all) struct Token {
  kind : TokenKind
  text : String
  quoted : Bool
  line : Int32
  column : Int32
}

///|
/// Scanner owns a bounded copy of Unicode scalars. Positions are scalar based.
pub struct Scanner {
  priv chars : Array[Char]
  priv mut pos : Int32
  priv mut line : Int32
  priv mut column : Int32
  priv max_token : Int32
}

///|
pub fn Scanner::new(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Scanner raise ArffError {
  limits.check()
  if source.length() > limits.max_input {
    raise Limit("input budget")
  }
  let chars : Array[Char] = []
  for ch in source {
    chars.push(ch)
  }
  { chars, pos: 0, line: 1, column: 1, max_token: limits.max_token, }
}

///|
fn Scanner::take(self : Scanner) -> Char {
  let ch = self.chars[self.pos]
  self.pos += 1
  if ch == '\n' {
    self.line += 1
    self.column = 1
  } else {
    self.column += 1
  }
  ch
}

///|
fn horizontal(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\u{000C}'
}

///|
fn delimiter(c : Char) -> Bool {
  horizontal(c) ||
  c == '\n' ||
  c == '\r' ||
  c == ',' ||
  c == '{' ||
  c == '}' ||
  c == '%'
}

///|
pub fn Scanner::next(self : Scanner) -> Token raise ArffError {
  while self.pos < self.chars.length() {
    let c = self.chars[self.pos]
    if horizontal(c) {
      ignore(self.take())
      continue
    }
    if c == '%' {
      while self.pos < self.chars.length() &&
            self.chars[self.pos] != '\n' &&
            self.chars[self.pos] != '\r' {
        ignore(self.take())
      }
      continue
    }
    break
  }
  let line = self.line
  let column = self.column
  if self.pos == self.chars.length() {
    return { kind: End, text: "", quoted: false, line, column, }
  }
  let c = self.take()
  let simple = match c {
    ',' => Some(Comma)
    '{' => Some(Open)
    '}' => Some(Close)
    '\n' | '\r' => Some(Newline)
    _ => None
  }
  if simple is Some(kind) {
    if c == '\r' {
      if self.pos < self.chars.length() && self.chars[self.pos] == '\n' {
        ignore(self.take())
      } else {
        self.line += 1
        self.column = 1
      }
    }
    return { kind, text: "", quoted: false, line, column, }
  }
  let quoted = c == '\'' || c == '"'
  let out = BoundedText::new(self.max_token)
  if !quoted {
    out.write_char(c)
  }
  let mut closed = !quoted
  while self.pos < self.chars.length() {
    let ch = self.chars[self.pos]
    if !quoted && delimiter(ch) {
      break
    }
    ignore(self.take())
    if quoted && ch == c {
      closed = true
      break
    }
    if ch == '\n' || ch == '\r' {
      raise Syntax(line, column, "unclosed quoted token")
    }
    if ch == '\\' {
      if self.pos == self.chars.length() {
        raise Syntax(line, column, "truncated escape")
      }
      let escaped = self.take()
      match escaped {
        'n' => out.write_char('\n')
        'r' => out.write_char('\r')
        't' => out.write_char('\t')
        'b' => out.write_char('\u{0008}')
        'f' => out.write_char('\u{000C}')
        '\\' | '\'' | '"' | '%' => out.write_char(escaped)
        _ => raise Syntax(self.line, self.column, "unsupported escape")
      }
    } else {
      out.write_char(ch)
    }
  }
  if !closed {
    raise Syntax(line, column, "unclosed quoted token")
  }
  if quoted &&
    self.pos < self.chars.length() &&
    !delimiter(self.chars[self.pos]) {
    raise Syntax(self.line, self.column, "separator required after quote")
  }
  { kind: Word, text: out.to_string(), quoted, line, column, }
}

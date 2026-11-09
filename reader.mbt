///|
/// Decimal syntax is locale independent and excludes infinity/NaN/hex values.
fn decimal(text : String) -> Double raise ArffError {
  let n = text.length()
  let mut i = 0
  if n > 0 && (text[0] == 43 || text[0] == 45) {
    i += 1
  }
  let mut digits = 0
  while i < n && text[i] >= 48 && text[i] <= 57 {
    i += 1
    digits += 1
  }
  if i < n && text[i] == 46 {
    i += 1
    while i < n && text[i] >= 48 && text[i] <= 57 {
      i += 1
      digits += 1
    }
  }
  if digits == 0 {
    raise Invalid("numeric cell requires decimal digits")
  }
  if i < n && (text[i] == 69 || text[i] == 101) {
    i += 1
    if i < n && (text[i] == 43 || text[i] == 45) {
      i += 1
    }
    let start = i
    while i < n && text[i] >= 48 && text[i] <= 57 {
      i += 1
    }
    if i == start {
      raise Invalid("exponent requires digits")
    }
  }
  if i != n {
    raise Invalid("invalid numeric cell")
  }
  let value = @string.parse_double(text) catch {
    _ => raise Invalid("decimal conversion failed")
  }
  if !finite(value) {
    raise Invalid("non-finite decimal")
  }
  value
}

///|
fn parse_cell(attribute : Attribute, token : Token) -> Cell raise ArffError {
  let text = require_word(token, "cell value required")
  if text == "?" && !token.quoted {
    return Missing
  }
  match attribute.kind {
    Numeric => {
      let number = decimal(text) catch {
        _ =>
          raise Syntax(token.line, token.column, "invalid finite numeric value")
      }
      Number(number)
    }
    Text => Label(text)
    Nominal(labels) => {
      if !labels.contains(text) {
        raise Syntax(
          token.line,
          token.column,
          "value is outside nominal domain",
        )
      }
      Label(text)
    }
  }
}

///|
pub struct Reader {
  schema : Schema
  priv scanner : Scanner
  priv limits : Limits
  priv mut count : Int32
  priv mut ended : Bool
}

///|
pub fn Reader::new(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Reader raise ArffError {
  let scanner = Scanner::new(source, limits~)
  let schema = parse_header(scanner, limits)
  { schema, scanner, limits, count: 0, ended: false, }
}

///|
/// Repeated next after EOF returns None. Invalid rows raise with no partial row returned.
pub fn Reader::next(self : Reader) -> Record? raise ArffError {
  if self.ended {
    return None
  }
  let mut first = self.scanner.next()
  while first.kind == Newline {
    first = self.scanner.next()
  }
  if first.kind == End {
    self.ended = true
    return None
  }
  let width = self.schema.attributes.length()
  if self.count >= self.limits.max_rows ||
    self.count >= self.limits.max_cells / width {
    raise Limit("expanded row/cell budget")
  }
  let rest = line_tokens(self.scanner, self.limits.max_attributes * 3 + 3)
  let tokens = [first]
  for token in rest {
    tokens.push(token)
  }
  if first.kind == Open {
    let row = sparse_record(self.schema, tokens)
    self.count += 1
    return Some(row)
  }
  let values : Array[Cell] = []
  let mut i = 0
  for column in 0..<width {
    if i >= tokens.length() {
      raise Syntax(first.line, first.column, "record has too few cells")
    }
    values.push(parse_cell(self.schema.attributes[column], tokens[i]))
    i += 1
    if column + 1 < width {
      if i >= tokens.length() || tokens[i].kind != Comma {
        raise Syntax(first.line, first.column, "comma required between cells")
      }
      i += 1
    }
  }
  if i != tokens.length() {
    raise Syntax(
      first.line,
      first.column,
      "record has extra cells or unsupported instance weight",
    )
  }
  self.count += 1
  Some({ values, })
}

///|
/// Fully materialize a bounded dataset. Reader::next avoids retaining previous rows.
pub fn parse(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  let reader = Reader::new(source, limits~)
  let rows : Array[Record] = []
  while reader.next() is Some(row) {
    rows.push(row)
  }
  { schema: reader.schema, rows, }
}

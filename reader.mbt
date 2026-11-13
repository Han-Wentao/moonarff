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
  if value == 0.0 && text[0] == 45 {
    -0.0
  } else {
    value
  }
}

///|
fn parse_cell(
  attribute : Attribute,
  token : Token,
  budget : FormatBudget,
  depth : Int32,
) -> Cell raise ArffError {
  let text = require_word(token, "cell value required")
  if text == "?" && !token.quoted {
    return Missing
  }
  match attribute.kind {
    Numeric => Number(decimal(text))
    Date(pattern) => DateValue(parse_date(text, pattern))
    Text => Label(text)
    Nominal(labels) => {
      if !labels.contains(text) {
        raise Syntax(token.line, token.column, "value outside nominal domain")
      }
      Label(text)
    }
    Relational(attributes) => {
      if !token.quoted {
        raise Syntax(
          token.line,
          token.column,
          "relational value must be quoted",
        )
      }
      if depth >= 16 {
        raise Limit("relational value nesting exceeds 16")
      }
      let scanner = Scanner::new(text, limits=budget.limits)
      let rows = []
      while read_record_tokens(scanner, budget.limits) is Some(tokens) {
        rows.push(parse_record_tokens(attributes, tokens, budget, depth + 1))
      }
      Relation(rows)
    }
  }
}

///|
fn read_record_tokens(
  scanner : Scanner,
  limits : Limits,
) -> Array[Token]? raise ArffError {
  let mut first = scanner.next()
  while first.kind == Newline {
    first = scanner.next()
  }
  if first.kind == End {
    return None
  }
  let tokens = [first]
  for token in line_tokens(scanner, limits.max_attributes * 3 + 7) {
    tokens.push(token)
  }
  Some(tokens)
}

///|
fn parse_record_tokens(
  attributes : Array[Attribute],
  input : Array[Token],
  budget : FormatBudget,
  depth : Int32,
) -> Record raise ArffError {
  if depth > 16 {
    raise Limit("relational nesting exceeds 16")
  }
  if budget.rows >= budget.limits.max_rows ||
    attributes.length() > budget.limits.max_cells - budget.cells {
    raise Limit("total nested row/cell budget")
  }
  budget.rows += 1
  budget.cells += attributes.length()
  let tokens = input.copy()
  let n = tokens.length()
  let mut weight = 1.0
  if n >= 5 &&
    tokens[n - 4].kind == Comma &&
    tokens[n - 3].kind == Open &&
    tokens[n - 1].kind == Close {
    weight = decimal(require_word(tokens[n - 2], "instance weight required"))
    for _ in 0..<4 {
      ignore(tokens.pop())
    }
  }
  let first = tokens[0]
  if first.kind == Open {
    return sparse_record(attributes, tokens, weight, budget, depth)
  }
  let values = []
  let mut i = 0
  for column in 0..<attributes.length() {
    if i >= tokens.length() {
      raise Syntax(first.line, first.column, "record has too few cells")
    }
    values.push(parse_cell(attributes[column], tokens[i], budget, depth))
    i += 1
    if column + 1 < attributes.length() {
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
      "extra cells or malformed instance weight",
    )
  }
  { values, weight, }
}

///|
/// In-memory pull reader. Use StreamReader for bounded chunk-fed incremental input.
pub struct Reader {
  priv schema : Schema
  priv scanner : Scanner
  priv budget : FormatBudget
  priv mut failed : Bool
  priv mut ended : Bool
}

///|
pub fn Reader::new(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Reader raise ArffError {
  let scanner = Scanner::new(source, limits~)
  let schema = parse_header(scanner, limits)
  {
    schema,
    scanner,
    budget: FormatBudget::new(limits),
    failed: false,
    ended: false,
  }
}

///|
pub fn parse(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  let reader = Reader::new(source, limits~)
  let rows = []
  while reader.next() is Some(row) {
    rows.push(row)
  }
  { schema: reader.schema(), rows, }
}

///|
pub fn Reader::schema(self : Reader) -> Schema {
  copy_schema(self.schema)
}

///|
pub fn Reader::next(self : Reader) -> Record? raise ArffError {
  if self.failed {
    raise Invalid("reader is failed; construct a new reader")
  }
  if self.ended {
    return None
  }
  errdefer {
    self.failed = true
  }
  match read_record_tokens(self.scanner, self.budget.limits) {
    None => {
      self.ended = true
      None
    }
    Some(tokens) =>
      Some(parse_record_tokens(self.schema.attributes, tokens, self.budget, 0))
  }
}

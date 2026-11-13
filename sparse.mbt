///|
/// Sparse indices are zero based and strictly increasing; leading zeroes are accepted.
fn sparse_index(token : Token, width : Int32) -> Int32 raise ArffError {
  if token.kind != Word || token.quoted || token.text.length() == 0 {
    raise Syntax(token.line, token.column, "unquoted sparse index required")
  }
  let mut value = 0
  for ch in token.text {
    let digit = ch.to_int() - 48
    if digit < 0 || digit > 9 || value > (2147483647 - digit) / 10 {
      raise Syntax(token.line, token.column, "invalid sparse index")
    }
    value = value * 10 + digit
  }
  if value >= width {
    raise Syntax(token.line, token.column, "sparse index outside schema")
  }
  value
}

///|
fn sparse_record(
  attributes : Array[Attribute],
  tokens : Array[Token],
  weight : Double,
  budget : FormatBudget,
  depth : Int32,
) -> Record raise ArffError {
  let first = tokens[0]
  let width = attributes.length()
  let cells : Array[Cell?] = Array::make(width, None)
  let mut previous = -1
  let mut i = 1
  while i < tokens.length() && tokens[i].kind != Close {
    let index = sparse_index(tokens[i], width)
    if index <= previous {
      raise Syntax(
        tokens[i].line,
        tokens[i].column,
        "sparse indices must be unique and increasing",
      )
    }
    previous = index
    i += 1
    if i >= tokens.length() {
      raise Syntax(first.line, first.column, "sparse value required")
    }
    cells[index] = Some(parse_cell(attributes[index], tokens[i], budget, depth))
    i += 1
    if i < tokens.length() && tokens[i].kind == Close {
      break
    }
    if i >= tokens.length() || tokens[i].kind != Comma {
      raise Syntax(first.line, first.column, "sparse comma required")
    }
    i += 1
    if i < tokens.length() && tokens[i].kind == Close {
      raise Syntax(first.line, first.column, "sparse trailing comma")
    }
  }
  if i >= tokens.length() || tokens[i].kind != Close || i + 1 != tokens.length() {
    raise Syntax(
      first.line,
      first.column,
      "unclosed sparse row or malformed instance weight",
    )
  }
  let values : Array[Cell] = []
  for index in 0..<width {
    match cells[index] {
      Some(value) => values.push(value)
      None =>
        match attributes[index].kind {
          Numeric => values.push(Number(0.0))
          Date(pattern) => {
            ignore(format_date(0.0, pattern))
            values.push(DateValue(0.0))
          }
          Relational(_) =>
            raise Unsupported(
              "sparse relational values must be explicit; dictionary index zero is not a portable default",
            )
          Nominal(labels) => values.push(Label(labels[0]))
          Text =>
            raise Unsupported(
              "sparse string attributes must be explicitly present; Weka dictionary-index zero is ambiguous",
            )
        }
    }
  }
  { values, weight, }
}

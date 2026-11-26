///|
/// Java/Weka Double lexical forms used by numeric cells and instance weights.
fn numeric_text(text : String) -> String {
  let mut start = 0
  let mut end = text.length()
  while start < end && text[start] <= 32 {
    start += 1
  }
  while end > start && text[end - 1] <= 32 {
    end -= 1
  }
  let builder = StringBuilder()
  for i in start..<end {
    builder.write_char(text[i].unsafe_to_char())
  }
  builder.to_string()
}

///|
fn hex_digit(c : Char) -> Int32? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn parse_hex_double(text : String) -> Double raise ArffError {
  let n = text.length()
  let mut i = if n > 0 && (text[0] == '+' || text[0] == '-') { 1 } else { 0 }
  let negative = n > 0 && text[0] == '-'
  if i + 2 > n || text[i] != '0' || (text[i + 1] != 'x' && text[i + 1] != 'X') {
    raise Invalid("invalid hexadecimal float")
  }
  i += 2
  let digits : Array[Int32] = []
  let mut fractional = 0
  let mut after_dot = false
  while i < n && text[i] != 'p' && text[i] != 'P' {
    if text[i] == '.' {
      if after_dot {
        raise Invalid("invalid hexadecimal float")
      }
      after_dot = true
    } else {
      match hex_digit(text[i].unsafe_to_char()) {
        Some(d) => {
          digits.push(d)
          if after_dot {
            fractional += 1
          }
        }
        None => raise Invalid("invalid hexadecimal float")
      }
    }
    i += 1
  }
  if digits.is_empty() || i >= n {
    raise Invalid("hexadecimal float requires a p exponent")
  }
  i += 1
  let mut exp_negative = false
  if i < n && (text[i] == '+' || text[i] == '-') {
    exp_negative = text[i] == '-'
    i += 1
  }
  if i >= n {
    raise Invalid("hexadecimal exponent requires digits")
  }
  let mut exponent = 0
  while i < n {
    let c = text[i]
    if c < '0' || c > '9' {
      raise Invalid("invalid hexadecimal exponent")
    }
    if exponent < 100000000 {
      exponent = exponent * 10 + c.to_int() - '0'.to_int()
    }
    i += 1
  }
  if exp_negative {
    exponent = -exponent
  }
  let mut first_digit = -1
  let mut first_bit = -1
  for index, digit in digits {
    if first_digit < 0 && digit != 0 {
      first_digit = index
      first_bit = if digit >= 8 {
        3
      } else if digit >= 4 {
        2
      } else if digit >= 2 {
        1
      } else {
        0
      }
    }
  }
  if first_digit < 0 {
    return if negative { -0.0 } else { 0.0 }
  }
  let bit_length = (digits.length() - first_digit - 1) * 4 + first_bit + 1
  // Construct IEEE-754 bits directly: round only once, including subnormals.
  // Guard is a position, not a flag that can be reassigned by later bits.
  let mut top_exponent = exponent - fractional * 4 + bit_length - 1
  let sign : UInt64 = if negative { 0x8000000000000000UL } else { 0UL }
  if top_exponent > 1023 {
    return (sign | 0x7ff0000000000000UL).reinterpret_as_double()
  }
  if top_exponent < -1075 {
    return sign.reinterpret_as_double()
  }
  let precision = if top_exponent >= -1022 { 53 } else { top_exponent + 1075 }
  let mut significand = 0UL
  let mut seen = 0
  let mut guard_bit = false
  let mut sticky = false
  for digit_index in first_digit..<digits.length() {
    let start_bit = if digit_index == first_digit { first_bit } else { 3 }
    for offset in 0..<4 {
      let bit = 3 - offset
      if bit <= start_bit {
        let value = digits[digit_index] / (1 << bit) % 2
        if seen < precision {
          significand = (significand << 1) | value.to_uint64()
        } else if seen == precision {
          guard_bit = value == 1
        } else if value == 1 {
          sticky = true
        }
        seen += 1
      }
    }
  }
  if seen < precision {
    significand = significand << (precision - seen)
  }
  if guard_bit && (sticky || (significand & 1UL) != 0UL) {
    significand += 1UL
  }
  if top_exponent < -1022 {
    // Rounding may promote a subnormal to the smallest normal, whose bit
    // representation is also 1 << 52. Signed zero is preserved as well.
    return (sign | significand).reinterpret_as_double()
  }
  if significand == 0x20000000000000UL {
    significand = significand >> 1
    top_exponent += 1
  }
  if top_exponent > 1023 {
    return (sign | 0x7ff0000000000000UL).reinterpret_as_double()
  }
  (sign |
  ((top_exponent + 1023).to_uint64() << 52) |
  (significand - 0x10000000000000UL)).reinterpret_as_double()
}

///|
fn decimal(text : String) -> Double raise ArffError {
  let trimmed = numeric_text(text)
  let n = trimmed.length()
  if n == 0 {
    raise Invalid("numeric cell requires a value")
  }
  if trimmed == "NaN" || trimmed == "+NaN" || trimmed == "-NaN" {
    return @string.parse_double("NaN") catch { _ => 0.0 }
  }
  if trimmed == "Infinity" || trimmed == "+Infinity" {
    return @double.infinity
  }
  if trimmed == "-Infinity" {
    return @double.neg_infinity
  }
  let mut end = n
  if trimmed[n - 1] == 'f' ||
    trimmed[n - 1] == 'F' ||
    trimmed[n - 1] == 'd' ||
    trimmed[n - 1] == 'D' {
    end -= 1
  }
  if end == 0 {
    raise Invalid("numeric suffix without a value")
  }
  let builder = StringBuilder()
  for i in 0..<end {
    builder.write_char(trimmed[i].unsafe_to_char())
  }
  let body = builder.to_string()
  let sign_offset = if body[0] == 43 || body[0] == 45 { 1 } else { 0 }
  let is_hex = body.length() >= sign_offset + 2 &&
    body[sign_offset] == 48 &&
    (body[sign_offset + 1] == 120 || body[sign_offset + 1] == 88)
  if is_hex {
    return parse_hex_double(body)
  }
  let mut i = if body[0] == 43 || body[0] == 45 { 1 } else { 0 }
  let mut digits = 0
  while i < body.length() && body[i] >= 48 && body[i] <= 57 {
    i += 1
    digits += 1
  }
  if i < body.length() && body[i] == 46 {
    i += 1
    while i < body.length() && body[i] >= 48 && body[i] <= 57 {
      i += 1
      digits += 1
    }
  }
  if digits == 0 {
    raise Invalid("numeric cell requires decimal digits")
  }
  if i < body.length() && (body[i] == 69 || body[i] == 101) {
    i += 1
    if i < body.length() && (body[i] == 43 || body[i] == 45) {
      i += 1
    }
    let exponent_start = i
    while i < body.length() && body[i] >= 48 && body[i] <= 57 {
      i += 1
    }
    if i == exponent_start {
      raise Invalid("numeric exponent requires digits")
    }
  }
  if i != body.length() {
    raise Invalid("invalid numeric value")
  }
  let value = @string.parse_double(body) catch {
    _ => {
      let mut exponent_at = body.length()
      for index in 0..<body.length() {
        if body[index] == 101 || body[index] == 69 {
          exponent_at = index
          break
        }
      }
      if exponent_at == body.length() {
        raise Invalid("invalid numeric value")
      }
      let mut exponent_negative = false
      let mut exponent_start = exponent_at + 1
      if exponent_start < body.length() &&
        (body[exponent_start] == 43 || body[exponent_start] == 45) {
        exponent_negative = body[exponent_start] == 45
        exponent_start += 1
      }
      ignore(exponent_start)
      let mut mantissa_nonzero = false
      for index in 0..<exponent_at {
        if body[index] >= 49 && body[index] <= 57 {
          mantissa_nonzero = true
        }
      }
      if !mantissa_nonzero || exponent_negative {
        0.0
      } else if body[0] == 45 {
        @double.neg_infinity
      } else {
        @double.infinity
      }
    }
  }
  if value == 0.0 && body[0] == 45 {
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
    Numeric => {
      let value = decimal(text)
      if value.is_nan() {
        Missing
      } else {
        Number(value)
      }
    }
    Date(pattern) =>
      DateValue(parse_date_window(text, pattern, budget.date_start))
    Text => Label(text)
    Nominal(labels) => {
      if !labels.contains(text) {
        raise Syntax(token.line, token.column, "value outside nominal domain")
      }
      Label(text)
    }
    Relational(attributes) => {
      // Weka emits compact relational values as unquoted sparse tokens when their
      // nested ARFF representation contains no outer delimiter.
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
    let parsed_weight = decimal(
      require_word(tokens[n - 2], "instance weight required"),
    )
    weight = if parsed_weight.is_nan() { 1.0 } else { parsed_weight }
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
  let schema = reader.schema()
  { schema, rows: resolve_dictionary_zero(schema.attributes, rows), }
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

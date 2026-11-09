///|
/// Always quote user-controlled words; this preserves literal '?' and comment markers.
fn quote_word(text : String) -> String {
  let out = StringBuilder()
  out.write_char('\'')
  for ch in text {
    match ch {
      '\'' => out.write_string("\\'")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      '\u{0008}' => out.write_string("\\b")
      '\u{000C}' => out.write_string("\\f")
      _ => out.write_char(ch)
    }
  }
  out.write_char('\'')
  out.to_string()
}

///|
fn write_header(schema : Schema, out : StringBuilder) -> Unit {
  out.write_string("@relation " + quote_word(schema.relation) + "\n\n")
  for attribute in schema.attributes {
    out.write_string("@attribute " + quote_word(attribute.name) + " ")
    match attribute.kind {
      Numeric => out.write_string("numeric")
      Text => out.write_string("string")
      Nominal(labels) => {
        out.write_char('{')
        for i, label in labels {
          if i > 0 {
            out.write_char(',')
          }
          out.write_string(quote_word(label))
        }
        out.write_char('}')
      }
    }
    out.write_char('\n')
  }
  out.write_string("\n@data\n")
}

///|
fn cell_text(value : Cell) -> String {
  match value {
    Missing => "?"
    Number(n) => n.to_string()
    Label(s) => quote_word(s)
  }
}

///|
/// Deterministic dense ARFF. Schema and every cell are validated before serialization.
pub fn write(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  validate(data, limits~)
  let out = StringBuilder()
  write_header(data.schema, out)
  for row in data.rows {
    for i, cell in row.values {
      if i > 0 {
        out.write_char(',')
      }
      out.write_string(cell_text(cell))
    }
    out.write_char('\n')
  }
  let result = out.to_string()
  if result.length() > limits.max_input {
    raise Limit("serialized output budget")
  }
  result
}

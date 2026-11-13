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
fn write_attributes(
  attributes : Array[Attribute],
  out : BoundedText,
) -> Unit raise ArffError {
  for attribute in attributes {
    out.write_string("@attribute " + quote_word(attribute.name) + " ")
    match attribute.kind {
      Numeric => out.write_string("numeric\n")
      Text => out.write_string("string\n")
      Date(pattern) => out.write_string("date " + quote_word(pattern) + "\n")
      Relational(children) => {
        out.write_string("relational\n")
        write_attributes(children, out)
        out.write_string("@end " + quote_word(attribute.name) + "\n")
      }
      Nominal(labels) => {
        out.write_char('{')
        for i, label in labels {
          if i > 0 {
            out.write_char(',')
          }
          out.write_string(quote_word(label))
        }
        out.write_string("}\n")
      }
    }
  }
}

///|
fn write_header(schema : Schema, out : BoundedText) -> Unit raise ArffError {
  out.write_string("@relation " + quote_word(schema.relation) + "\n\n")
  write_attributes(schema.attributes, out)
  out.write_string("\n@data\n")
}

///|
fn cell_text(
  value : Cell,
  attribute : Attribute,
  limits : Limits,
) -> String raise ArffError {
  match value {
    Missing => "?"
    Number(n) => if n == 0.0 && 1.0 / n < 0.0 { "-0.0" } else { n.to_string() }
    Label(s) => quote_word(s)
    DateValue(n) =>
      match attribute.kind {
        Date(pattern) => quote_word(format_date(n, pattern))
        _ => raise Invalid("date cell schema mismatch")
      }
    Relation(rows) =>
      match attribute.kind {
        Relational(children) => {
          let out = BoundedText::new(limits.max_token)
          for row in rows {
            write_row(children, row, false, out, limits)
          }
          quote_word(out.to_string())
        }
        _ => raise Invalid("relational cell schema mismatch")
      }
  }
}

///|
fn write_row(
  attributes : Array[Attribute],
  row : Record,
  sparse : Bool,
  out : BoundedText,
  limits : Limits,
) -> Unit raise ArffError {
  if sparse {
    out.write_char('{')
  }
  let mut emitted = false
  for i, cell in row.values {
    let omit = sparse &&
      (match (attributes[i].kind, cell) {
        (Numeric, Number(n)) => n == 0.0 && 1.0 / n > 0.0
        (Date(_), DateValue(n)) => n == 0.0
        (Nominal(labels), Label(s)) => s == labels[0]
        _ => false
      })
    if !omit {
      if emitted {
        out.write_char(',')
      }
      if sparse {
        out.write_string(i.to_string() + " ")
      }
      out.write_string(cell_text(cell, attributes[i], limits))
      emitted = true
    }
  }
  if sparse {
    out.write_char('}')
  }
  if row.weight != 1.0 {
    out.write_string(",{" + row.weight.to_string() + "}")
  }
  out.write_char('\n')
}

///|
/// Materialized output; StreamWriter emits one validated record to a sink at a time.
pub fn write(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  validate(data, limits~)
  let out = BoundedText::new(limits.max_input)
  write_header(data.schema, out)
  for row in data.rows {
    write_row(data.schema.attributes, row, false, out, limits)
  }
  out.to_string()
}

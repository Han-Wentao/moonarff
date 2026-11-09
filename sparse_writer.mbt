///|
/// Sparse output omits only semantic defaults. Text cells are always explicit.
pub fn write_sparse(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  validate(data, limits~)
  let out = BoundedText::new(limits.max_input)
  write_header(data.schema, out)
  for row in data.rows {
    out.write_char('{')
    let mut emitted = false
    for i, cell in row.values {
      let omit = match (data.schema.attributes[i].kind, cell) {
        (Numeric, Number(n)) => n == 0.0 && 1.0 / n > 0.0
        (Nominal(labels), Label(s)) => s == labels[0]
        _ => false
      }
      if !omit {
        if emitted {
          out.write_char(',')
        }
        out.write_string(i.to_string() + " " + cell_text(cell))
        emitted = true
      }
    }
    out.write_string("}\n")
  }
  let result = out.to_string()
  if result.length() > limits.max_input {
    raise Limit("serialized output budget")
  }
  result
}

///|
fn csv_field(out : BoundedText, text : String) -> Unit raise ArffError {
  out.write_char('"')
  for ch in text {
    if ch == '"' {
      out.write_char('"')
    }
    out.write_char(ch)
  }
  out.write_char('"')
}

///|
/// Export a machine-oriented numeric CSV; blank cells represent missing values.
/// Headers use positional f0/f1 names. Separate metadata preserves unambiguous names.
/// This is not a spreadsheet sanitization or formula-neutralization API.
pub fn features_csv(
  plan : FeaturePlan,
  batch : FeatureBatch,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  validate_features(plan, batch, limits~)
  let out = BoundedText::new(limits.max_input)
  for j in 0..<plan.width() {
    if j > 0 {
      out.write_char(',')
    }
    out.write_string("f" + j.to_string())
  }
  out.write_string("\r\n")
  for r, row in batch.values {
    for j, value in row {
      if j > 0 {
        out.write_char(',')
      }
      if !batch.missing[r][j] {
        out.write_string(
          cell_text(Number(value), { name: "feature", kind: Numeric, }, limits),
        )
      }
    }
    out.write_string("\r\n")
  }
  out.to_string()
}

///|
/// Export a separate feature dictionary with RFC-style double-quote escaping.
/// The category_present flag distinguishes a numeric feature from an empty label.
pub fn feature_dictionary_csv(
  plan : FeaturePlan,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  limits.check()
  if plan.width() > limits.max_attributes {
    raise Limit("dictionary feature width budget")
  }
  let out = BoundedText::new(limits.max_input)
  out.write_string("feature,attribute,category_present,category\r\n")
  for j, column in plan.columns {
    out.write_string("f" + j.to_string() + ",")
    csv_field(out, column.attribute)
    match column.category {
      None => out.write_string(",false,\"\"")
      Some(label) => {
        out.write_string(",true,")
        csv_field(out, label)
      }
    }
    out.write_string("\r\n")
  }
  out.to_string()
}

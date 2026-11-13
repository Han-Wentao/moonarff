///|
/// Sparse values preserve date epoch defaults, explicit relations and instance weights.
pub fn write_sparse(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> String raise ArffError {
  validate(data, limits~)
  let out = BoundedText::new(limits.max_input)
  write_header(data.schema, out)
  for row in data.rows {
    write_row(data.schema.attributes, row, true, out, limits)
  }
  out.to_string()
}

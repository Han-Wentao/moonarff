///|
/// Rename simultaneously: swaps are legal; collisions are checked on the result.
pub fn rename(
  data : Dataset,
  changes : Map[String, String],
  relation~ : String? = None,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate(data, limits~)
  for old, _ in changes {
    if data.schema.index_of(old) is None {
      raise Invalid("unknown rename source: " + old)
    }
  }
  let attributes = data.schema.attributes.map(fn(attribute) {
    let copied = copy_attribute(attribute)
    {
      name: changes.get(attribute.name).unwrap_or(attribute.name),
      kind: copied.kind,
    }
  })
  let schema = {
    relation: relation.unwrap_or(data.schema.relation),
    attributes,
  }
  validate_schema(schema, limits~)
  { schema, rows: data.rows.map(copy_record), }
}

///|
/// Remap the complete nominal domain bijectively, including unused labels.
/// Partial maps leave unmentioned labels unchanged; any resulting collision fails.
pub fn recode_nominal(
  data : Dataset,
  name : String,
  mapping : Map[String, String],
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate(data, limits~)
  let index = match data.schema.index_of(name) {
    Some(i) => i
    None => raise Invalid("unknown recode column")
  }
  let labels = match data.schema.attributes[index].kind {
    Nominal(labels) => labels
    _ => raise Invalid("recode requires a nominal column")
  }
  for old, _ in mapping {
    if !labels.contains(old) {
      raise Invalid("unknown recode label: " + old)
    }
  }
  let new_labels = labels.map(fn(label) { mapping.get(label).unwrap_or(label) })
  let attributes = data.schema.attributes.map(copy_attribute)
  attributes[index] = { name, kind: Nominal(new_labels), }
  let schema = { relation: data.schema.relation, attributes, }
  validate_schema(schema, limits~)
  let rows = data.rows.map(fn(row) {
    let values = row.values.copy()
    match values[index] {
      Label(label) => values[index] = Label(mapping.get(label).unwrap_or(label))
      _ => ()
    }
    { values, }
  })
  { schema, rows, }
}

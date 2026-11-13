///|
/// Copy mutable domain arrays so downstream edits cannot alter the source schema.
fn copy_attribute(attribute : Attribute) -> Attribute {
  let kind = match attribute.kind {
    Nominal(labels) => Nominal(labels.copy())
    Relational(children) => Relational(children.map(copy_attribute))
    other => other
  }
  { name: attribute.name, kind, }
}

///|
fn copy_schema(schema : Schema) -> Schema {
  {
    relation: schema.relation,
    attributes: schema.attributes.map(copy_attribute),
  }
}

///|
fn copy_record(row : Record) -> Record {
  { weight: row.weight, values: row.values.map(copy_cell), }
}

///|
/// Select and reorder named columns; an empty or duplicate selection is an error.
pub fn project(
  data : Dataset,
  names : Array[String],
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate(data, limits~)
  if names.length() == 0 {
    raise Invalid("projection cannot be empty")
  }
  if names.length() > limits.max_attributes {
    raise Limit("projection attribute budget")
  }
  let indices : Array[Int32] = []
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      raise Invalid("duplicate projected name: " + name)
    }
    seen[name] = true
    match data.schema.index_of(name) {
      Some(i) => indices.push(i)
      None => raise Invalid("unknown projected name: " + name)
    }
  }
  let attributes = indices.map(fn(i) {
    copy_attribute(data.schema.attributes[i])
  })
  let rows = data.rows.map(fn(row) {
    {
      weight: row.weight,
      values: indices.map(fn(i) { copy_cell(row.values[i]) }),
    }
  })
  { schema: { relation: data.schema.relation, attributes, }, rows, }
}

///|
/// Slice rows using a half-open interval, preserving schema and independent arrays.
pub fn slice_rows(
  data : Dataset,
  start : Int32,
  end : Int32,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate(data, limits~)
  if start < 0 || end < start || end > data.rows.length() {
    raise Invalid("invalid half-open row interval")
  }
  let rows = []
  for i = start; i < end; i = i + 1 {
    rows.push(copy_record(data.rows[i]))
  }
  { schema: copy_schema(data.schema), rows, }
}

///|
fn copy_cell(cell : Cell) -> Cell {
  match cell {
    Relation(rows) => Relation(rows.map(copy_record))
    other => other
  }
}

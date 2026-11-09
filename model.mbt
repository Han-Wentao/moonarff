///|
/// Typed schema and row representation; nominal labels retain declaration order.
pub(all) enum AttributeType {
  Numeric
  Nominal(Array[String])
  Text
} derive(Eq, Debug)

///|
pub(all) struct Attribute {
  name : String
  kind : AttributeType
} derive(Eq, Debug)

///|
pub(all) enum Cell {
  Missing
  Number(Double)
  Label(String)
} derive(Eq, Debug)

///|
pub(all) struct Schema {
  relation : String
  attributes : Array[Attribute]
} derive(Eq, Debug)

///|
pub(all) struct Record {
  values : Array[Cell]
} derive(Eq, Debug)

///|
pub(all) struct Dataset {
  schema : Schema
  rows : Array[Record]
} derive(Eq, Debug)

///|
pub(all) suberror ArffError {
  Syntax(Int32, Int32, String)
  Invalid(String)
  Limit(String)
  Unsupported(String)
}

///|
/// Limits count UTF-16 input code units and expanded cells, even for sparse rows.
pub(all) struct Limits {
  max_input : Int32
  max_attributes : Int32
  max_rows : Int32
  max_cells : Int32
  max_token : Int32
}

///|
pub fn Limits::default() -> Limits {
  {
    max_input: 16777216,
    max_attributes: 4096,
    max_rows: 100000,
    max_cells: 1000000,
    max_token: 1048576,
  }
}

///|
fn Limits::check(self : Limits) -> Unit raise ArffError {
  if self.max_input > 268435456 ||
    self.max_attributes > 65536 ||
    self.max_token > 16777216 {
    raise Limit(
      "supported hard caps: input 256 Mi UTF-16 units, attributes 65536, token 16 Mi units",
    )
  }
  if self.max_input < 1 ||
    self.max_attributes < 1 ||
    self.max_rows < 0 ||
    self.max_cells < 0 ||
    self.max_token < 1 {
    raise Limit("limits must be positive (row and cell budgets may be zero)")
  }
}

///|
pub fn Schema::index_of(self : Schema, name : String) -> Int32? {
  for i, attribute in self.attributes {
    if attribute.name == name {
      return Some(i)
    }
  }
  None
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && value != @double.infinity && value != @double.neg_infinity
}

///|
pub fn validate_schema(
  schema : Schema,
  limits~ : Limits = Limits::default(),
) -> Unit raise ArffError {
  limits.check()
  if schema.relation.length() == 0 {
    raise Invalid("empty relation name")
  }
  if schema.attributes.length() == 0 {
    raise Invalid("schema needs at least one attribute")
  }
  if schema.attributes.length() > limits.max_attributes {
    raise Limit("attribute budget")
  }
  let seen : Map[String, Bool] = Map([])
  for attribute in schema.attributes {
    if attribute.name.length() == 0 {
      raise Invalid("empty attribute name")
    }
    if seen.contains(attribute.name) {
      raise Invalid("duplicate attribute: " + attribute.name)
    }
    seen[attribute.name] = true
    match attribute.kind {
      Nominal(labels) => {
        if labels.length() == 0 {
          raise Invalid("empty nominal domain")
        }
        let domain : Map[String, Bool] = Map([])
        for label in labels {
          if domain.contains(label) {
            raise Invalid("duplicate nominal label: " + label)
          }
          domain[label] = true
          if label.length() > limits.max_token {
            raise Limit("nominal token budget")
          }
        }
      }
      _ => ()
    }
    if attribute.name.length() > limits.max_token {
      raise Limit("attribute name budget")
    }
  }
  if schema.relation.length() > limits.max_token {
    raise Limit("relation name budget")
  }
}

///|
pub fn validate_record(schema : Schema, row : Record) -> Unit raise ArffError {
  if row.values.length() != schema.attributes.length() {
    raise Invalid("record width differs from schema")
  }
  for i, cell in row.values {
    match (schema.attributes[i].kind, cell) {
      (_, Missing) => ()
      (Numeric, Number(n)) =>
        if !finite(n) {
          raise Invalid("non-finite numeric cell")
        }
      (Text, Label(_)) => ()
      (Nominal(labels), Label(value)) =>
        if !labels.contains(value) {
          raise Invalid("unknown nominal value: " + value)
        }
      _ =>
        raise Invalid(
          "cell type mismatch at attribute " + schema.attributes[i].name,
        )
    }
  }
}

///|
pub fn validate(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> Unit raise ArffError {
  validate_schema(data.schema, limits~)
  let width = data.schema.attributes.length()
  if data.rows.length() > limits.max_rows ||
    (width > 0 && data.rows.length() > limits.max_cells / width) {
    raise Limit("expanded row/cell budget")
  }
  for row in data.rows {
    validate_record(data.schema, row)
    for cell in row.values {
      if cell is Label(s) && s.length() > limits.max_token {
        raise Limit("cell token budget")
      }
    }
  }
}

///|
pub extend AttributeType with Eq::{equal, not_equal}

///|
pub extend Attribute with Eq::{equal, not_equal}

///|
pub extend Cell with Eq::{equal, not_equal}

///|
pub extend Schema with Eq::{equal, not_equal}

///|
pub extend Record with Eq::{equal, not_equal}

///|
pub extend Dataset with Eq::{equal, not_equal}

///|
pub extend AttributeType with @debug.Debug::{to_repr}

///|
pub extend Attribute with @debug.Debug::{to_repr}

///|
pub extend Cell with @debug.Debug::{to_repr}

///|
pub extend Schema with @debug.Debug::{to_repr}

///|
pub extend Record with @debug.Debug::{to_repr}

///|
pub extend Dataset with @debug.Debug::{to_repr}

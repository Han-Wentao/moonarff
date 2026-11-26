///|
/// Typed schema and row representation; nominal labels retain declaration order.
#derive(Eq, Debug)
pub(all) enum AttributeType {
  Numeric
  Nominal(Array[String])
  Text
  Date(String)
  Relational(Array[Attribute])
}

///|
#derive(Eq, Debug)
pub(all) struct Attribute {
  name : String
  kind : AttributeType
}

///|
#derive(Eq, Debug)
pub(all) enum Cell {
  Missing
  Number(Double)
  Label(String)
  DateValue(Double)
  Relation(Array[Record])
  /// Weka sparse default: dictionary index zero, unresolved until the attribute dictionary is known.
  DictionaryZero
}

///|
#derive(Eq, Debug)
pub(all) struct Schema {
  relation : String
  attributes : Array[Attribute]
}

///|
#derive(Eq, Debug)
pub(all) struct Record {
  values : Array[Cell]
  weight : Double
}

///|
#derive(Eq, Debug)
pub(all) struct Dataset {
  schema : Schema
  rows : Array[Record]
}

///|
/// Resolve Weka dictionary-index-zero references once later explicit values reveal each dictionary.
fn resolve_dictionary_zero(
  attributes : Array[Attribute],
  rows : Array[Record],
) -> Array[Record] {
  let copied = rows.map(fn(row) {
    { values: row.values.copy(), weight: row.weight, }
  })
  // A relational attribute shares child dictionaries across all of its relation values.
  for i, attribute in attributes {
    match attribute.kind {
      Relational(children) => {
        let nested : Array[Record] = []
        let lengths : Array[Int32] = []
        for row in copied {
          match row.values[i] {
            Relation(inner) => {
              lengths.push(inner.length())
              for item in inner {
                nested.push(item)
              }
            }
            _ => lengths.push(-1)
          }
        }
        let resolved = resolve_dictionary_zero(children, nested)
        let mut offset = 0
        for r in 0..<copied.length() {
          if lengths[r] >= 0 {
            let inner = []
            for _ in 0..<lengths[r] {
              inner.push(resolved[offset])
              offset += 1
            }
            copied[r].values[i] = Relation(inner)
          }
        }
      }
      _ => ()
    }
  }
  for i, attribute in attributes {
    match attribute.kind {
      Text | Relational(_) => {
        let mut first : Cell? = None
        for row in copied {
          match row.values[i] {
            DictionaryZero | Missing => ()
            value => if first is None { first = Some(value) }
          }
        }
        match first {
          Some(value) =>
            for row in copied {
              if row.values[i] is DictionaryZero {
                row.values[i] = value
              }
            }
          None => ()
        }
      }
      _ => ()
    }
  }
  copied
}

///|
/// Resolve sparse String/Relational index-zero cells after all streamed rows are known.
///
/// StreamReader emits `DictionaryZero` when the first explicit dictionary value may
/// appear later. Retain those records, then call this once the stream is complete.
/// The returned records are copied; the caller's streamed records are not mutated.
pub fn resolve_dictionary_defaults(
  schema : Schema,
  rows : Array[Record],
  limits~ : Limits = Limits::default(),
) -> Array[Record] raise ArffError {
  // Validate the whole graph before traversing by schema index. Share the
  // recursive budgets so malformed or oversized caller-owned records fail as
  // ArffError instead of trapping, including nested relational records.
  validate({ schema, rows, }, limits~)
  resolve_dictionary_zero(schema.attributes, rows)
}

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
  if schema.relation.length() == 0 ||
    schema.relation.length() > limits.max_token {
    raise Invalid("invalid relation name")
  }
  let budget = FormatBudget::new(limits)
  validate_attributes(schema.attributes, budget, 0)
}

///|
priv struct FormatBudget {
  date_start : Double
  limits : Limits
  mut attributes : Int32
  mut rows : Int32
  mut cells : Int32
}

///|
fn FormatBudget::new(limits : Limits) -> FormatBudget {
  {
    limits,
    date_start: date_century_start(),
    attributes: 0,
    rows: 0,
    cells: 0,
  }
}

///|
fn validate_attributes(
  attributes : Array[Attribute],
  budget : FormatBudget,
  depth : Int32,
) -> Unit raise ArffError {
  if depth > 16 {
    raise Limit("relational nesting depth exceeds 16")
  }
  if attributes.is_empty() {
    raise Invalid("schema needs at least one attribute")
  }
  if attributes.length() > budget.limits.max_attributes - budget.attributes {
    raise Limit("total nested attribute budget")
  }
  budget.attributes += attributes.length()
  let seen : Map[String, Bool] = Map([])
  for attribute in attributes {
    if attribute.name.is_empty() ||
      attribute.name.length() > budget.limits.max_token {
      raise Invalid("invalid attribute name")
    }
    if seen.contains(attribute.name) {
      raise Invalid("duplicate attribute: " + attribute.name)
    }
    seen[attribute.name] = true
    match attribute.kind {
      Nominal(labels) => {
        if labels.is_empty() {
          raise Invalid("empty nominal domain")
        }
        let domain : Map[String, Bool] = Map([])
        for label in labels {
          if domain.contains(label) {
            raise Invalid("duplicate nominal label: " + label)
          }
          if label.length() > budget.limits.max_token {
            raise Limit("nominal token budget")
          }
          domain[label] = true
        }
      }
      Date(pattern) => ignore(date_parts(pattern))
      Relational(children) => validate_attributes(children, budget, depth + 1)
      _ => ()
    }
  }
}

///|
fn validate_row(
  attributes : Array[Attribute],
  row : Record,
  budget : FormatBudget,
  depth : Int32,
) -> Unit raise ArffError {
  if depth > 16 {
    raise Limit("relational nesting depth exceeds 16")
  }
  if row.values.length() != attributes.length() {
    raise Invalid("record width differs from schema")
  }
  if row.weight.is_nan() {
    raise Invalid("instance weight cannot be NaN")
  }
  if budget.rows >= budget.limits.max_rows ||
    attributes.length() > budget.limits.max_cells - budget.cells {
    raise Limit("total nested row/cell budget")
  }
  budget.rows += 1
  budget.cells += attributes.length()
  for i, cell in row.values {
    match (attributes[i].kind, cell) {
      (_, Missing) => ()
      (Numeric, Number(n)) =>
        if n.is_nan() {
          raise Invalid("numeric NaN must be represented as missing")
        }
      (Date(pattern), DateValue(n)) => ignore(format_date(n, pattern))
      (Text, DictionaryZero) => ()
      (Relational(_), DictionaryZero) => ()
      (Text, Label(s)) =>
        if s.length() > budget.limits.max_token {
          raise Limit("text token budget")
        }
      (Nominal(labels), Label(s)) =>
        if !labels.contains(s) {
          raise Invalid("unknown nominal value")
        }
      (Relational(children), Relation(rows)) =>
        for child in rows {
          validate_row(children, child, budget, depth + 1)
        }
      _ =>
        raise Invalid("cell type mismatch at attribute " + attributes[i].name)
    }
  }
}

///|
pub fn validate_record(schema : Schema, row : Record) -> Unit raise ArffError {
  validate_schema(schema)
  validate_row(schema.attributes, row, FormatBudget::new(Limits::default()), 0)
}

///|
pub fn validate(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> Unit raise ArffError {
  validate_schema(data.schema, limits~)
  let budget = FormatBudget::new(limits)
  for row in data.rows {
    validate_row(data.schema.attributes, row, budget, 0)
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

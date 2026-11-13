///|
/// Feature columns carry separate attribute/category fields to avoid name collisions.
pub(all) struct FeatureColumn {
  attribute : String
  category : String?
} derive(Eq, Debug)

///|
/// A fitted plan owns a snapshot of ordered domains, independent of later mutations.
pub struct FeaturePlan {
  priv schema : Schema
  priv columns : Array[FeatureColumn]
  priv offsets : Array[Int32]
}

///|
pub fn FeaturePlan::width(self : FeaturePlan) -> Int32 {
  self.columns.length()
}

///|
pub fn FeaturePlan::columns(self : FeaturePlan) -> Array[FeatureColumn] {
  self.columns.copy()
}

///|
pub fn FeaturePlan::schema(self : FeaturePlan) -> Schema {
  copy_schema(self.schema)
}

///|
/// Fit numeric passthrough and full nominal one-hot columns from the declared schema.
/// Unobserved labels remain features; text must first be projected out explicitly.
pub fn fit_features(
  schema : Schema,
  limits~ : Limits = Limits::default(),
) -> FeaturePlan raise ArffError {
  validate_schema(schema, limits~)
  let columns = []
  let offsets = []
  for attribute in schema.attributes {
    offsets.push(columns.length())
    match attribute.kind {
      Numeric | Date(_) => {
        if columns.length() >= limits.max_attributes {
          raise Limit("feature width budget")
        }
        columns.push({ attribute: attribute.name, category: None, })
      }
      Nominal(labels) => {
        if labels.length() > limits.max_attributes - columns.length() {
          raise Limit("one-hot feature width budget")
        }
        for label in labels {
          columns.push({ attribute: attribute.name, category: Some(label), })
        }
      }
      Text | Relational(_) =>
        raise Unsupported(
          "feature encoding requires explicit exclusion of string/relational columns",
        )
    }
  }
  { schema: copy_schema(schema), columns, offsets, }
}

///|
pub extend FeatureColumn with Eq::{equal, not_equal}

///|
pub extend FeatureColumn with @debug.Debug::{to_repr}

///|
/// Half-open feature range belonging to one input column.
pub fn FeaturePlan::range(
  self : FeaturePlan,
  name : String,
) -> (Int32, Int32) raise ArffError {
  let index = match self.schema.index_of(name) {
    Some(i) => i
    None => raise Invalid("unknown feature attribute")
  }
  let end = if index + 1 == self.offsets.length() {
    self.width()
  } else {
    self.offsets[index + 1]
  }
  (self.offsets[index], end)
}

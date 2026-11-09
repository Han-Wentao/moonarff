///|
/// Values use zero for missing cells only in conjunction with an explicit mask.
/// Each nominal feature group repeats its source missing bit across the group.
pub(all) struct FeatureBatch {
  values : Array[Array[Double]]
  missing : Array[Array[Bool]]
} derive(Eq, Debug)

///|
fn compatible_features(
  plan : FeaturePlan,
  schema : Schema,
) -> Unit raise ArffError {
  if plan.schema.attributes != schema.attributes {
    raise Invalid(
      "feature plan requires identical ordered attribute names, types and domains",
    )
  }
}

///|
/// Encode without fitting on rows. Relation names may differ; column contracts may not.
pub fn encode_features(
  plan : FeaturePlan,
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> FeatureBatch raise ArffError {
  validate(data, limits~)
  compatible_features(plan, data.schema)
  let width = plan.width()
  if width > limits.max_attributes ||
    data.rows.length() > limits.max_cells / width {
    raise Limit("encoded feature cell budget")
  }
  let values = []
  let missing = []
  for row in data.rows {
    let encoded = Array::make(width, 0.0)
    let mask = Array::make(width, false)
    for i, cell in row.values {
      let start = plan.offsets[i]
      let end = if i + 1 == plan.offsets.length() {
        width
      } else {
        plan.offsets[i + 1]
      }
      match cell {
        Missing =>
          for j = start; j < end; j = j + 1 {
            mask[j] = true
          }
        Number(n) => encoded[start] = n
        Label(label) =>
          match plan.schema.attributes[i].kind {
            Nominal(labels) =>
              for j, candidate in labels {
                if candidate == label {
                  encoded[start + j] = 1.0
                }
              }
            _ => raise Invalid("feature plan does not encode text")
          }
      }
    }
    values.push(encoded)
    missing.push(mask)
  }
  { values, missing, }
}

///|
/// Validate external feature matrices before decoding/exporting them.
pub fn validate_features(
  plan : FeaturePlan,
  batch : FeatureBatch,
  limits~ : Limits = Limits::default(),
) -> Unit raise ArffError {
  limits.check()
  let width = plan.width()
  if width > limits.max_attributes ||
    batch.values.length() > limits.max_rows ||
    batch.values.length() > limits.max_cells / width {
    raise Limit("feature matrix budget")
  }
  if batch.values.length() != batch.missing.length() {
    raise Invalid("feature mask row count differs")
  }
  for r, row in batch.values {
    if row.length() != width || batch.missing[r].length() != width {
      raise Invalid("feature matrix width differs")
    }
    for j, value in row {
      if !finite(value) {
        raise Invalid("feature matrix contains non-finite values")
      }
      if batch.missing[r][j] && value != 0.0 {
        raise Invalid("masked features must use zero payload")
      }
    }
    for i, attribute in plan.schema.attributes {
      let start = plan.offsets[i]
      match attribute.kind {
        Nominal(labels) => {
          let mut active = 0
          for j = start; j < start + labels.length(); j = j + 1 {
            if batch.missing[r][j] != batch.missing[r][start] {
              raise Invalid("inconsistent missing bits in nominal group")
            }
            if row[j] == 1.0 {
              active += 1
            } else if row[j] != 0.0 {
              raise Invalid("nominal features must be zero or one")
            }
          }
          if !batch.missing[r][start] && active != 1 {
            raise Invalid(
              "nonmissing nominal group requires exactly one active feature",
            )
          }
        }
        _ => ()
      }
    }
  }
}

///|
pub extend FeatureBatch with Eq::{equal, not_equal}

///|
pub extend FeatureBatch with @debug.Debug::{to_repr}

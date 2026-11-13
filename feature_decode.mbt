///|
/// Reconstruct typed records from a validated matrix and the fitted schema snapshot.
/// A one-hot matrix without its plan or missing mask is insufficient for this operation.
pub fn decode_features(
  plan : FeaturePlan,
  batch : FeatureBatch,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate_features(plan, batch, limits~)
  let rows = []
  for r, encoded in batch.values {
    let values = []
    for i, attribute in plan.schema.attributes {
      let start = plan.offsets[i]
      let cell = if batch.missing[r][start] {
        Missing
      } else {
        match attribute.kind {
          Numeric => Number(encoded[start])
          Date(_) => DateValue(encoded[start])
          Nominal(labels) => {
            let mut selected = 0
            for j, _ in labels {
              if encoded[start + j] == 1.0 {
                selected = j
              }
            }
            Label(labels[selected])
          }
          Text | Relational(_) =>
            raise Unsupported("feature plan cannot contain string columns")
        }
      }
      values.push(cell)
    }
    rows.push({ values, weight: 1.0, })
  }
  let result = { schema: copy_schema(plan.schema), rows, }
  validate(result, limits~)
  result
}

///|
/// Concatenate compatible datasets. Nominal unions must be explicitly enabled.
/// Domain union order is left-first, then previously unseen right labels.
pub fn concatenate(
  left : Dataset,
  right : Dataset,
  union_domains~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> Dataset raise ArffError {
  validate(left, limits~)
  validate(right, limits~)
  let width = left.schema.attributes.length()
  if width != right.schema.attributes.length() {
    raise Invalid("concatenate schema width differs")
  }
  if right.rows.length() > limits.max_rows - left.rows.length() ||
    right.rows.length() > limits.max_cells / width - left.rows.length() {
    raise Limit("concatenate row/cell budget")
  }
  let attributes = []
  for i, a in left.schema.attributes {
    let b = right.schema.attributes[i]
    if a.name != b.name {
      raise Invalid("concatenate column order or names differ")
    }
    let kind = match (a.kind, b.kind) {
      (Numeric, Numeric) => Numeric
      (Text, Text) => Text
      (Date(a), Date(b)) =>
        if a == b {
          Date(a)
        } else {
          raise Invalid("date formats differ")
        }
      (Relational(a), Relational(b)) =>
        if a == b {
          Relational(a.map(copy_attribute))
        } else {
          raise Invalid("nested relation schemas differ")
        }
      (Nominal(xs), Nominal(ys)) => {
        if !union_domains && xs != ys {
          raise Invalid(
            "nominal declaration order differs; explicit union required",
          )
        }
        let labels = xs.copy()
        let seen : Map[String, Bool] = Map([])
        for x in xs {
          seen[x] = true
        }
        for y in ys {
          if !seen.contains(y) {
            labels.push(y)
            seen[y] = true
          }
        }
        Nominal(labels)
      }
      _ => raise Invalid("concatenate column types differ")
    }
    attributes.push({ name: a.name, kind, })
  }
  let rows = left.rows.map(copy_record)
  for row in right.rows {
    rows.push(copy_record(row))
  }
  let result = {
    schema: { relation: left.schema.relation, attributes, },
    rows,
  }
  validate(result, limits~)
  result
}

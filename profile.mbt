///|
/// Numeric summaries exclude missing values; variance uses the sample denominator.
pub(all) struct NumericSummary {
  count : Int32
  missing : Int32
  minimum : Double?
  maximum : Double?
  mean : Double?
  sample_variance : Double?
} derive(Eq, Debug)

///|
pub(all) struct CategoryCount {
  label : String
  count : Int32
} derive(Eq, Debug)

///|
pub(all) enum ColumnSummary {
  NumericProfile(NumericSummary)
  NominalProfile(Int32, Array[CategoryCount])
  TextProfile(Int32, Int32, Int32)
} derive(Eq, Debug)

///|
pub(all) struct Profile {
  rows : Int32
  columns : Array[ColumnSummary]
} derive(Eq, Debug)

///|
fn numeric_summary(
  rows : Array[Record],
  index : Int32,
) -> NumericSummary raise ArffError {
  let mut count = 0
  let mut missing = 0
  let mut minimum = @double.infinity
  let mut maximum = @double.neg_infinity
  let mut mean = 0.0
  let mut m2 = 0.0
  for row in rows {
    match row.values[index] {
      Missing => missing += 1
      Number(x) => {
        count += 1
        if x < minimum {
          minimum = x
        }
        if x > maximum {
          maximum = x
        }
        if count == 1 {
          mean = x
        } else {
          let old = mean
          let n = count.to_double()
          mean = old * ((n - 1.0) / n) + x / n
          m2 += (x - old) * (x - mean)
          if !finite(mean) || !finite(m2) {
            raise Invalid(
              "numeric profile overflow; values exceed finite summary range",
            )
          }
        }
      }
      _ => raise Invalid("numeric profile received a nonnumeric cell")
    }
  }
  {
    count,
    missing,
    minimum: if count == 0 {
      None
    } else {
      Some(minimum)
    },
    maximum: if count == 0 {
      None
    } else {
      Some(maximum)
    },
    mean: if count == 0 {
      None
    } else {
      Some(mean)
    },
    sample_variance: if count < 2 {
      None
    } else {
      Some(m2 / (count - 1).to_double())
    },
  }
}

///|
/// Summarize all columns without imputing missing data or discarding unused labels.
/// Text profile stores (missing, present, maximum UTF-16 length), not raw text.
pub fn profile(
  data : Dataset,
  limits~ : Limits = Limits::default(),
) -> Profile raise ArffError {
  validate(data, limits~)
  let columns = []
  for i, attribute in data.schema.attributes {
    let summary = match attribute.kind {
      Numeric => NumericProfile(numeric_summary(data.rows, i))
      Nominal(labels) => {
        let counts : Map[String, Int32] = Map([])
        let mut missing = 0
        for row in data.rows {
          match row.values[i] {
            Missing => missing += 1
            Label(s) => counts[s] = counts.get(s).unwrap_or(0) + 1
            _ => raise Invalid("nominal profile type mismatch")
          }
        }
        NominalProfile(
          missing,
          labels.map(fn(label) {
            { label, count: counts.get(label).unwrap_or(0), }
          }),
        )
      }
      Text => {
        let mut missing = 0
        let mut present = 0
        let mut longest = 0
        for row in data.rows {
          match row.values[i] {
            Missing => missing += 1
            Label(s) => {
              present += 1
              if s.length() > longest {
                longest = s.length()
              }
            }
            _ => raise Invalid("text profile type mismatch")
          }
        }
        TextProfile(missing, present, longest)
      }
    }
    columns.push(summary)
  }
  { rows: data.rows.length(), columns, }
}

///|
pub extend NumericSummary with Eq::{equal, not_equal}

///|
pub extend CategoryCount with Eq::{equal, not_equal}

///|
pub extend ColumnSummary with Eq::{equal, not_equal}

///|
pub extend Profile with Eq::{equal, not_equal}

///|
pub extend NumericSummary with @debug.Debug::{to_repr}

///|
pub extend CategoryCount with @debug.Debug::{to_repr}

///|
pub extend ColumnSummary with @debug.Debug::{to_repr}

///|
pub extend Profile with @debug.Debug::{to_repr}

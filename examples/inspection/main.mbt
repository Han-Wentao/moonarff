///|
/// Evaluation/teaching: incrementally inspect sparse rows, then verify profiles.
fn main {
  let source = "@relation sparse\n@attribute score numeric\n@attribute class {negative,positive,unseen}\n@data\n{}\n{0 2,1 positive}\n{0 ?,1 ?}\n"
  let reader = @arff.Reader::new(source) catch { _ => panic() }
  let mut count = 0
  let mut missing = 0
  while (reader.next() catch { _ => panic() }) is Some(row) {
    count += 1
    if row.values[0] == @arff.Missing {
      missing += 1
    }
  }
  assert_eq(count, 3) catch {
    _ => panic()
  }
  assert_eq(missing, 1) catch {
    _ => panic()
  }
  let data = @arff.parse(source) catch { _ => panic() }
  let summary = @arff.profile(data) catch { _ => panic() }
  match summary.columns[0] {
    @arff.NumericProfile(s) => {
      assert_eq(s.mean, Some(1.0)) catch {
        _ => panic()
      }
      assert_eq(s.sample_variance, Some(2.0)) catch {
        _ => panic()
      }
    }
    _ => panic()
  }
  match summary.columns[1] {
    @arff.NominalProfile(n, counts) => {
      assert_eq(n, 1) catch {
        _ => panic()
      }
      assert_eq(counts[2].count, 0) catch {
        _ => panic()
      }
    }
    _ => panic()
  }
  println(
    "inspection: PASS; sparse defaults, missing counts, sample variance, unused domain",
  )
}

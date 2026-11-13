///|
/// Multi-instance exchange: dates at bag level, weighted child instances, empty versus missing bags.
fn main {
  let source = "@relation observations\n@attribute day date 'yyyy-MM-dd'\n@attribute samples relational\n@attribute value numeric\n@attribute state {ok,bad,unseen}\n@end samples\n@data\n2024-02-29,'1,ok,{0.25}\\n2,bad,{-0.5}',{2}\n1970-01-01,''\n?,?\n"
  let data = @arff.parse(source) catch { _ => panic() }
  let reordered = @arff.project(data, ["samples", "day"]) catch { _ => panic() }
  let sparse = @arff.write_sparse(reordered) catch { _ => panic() }
  let decoded = @arff.parse(sparse) catch { _ => panic() }
  assert_eq(decoded, reordered) catch {
    _ => panic()
  }
  assert_eq(decoded.rows[0].weight, 2.0) catch {
    _ => panic()
  }
  match decoded.rows[0].values[0] {
    @arff.Relation(rows) => {
      assert_eq(rows.length(), 2) catch {
        _ => panic()
      }
      assert_eq(rows[0].weight, 0.25) catch {
        _ => panic()
      }
    }
    _ => panic()
  }
  assert_eq(decoded.rows[1].values[0], @arff.Relation([])) catch {
    _ => panic()
  }
  assert_eq(decoded.rows[2].values[0], @arff.Missing) catch {
    _ => panic()
  }
  let summary = @arff.profile(decoded) catch { _ => panic() }
  match summary.columns[0] {
    @arff.RelationalProfile(missing, present, children) =>
      assert_eq([missing, present, children], [1, 2, 2]) catch {
        _ => panic()
      }
    _ => panic()
  }
  println(
    "relational: PASS; dated bags, weighted nested instances, projection, sparse interchange, profiles",
  )
}

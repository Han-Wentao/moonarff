///|
/// Curation: combine independently declared categories, recode and reorder, round trip.
fn main {
  let first = @arff.parse(
    "@relation first\n@attribute id numeric\n@attribute status {yes,no}\n@data\n1,yes\n2,?\n",
  ) catch {
    _ => panic()
  }
  let second = @arff.parse(
    "@relation second\n@attribute id numeric\n@attribute status {no,unknown,yes}\n@data\n3,unknown\n",
  ) catch {
    _ => panic()
  }
  let merged = @arff.concatenate(first, second, union_domains=true) catch {
    _ => panic()
  }
  let coded = @arff.recode_nominal(
    merged,
    "status",
    Map([("yes", "ok"), ("no", "bad")]),
  ) catch {
    _ => panic()
  }
  let selected = @arff.project(coded, ["status", "id"]) catch { _ => panic() }
  let curated = @arff.rename(
    selected,
    Map([("status", "result")]),
    relation=Some("curated"),
  ) catch {
    _ => panic()
  }
  let text = @arff.write_sparse(curated) catch { _ => panic() }
  let restored = @arff.parse(text) catch { _ => panic() }
  assert_eq(restored, curated) catch {
    _ => panic()
  }
  assert_eq(restored.rows.length(), 3) catch {
    _ => panic()
  }
  assert_eq(restored.rows[1].values[0], @arff.Missing) catch {
    _ => panic()
  }
  println(text)
  println(
    "curation: PASS; domain union, recode, reorder, rename, sparse round trip",
  )
}

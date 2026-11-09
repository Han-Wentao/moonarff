///|
/// ML ingestion: preserve held-out domains, encode missing masks, export and reconstruct.
fn main {
  let source = "@relation training\n@attribute length numeric\n@attribute color {red,blue,green}\n@attribute note string\n@data\n1,red,'sample a'\n?,blue,'sample b'\n3,?,'sample c'\n"
  let data = @arff.parse(source) catch { _ => panic() }
  let features = @arff.project(data, ["length", "color"]) catch { _ => panic() }
  let plan = @arff.fit_features(features.schema) catch { _ => panic() }
  let encoded = @arff.encode_features(plan, features) catch { _ => panic() }
  assert_eq(plan.width(), 4) catch {
    _ => panic()
  }
  assert_eq(encoded.missing[1][0], true) catch {
    _ => panic()
  }
  assert_eq(encoded.values[0][3], 0.0) catch {
    _ => panic()
  }
  let restored = @arff.decode_features(plan, encoded) catch { _ => panic() }
  assert_eq(restored, features) catch {
    _ => panic()
  }
  let csv = @arff.features_csv(plan, encoded) catch { _ => panic() }
  assert_true(csv.contains("f0,f1,f2,f3")) catch {
    _ => panic()
  }
  println(csv)
  println("ingestion: PASS; 3 rows, 4 features, explicit missing masks")
}

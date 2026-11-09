///|
test "profiles preserve empty nominal categories and missing counts" {
  let data = parse(
    "@relation r\n@attribute x numeric\n@attribute c {a,b,z}\n@attribute t string\n@data\n1,a,'hi'\n2,b,''\n3,a,?\n?,?,?\n",
  )
  let result = profile(data)
  match result.columns[0] {
    NumericProfile(s) => {
      assert_eq(s.count, 3)
      assert_eq(s.missing, 1)
      assert_eq(s.mean, Some(2.0))
      assert_eq(s.sample_variance, Some(1.0))
    }
    _ => fail("numeric summary")
  }
  match result.columns[1] {
    NominalProfile(missing, counts) => {
      assert_eq(missing, 1)
      assert_eq(counts[2].count, 0)
      assert_eq(counts[0].count, 2)
    }
    _ => fail("nominal summary")
  }
  assert_eq(result.columns[2], TextProfile(2, 2, 2))
}

///|
test "profile empty and overflowing numeric columns are explicit" {
  let data = parse("@relation r\n@attribute x numeric\n@data\n?\n")
  match profile(data).columns[0] {
    NumericProfile(s) => {
      assert_eq(s.mean, None)
      assert_eq(s.sample_variance, None)
    }
    _ => fail("numeric")
  }
  let extreme = parse(
    "@relation r\n@attribute x numeric\n@data\n1e308\n-1e308\n",
  )
  let rejected = try {
    let _ = profile(extreme)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

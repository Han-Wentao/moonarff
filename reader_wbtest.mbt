///|
test "dense rows distinguish literal question mark and missing" {
  let d = parse(
    "@relation r\n@attribute x real\n@attribute c {'?',yes}\n@data\n1e2,'?' % comment\n?,yes\n",
  )
  assert_eq(d.rows.length(), 2)
  assert_true(d.rows[0].values == [Number(100.0), Label("?")])
  assert_true(d.rows[1].values == [Missing, Label("yes")])
}

///|
test "dense rows reject malformed widths numbers and domains" {
  let h = "@relation r\n@attribute x numeric\n@attribute c {yes,no}\n@data\n"
  for row in ["1,unknown", "1", "1,yes,2", "1e,yes", "0x12,yes", ",yes", "1,,"] {
    assert_true(
      try {
        ignore(parse(h + row))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "incremental reader EOF and row budget" {
  let r = Reader::new("@relation r\n@attribute x numeric\n@data\n1\n")
  assert_true(r.next() is Some(_))
  assert_true(r.next() is None)
  assert_true(r.next() is None)
  let limits = Limits::{
    max_input: 1024,
    max_attributes: 4,
    max_rows: 0,
    max_cells: 4,
    max_token: 128,
  }
  assert_true(
    try {
      ignore(parse("@relation r\n@attribute x numeric\n@data\n1", limits~))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "stream dictionary-zero references resolve after later values without mutating callbacks" {
  let schema = Schema::{
    relation: "streamed",
    attributes: [
      { name: "text", kind: Text, },
      { name: "bag", kind: Relational([{ name: "label", kind: Text, }]), },
    ],
  }
  let streamed = [
    {
      weight: 1.0,
      values: [
        DictionaryZero,
        Relation([{ weight: 1.0, values: [DictionaryZero], }]),
      ],
    },
    {
      weight: 1.0,
      values: [
        Label("first"),
        Relation([{ weight: 1.0, values: [Label("nested-first")], }]),
      ],
    },
  ]
  let resolved = resolve_dictionary_defaults(schema, streamed)
  assert_eq(resolved[0].values[0], Label("first"))
  assert_eq(
    resolved[0].values[1],
    Relation([{ weight: 1.0, values: [Label("nested-first")], }]),
  )
  assert_eq(streamed[0].values[0], DictionaryZero)
  assert_eq(
    streamed[0].values[1],
    Relation([{ weight: 1.0, values: [DictionaryZero], }]),
  )
}

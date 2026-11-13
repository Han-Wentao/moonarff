///|
test "stream UTF8 every byte CRLF backpressure and relational values" {
  let source = "@relation r\r\n@attribute d date 'yyyy-MM-dd'\r\n@attribute note string\r\n@data\r\n'2024-02-29','中文😀',{2.5}\r\n?,?"
  let expected = parse(source)
  let stream = StreamReader::new()
  let rows : Array[Record] = []
  let bytes = @utf8.encode(source)
  for byte in bytes {
    stream.feed_utf8([byte], fn(row) { rows.push(row) })
  }
  assert_eq(rows.length(), 1)
  stream.finish(fn(row) { rows.push(row) })
  stream.finish(fn(_) raise ArffError {
    raise Invalid("EOF must be idempotent")
  })
  assert_eq(rows, expected.rows)
  assert_eq(stream.schema(), Some(expected.schema))
  assert_eq(stream.buffered_units(), 0)
}

///|
test "stream every text split matches whole reader" {
  let source = "@relation r\n@attribute a relational\n@attribute x numeric\n@attribute s string\n@end a\n@data\n'1,\\\"it\\\\\\\'s\\\"\\n2,hi',{3}\n''\n?\n"
  let expected = parse(source)
  for cut = 0; cut <= source.length(); cut = cut + 1 {
    let stream = StreamReader::new()
    let rows : Array[Record] = []
    stream.feed(source[:cut].to_owned(), fn(row) { rows.push(row) })
    stream.feed(source[cut:].to_owned(), fn(row) { rows.push(row) })
    stream.finish(fn(row) { rows.push(row) })
    assert_eq(rows, expected.rows)
  }
}

///|
test "stream total input is not retained and frame budgets are enforced" {
  let limits = Limits::{ ..Limits::default(), max_input: 128, max_token: 32, }
  let stream = StreamReader::new(limits~)
  let mut count = 0
  stream.feed("@relation r\n@attribute n numeric\n@data\n", fn(_) { count += 1 })
  for _ in 0..<1000 {
    stream.feed("1\n", fn(_) { count += 1 })
    assert_eq(stream.buffered_units(), 0)
  }
  stream.finish(fn(_) { count += 1 })
  assert_eq(count, 1000)
  let broken = StreamReader::new(limits~)
  assert_true(
    try {
      for _ in 0..<129 {
        broken.feed("x", fn(_) { () })
      }
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      broken.finish(fn(_) { () })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "stream rejects invalid truncated UTF8 and terminal callback failure" {
  for
    bytes in [
      b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\x80", b"\xe4\xb8",
    ] {
    let stream = StreamReader::new()
    assert_true(
      try {
        stream.feed_utf8(bytes, fn(_) { () })
        stream.finish(fn(_) { () })
        false
      } catch {
        _ => true
      },
    )
  }
  let stream = StreamReader::new()
  assert_true(
    try {
      stream.feed("@relation r\n@attribute n numeric\n@data\n1\n", fn(
        _,
      ) raise ArffError {
        raise Invalid("sink failed")
      })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      stream.feed("2\n", fn(_) { () })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "stream writer emits immediately and snapshots schema" {
  let d = parse(
    "@relation r\n@attribute n numeric\n@attribute day date 'yyyy-MM-dd'\n@data\n1,'2024-02-29',{2.5}\n?,?\n",
  )
  for sparse in [false, true] {
    let pieces : Array[String] = []
    let writer = StreamWriter::new(
      d.schema,
      fn(piece) { pieces.push(piece) },
      sparse~,
    )
    assert_eq(pieces.length(), 1)
    for row in d.rows {
      let before = pieces.length()
      writer.write(row)
      assert_eq(pieces.length(), before + 1)
    }
    writer.finish()
    writer.finish()
    let text = StringBuilder()
    for piece in pieces {
      text.write_string(piece)
    }
    assert_eq(parse(text.to_string()), d)
    assert_true(
      try {
        writer.write(d.rows[0])
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "writer failure is terminal and never emits an invalid partial record" {
  let schema = read_schema("@relation r\n@attribute n numeric\n@data\n")
  let pieces : Array[String] = []
  let writer = StreamWriter::new(schema, fn(s) { pieces.push(s) })
  assert_true(
    try {
      writer.write({ values: [Label("bad")], weight: 1.0, })
      false
    } catch {
      _ => true
    },
  )
  assert_eq(pieces.length(), 1)
  assert_true(
    try {
      writer.write({ values: [Number(1.0)], weight: 1.0, })
      false
    } catch {
      _ => true
    },
  )
  let mut calls = 0
  let writer = StreamWriter::new(schema, fn(_) raise ArffError {
    calls += 1
    if calls > 1 {
      raise Invalid("transport failed")
    }
  })
  assert_true(
    try {
      writer.write({ values: [Number(1.0)], weight: 1.0, })
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      writer.finish()
      false
    } catch {
      _ => true
    },
  )
  assert_eq(calls, 2)
}

///|
test "stream schema snapshots and cumulative nested row budgets" {
  let source = "@relation r\n@attribute bag relational\n@attribute n numeric\n@end bag\n@data\n"
  let reader = StreamReader::new()
  reader.feed(source, fn(_) { () })
  match reader.schema() {
    Some(s) => s.attributes[0] = { name: "wrong", kind: Text, }
    None => fail("header expected")
  }
  let rows : Array[Record] = []
  reader.feed("'1\\n2'\n", fn(r) { rows.push(r) })
  assert_eq(rows[0].values, [
    Relation([
      { values: [Number(1.0)], weight: 1.0, },
      { values: [Number(2.0)], weight: 1.0, },
    ]),
  ])
  let limits = Limits::{ ..Limits::default(), max_rows: 2, }
  let reader = StreamReader::new(limits~)
  reader.feed(source, fn(_) { () })
  assert_true(
    try {
      reader.feed("'1\\n2'\n", fn(_) { () })
      false
    } catch {
      _ => true
    },
  )
}

///|
test "stream reentrancy and mixed incomplete UTF8 rejected" {
  let reader = StreamReader::new()
  assert_true(
    try {
      reader.feed("@relation r\n@attribute n numeric\n@data\n1\n", fn(
        _,
      ) raise ArffError {
        reader.finish(fn(_) { () })
      })
      false
    } catch {
      _ => true
    },
  )
  let reader = StreamReader::new()
  reader.feed_utf8(b"\xe4", fn(_) { () })
  assert_true(
    try {
      reader.feed("x", fn(_) { () })
      false
    } catch {
      _ => true
    },
  )
}

///|
/// Simulated byte transport; replace the loop with file/socket chunks, retain the same callbacks.
fn main {
  let source = "@relation events\r\n@attribute at date\r\n@attribute note string\r\n@data\r\n1970-01-01T00:00:00,'中文😀',{2.5}\r\n?,?\r\n"
  let reader = @arff.StreamReader::new() catch { _ => panic() }
  let mut writer : @arff.StreamWriter? = None
  let sink = StringBuilder()
  let mut count = 0
  for byte in @utf8.encode(source) {
    reader.feed_utf8([byte], fn(row) raise @arff.ArffError {
      if writer is None {
        match reader.schema() {
          Some(s) =>
            writer = Some(
              @arff.StreamWriter::new(
                s,
                fn(chunk) { sink.write_string(chunk) },
                sparse=true,
              ),
            )
          None => panic()
        }
      }
      if writer is Some(w) {
        w.write(row)
      }
      count += 1
    }) catch {
      _ => panic()
    }
  }
  reader.finish(fn(_) { panic() }) catch {
    _ => panic()
  }
  if writer is Some(w) {
    w.finish() catch {
      _ => panic()
    }
  }
  assert_eq(count, 2) catch {
    _ => panic()
  }
  assert_eq(reader.buffered_units(), 0) catch {
    _ => panic()
  }
  let result = @arff.parse(sink.to_string()) catch { _ => panic() }
  assert_eq(result, @arff.parse(source) catch { _ => panic() }) catch {
    _ => panic()
  }
  println(
    "streaming: PASS; one-byte UTF8 transport, CRLF, dates, weights, immediate sparse sink",
  )
}

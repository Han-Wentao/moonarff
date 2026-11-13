///|
/// Push parser retaining only a bounded header and current physical record.
/// Records are delivered synchronously; caller backpressure requires no row queue.
pub struct StreamReader {
  priv limits : Limits
  priv budget : FormatBudget
  priv mut header : BoundedText
  priv mut line : BoundedText
  priv mut schema : Schema?
  priv mut line_number : Int32
  priv mut previous_cr : Bool
  priv mut failed : Bool
  priv mut finished : Bool
  priv mut busy : Bool
  priv mut utf8_need : Int32
  priv mut utf8_value : Int32
  priv mut utf8_min : Int32
}

///|
pub fn StreamReader::new(
  limits~ : Limits = Limits::default(),
) -> StreamReader raise ArffError {
  limits.check()
  {
    limits,
    budget: FormatBudget::new(limits),
    header: BoundedText::new(limits.max_input),
    line: BoundedText::new(limits.max_input),
    schema: None,
    line_number: 1,
    previous_cr: false,
    failed: false,
    finished: false,
    busy: false,
    utf8_need: 0,
    utf8_value: 0,
    utf8_min: 0,
  }
}

///|
pub fn StreamReader::schema(self : StreamReader) -> Schema? {
  self.schema.map(copy_schema)
}

///|
/// Units retained in payload buffers, excluding the bounded schema and decoder.
pub fn StreamReader::buffered_units(self : StreamReader) -> Int32 {
  self.header.used + self.line.used
}

///|
fn StreamReader::check_open(self : StreamReader) -> Unit raise ArffError {
  if self.failed {
    raise Invalid("stream reader is failed")
  }
  if self.finished {
    raise Invalid("stream reader is finished")
  }
  if self.busy {
    raise Invalid("reentrant stream operation")
  }
}

///|
fn StreamReader::emit_line(
  self : StreamReader,
  emit : (Record) -> Unit raise ArffError,
) -> Unit raise ArffError {
  let text = self.line.to_string()
  self.line = BoundedText::new(self.limits.max_input)
  match self.schema {
    None => {
      self.header.write_string(text)
      self.header.write_char('\n')
      let scanner = Scanner::new(text, limits=self.limits)
      let first = scanner.next()
      if first.kind == Word && !first.quoted && keyword(first.text) == "@data" {
        let schema = read_schema(self.header.to_string(), limits=self.limits)
        self.schema = Some(schema)
        self.header = BoundedText::new(self.limits.max_input)
      }
    }
    Some(schema) => {
      let scanner = Scanner::new(text, limits=self.limits)
      if read_record_tokens(scanner, self.limits) is Some(tokens) {
        let located = tokens.map(fn(t) {
          Token::{ ..t, line: self.line_number, }
        })
        emit(parse_record_tokens(schema.attributes, located, self.budget, 0))
      }
    }
  }
  self.line_number += 1
}

///|
fn StreamReader::accept(
  self : StreamReader,
  ch : Char,
  emit : (Record) -> Unit raise ArffError,
) -> Unit raise ArffError {
  if ch == '\n' && self.previous_cr {
    self.previous_cr = false
    return
  }
  self.previous_cr = ch == '\r'
  if ch == '\n' || ch == '\r' {
    self.emit_line(emit)
  } else {
    self.line.write_char(ch)
  }
}

///|
/// Feed already decoded Unicode chunks. Do not split a UTF-16 surrogate pair;
/// arbitrary transport byte boundaries are supported by feed_utf8 instead.
pub fn StreamReader::feed(
  self : StreamReader,
  chunk : String,
  emit : (Record) -> Unit raise ArffError,
) -> Unit raise ArffError {
  self.check_open()
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer {
    self.failed = true
  }
  if self.utf8_need != 0 {
    raise Invalid("cannot mix text with an incomplete UTF-8 sequence")
  }
  for ch in chunk {
    if ch.to_int() >= 55296 && ch.to_int() <= 57343 {
      raise Invalid("unpaired Unicode surrogate")
    }
    self.accept(ch, emit)
  }
}

///|
/// Strict incremental UTF-8 decoder: accepts a split inside any multi-byte scalar.
pub fn StreamReader::feed_utf8(
  self : StreamReader,
  bytes : Bytes,
  emit : (Record) -> Unit raise ArffError,
) -> Unit raise ArffError {
  self.check_open()
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer {
    self.failed = true
  }
  for byte in bytes {
    let b = byte.to_int()
    if self.utf8_need == 0 {
      if b < 128 {
        self.accept(b.unsafe_to_char(), emit)
      } else if b >= 194 && b <= 223 {
        self.utf8_value = b - 192
        self.utf8_need = 1
        self.utf8_min = 128
      } else if b >= 224 && b <= 239 {
        self.utf8_value = b - 224
        self.utf8_need = 2
        self.utf8_min = 2048
      } else if b >= 240 && b <= 244 {
        self.utf8_value = b - 240
        self.utf8_need = 3
        self.utf8_min = 65536
      } else {
        raise Invalid("invalid UTF-8 leading byte")
      }
    } else {
      if b < 128 || b > 191 {
        raise Invalid("invalid UTF-8 continuation")
      }
      self.utf8_value = self.utf8_value * 64 + b - 128
      self.utf8_need -= 1
      if self.utf8_need == 0 {
        let value = self.utf8_value
        if value < self.utf8_min ||
          value > 1114111 ||
          (value >= 55296 && value <= 57343) {
          raise Invalid("noncanonical UTF-8 scalar")
        }
        self.accept(value.unsafe_to_char(), emit)
      }
    }
  }
}

///|
/// Process a final unterminated record. EOF is explicit and idempotent.
pub fn StreamReader::finish(
  self : StreamReader,
  emit : (Record) -> Unit raise ArffError,
) -> Unit raise ArffError {
  if self.failed {
    raise Invalid("stream reader is failed")
  }
  if self.busy {
    raise Invalid("reentrant stream operation")
  }
  if self.finished {
    return
  }
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer {
    self.failed = true
  }
  if self.utf8_need != 0 {
    raise Invalid("truncated UTF-8 at EOF")
  }
  if self.line.used > 0 {
    self.emit_line(emit)
  }
  if self.schema is None {
    raise Invalid("incomplete header at EOF")
  }
  self.finished = true
}

///|
/// Streaming writer. The sink owns transport, buffering and backpressure.
pub struct StreamWriter {
  priv schema : Schema
  priv budget : FormatBudget
  priv sink : (String) -> Unit raise ArffError
  priv sparse : Bool
  priv mut failed : Bool
  priv mut finished : Bool
  priv mut busy : Bool
}

///|
pub fn StreamWriter::new(
  schema : Schema,
  sink : (String) -> Unit raise ArffError,
  sparse~ : Bool = false,
  limits~ : Limits = Limits::default(),
) -> StreamWriter raise ArffError {
  validate_schema(schema, limits~)
  let snapshot = copy_schema(schema)
  let header = BoundedText::new(limits.max_input)
  write_header(snapshot, header)
  sink(header.to_string())
  {
    schema: snapshot,
    budget: FormatBudget::new(limits),
    sink,
    sparse,
    failed: false,
    finished: false,
    busy: false,
  }
}

///|
/// Validate an entire nested record before sending any bytes of that record.
pub fn StreamWriter::write(
  self : StreamWriter,
  row : Record,
) -> Unit raise ArffError {
  if self.failed || self.finished || self.busy {
    raise Invalid("stream writer failed, finished or reentrant")
  }
  self.busy = true
  defer {
    self.busy = false
  }
  errdefer {
    self.failed = true
  }
  validate_row(self.schema.attributes, row, self.budget, 0)
  let out = BoundedText::new(self.budget.limits.max_input)
  write_row(self.schema.attributes, row, self.sparse, out, self.budget.limits)
  (self.sink)(out.to_string())
}

///|
pub fn StreamWriter::finish(self : StreamWriter) -> Unit raise ArffError {
  if self.failed || self.busy {
    raise Invalid("stream writer failed or reentrant")
  }
  self.finished = true
}

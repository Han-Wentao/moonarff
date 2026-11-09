///|
/// A private sink checks UTF-16 output size before allocating each appended chunk.
priv struct BoundedText {
  builder : StringBuilder
  mut used : Int32
  maximum : Int32
}

///|
fn BoundedText::new(maximum : Int32) -> BoundedText {
  { builder: StringBuilder(), used: 0, maximum, }
}

///|
fn BoundedText::write_string(
  self : BoundedText,
  text : String,
) -> Unit raise ArffError {
  if text.length() > self.maximum - self.used {
    raise Limit("text output budget")
  }
  self.used += text.length()
  self.builder.write_string(text)
}

///|
fn BoundedText::write_char(
  self : BoundedText,
  ch : Char,
) -> Unit raise ArffError {
  let units = if ch.to_int() > 65535 { 2 } else { 1 }
  if units > self.maximum - self.used {
    raise Limit("text token/output budget")
  }
  self.used += units
  self.builder.write_char(ch)
}

///|
fn BoundedText::to_string(self : BoundedText) -> String {
  self.builder.to_string()
}

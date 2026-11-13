///|
/// ASCII-only case folding for ARFF reserved words, not user labels.
fn keyword(text : String) -> String {
  let out = StringBuilder()
  for ch in text {
    let code = ch.to_int()
    out.write_char(
      if code >= 65 && code <= 90 {
        (code + 32).unsafe_to_char()
      } else {
        ch
      },
    )
  }
  out.to_string()
}

///|
fn line_tokens(
  scanner : Scanner,
  max_count : Int32,
) -> Array[Token] raise ArffError {
  let out : Array[Token] = []
  while true {
    let token = scanner.next()
    if token.kind == Newline || token.kind == End {
      return out
    }
    if out.length() >= max_count {
      raise Limit("tokens per line budget")
    }
    out.push(token)
  }
  out
}

///|
fn require_word(token : Token, message : String) -> String raise ArffError {
  if token.kind != Word {
    raise Syntax(token.line, token.column, message)
  }
  token.text
}

///|
fn attribute_line(tokens : Array[Token]) -> Attribute raise ArffError {
  let at = tokens[0]
  if tokens.length() < 3 {
    raise Syntax(at.line, at.column, "attribute requires name and type")
  }
  let name = require_word(tokens[1], "attribute name required")
  let kind = tokens[2]
  if kind.kind == Word && !kind.quoted {
    let type_name = keyword(kind.text)
    if type_name == "date" {
      if tokens.length() > 4 {
        raise Syntax(kind.line, kind.column, "date takes one optional format")
      }
      let pattern = if tokens.length() == 4 {
        require_word(tokens[3], "date format required")
      } else {
        default_date_format()
      }
      ignore(date_parts(pattern))
      return { name, kind: Date(pattern), }
    }
    if tokens.length() != 3 {
      raise Syntax(kind.line, kind.column, "unexpected attribute suffix")
    }
    match keyword(kind.text) {
      "numeric" | "real" | "integer" => return { name, kind: Numeric, }
      "string" => return { name, kind: Text, }
      "relational" => return { name, kind: Relational([]), }
      _ => raise Syntax(kind.line, kind.column, "unknown attribute type")
    }
  }
  if kind.kind != Open {
    raise Syntax(kind.line, kind.column, "nominal domain or type required")
  }
  let labels : Array[String] = []
  let mut i = 3
  while i < tokens.length() {
    labels.push(require_word(tokens[i], "nominal label required"))
    i += 1
    if i == tokens.length() {
      break
    }
    if tokens[i].kind == Close {
      i += 1
      if i != tokens.length() {
        raise Syntax(at.line, at.column, "nominal suffix")
      }
      return { name, kind: Nominal(labels), }
    }
    if tokens[i].kind != Comma {
      raise Syntax(
        tokens[i].line,
        tokens[i].column,
        "comma required in nominal domain",
      )
    }
    i += 1
  }
  raise Syntax(at.line, at.column, "unclosed nominal domain")
}

///|
/// Parse and validate the header without consuming or validating data rows.
pub fn read_schema(
  source : String,
  limits~ : Limits = Limits::default(),
) -> Schema raise ArffError {
  parse_header(Scanner::new(source, limits~), limits)
}

///|
fn parse_header(scanner : Scanner, limits : Limits) -> Schema raise ArffError {
  let mut relation : String? = None
  let attributes : Array[Attribute] = []
  while true {
    let first = scanner.next()
    if first.kind == End {
      raise Syntax(first.line, first.column, "missing @data section")
    }
    if first.kind == Newline {
      continue
    }
    let tokens = [first]
    let tail = line_tokens(scanner, limits.max_input)
    for token in tail {
      tokens.push(token)
    }
    if first.kind != Word || first.quoted {
      raise Syntax(first.line, first.column, "header directive required")
    }
    match keyword(first.text) {
      "@relation" => {
        if relation is Some(_) ||
          tokens.length() != 2 ||
          attributes.length() > 0 {
          raise Syntax(
            first.line,
            first.column,
            "one relation must precede attributes",
          )
        }
        relation = Some(require_word(tokens[1], "relation name required"))
      }
      "@attribute" => {
        if relation is None {
          raise Syntax(
            first.line,
            first.column,
            "relation must precede attributes",
          )
        }
        if attributes.length() >= limits.max_attributes {
          raise Limit("attribute budget")
        }
        attributes.push(read_attribute(tokens, scanner, limits, 0))
      }
      "@data" => {
        if tokens.length() != 1 {
          raise Syntax(
            first.line,
            first.column,
            "@data must occupy its own line",
          )
        }
        let name = match relation {
          Some(name) => name
          None => raise Syntax(first.line, first.column, "missing relation")
        }
        let schema = Schema::{ relation: name, attributes, }
        validate_schema(schema, limits~)
        return schema
      }
      _ => raise Syntax(first.line, first.column, "unknown header directive")
    }
  }
  raise Invalid("unreachable header state")
}

///|
fn read_attribute(
  tokens : Array[Token],
  scanner : Scanner,
  limits : Limits,
  depth : Int32,
) -> Attribute raise ArffError {
  if depth > 16 {
    raise Limit("relational schema nesting exceeds 16")
  }
  let attribute = attribute_line(tokens)
  if attribute.kind is Relational(_) {
    let children = []
    while true {
      let first = scanner.next()
      if first.kind == Newline {
        continue
      }
      if first.kind != Word || first.quoted {
        raise Syntax(
          first.line,
          first.column,
          "nested @attribute or @end required",
        )
      }
      let tail = line_tokens(scanner, limits.max_input)
      let line = [first]
      for token in tail {
        line.push(token)
      }
      match keyword(first.text) {
        "@attribute" => {
          if children.length() >= limits.max_attributes {
            raise Limit("nested attribute budget")
          }
          children.push(read_attribute(line, scanner, limits, depth + 1))
        }
        "@end" => {
          if line.length() != 2 ||
            require_word(line[1], "@end name required") != attribute.name {
            raise Syntax(
              first.line,
              first.column,
              "@end name must match relational attribute",
            )
          }
          if children.is_empty() {
            raise Invalid("relational schema needs attributes")
          }
          return { name: attribute.name, kind: Relational(children), }
        }
        _ =>
          raise Syntax(
            first.line,
            first.column,
            "unexpected directive in relational schema",
          )
      }
    }
  }
  attribute
}

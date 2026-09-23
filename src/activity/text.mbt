///|
/// Reverses the five predefined XML entities plus numeric references.
pub fn unescape_xml(text : String) -> String {
  let sb = StringBuilder()
  let mut rest = text[:]
  while rest.find("&") is Some(i) {
    sb.write_string(rest[:i].to_owned())
    let tail = rest[i:]
    match tail.find(";") {
      Some(end) if end <= 8 => {
        let entity = tail[1:end]
        match entity {
          "amp" => sb.write_char('&')
          "lt" => sb.write_char('<')
          "gt" => sb.write_char('>')
          "quot" => sb.write_char('"')
          "apos" => sb.write_char('\'')
          ['#', 'x', .. hex] =>
            match parse_hex(hex) {
              Some(code) => sb.write_char(Int::unsafe_to_char(code))
              None => sb.write_string(tail[:end + 1].to_owned())
            }
          ['#', .. dec] =>
            match parse_number(dec) {
              Some(code) => sb.write_char(Int::unsafe_to_char(code))
              None => sb.write_string(tail[:end + 1].to_owned())
            }
          _ => sb.write_string(tail[:end + 1].to_owned())
        }
        rest = tail[end + 1:]
      }
      _ => {
        sb.write_char('&')
        rest = tail[1:]
      }
    }
  }
  sb.write_string(rest.to_owned())
  sb.to_string()
}

///|
fn parse_hex(text : StringView) -> Int? {
  if text.length() == 0 {
    return None
  }
  for i = 0, acc = 0; i < text.length(); {
    let c = text[i]
    let digit = if c >= '0' && c <= '9' {
      (c - '0').to_int()
    } else if c >= 'a' && c <= 'f' {
      (c - 'a').to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      (c - 'A').to_int() + 10
    } else {
      -1
    }
    if digit < 0 {
      break None
    }
    continue i + 1, acc * 16 + digit
  } nobreak {
    Some(acc)
  }
}

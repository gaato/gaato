///|
/// Escapes text for use inside an SVG/XML text node or attribute.
pub fn escape_xml(text : String) -> String {
  let sb = StringBuilder()
  for c in text {
    match c {
      '&' => sb.write_string("&amp;")
      '<' => sb.write_string("&lt;")
      '>' => sb.write_string("&gt;")
      '"' => sb.write_string("&quot;")
      '\'' => sb.write_string("&apos;")
      _ => if c.to_int() >= 0x20 { sb.write_char(c) }
    }
  }
  sb.to_string()
}

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

///|
/// Rough advance width of a character in em units for a sans-serif face:
/// full-width CJK glyphs count as 1em, everything else as 0.56em.
fn char_width_em(c : Char) -> Double {
  let code = c.to_int()
  if code >= 0x1100 &&
    (
      (code >= 0x2E80 && code <= 0xA4CF) ||
      (code >= 0xAC00 && code <= 0xD7A3) ||
      (code >= 0xF900 && code <= 0xFAFF) ||
      (code >= 0xFE30 && code <= 0xFE4F) ||
      (code >= 0xFF00 && code <= 0xFF60) ||
      (code >= 0xFFE0 && code <= 0xFFE6) ||
      (code >= 0x20000 && code <= 0x3FFFD) ||
      code == 0x1100
    ) {
    1.0
  } else if code < 0x20 {
    0.0
  } else {
    0.56
  }
}

///|
/// Estimated rendered width in pixels at the given font size.
pub fn text_width(text : String, font_size : Double) -> Double {
  let mut em = 0.0
  for c in text {
    em += char_width_em(c)
  }
  em * font_size
}

///|
/// Shortens `text` with an ellipsis so it fits within `max_width` pixels.
pub fn truncate_to_width(
  text : String,
  font_size : Double,
  max_width : Double,
) -> String {
  if text_width(text, font_size) <= max_width {
    return text
  }
  let ellipsis = char_width_em('…') * font_size
  let sb = StringBuilder()
  let mut used = 0.0
  for c in text {
    let w = char_width_em(c) * font_size
    if used + w + ellipsis > max_width {
      break
    }
    used += w
    sb.write_char(c)
  }
  let head = sb.to_string().trim().to_owned()
  "\{head}…"
}

///|
/// Offset applied before formatting calendar dates.
let jst_offset_seconds : Int64 = 9L * 3600L

///|
/// Days since 1970-01-01 for a proleptic Gregorian date.
fn days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (month + 9) % 12
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146097L + doe.to_int64() - 719468L
}

///|
/// Inverse of `days_from_civil`.
fn civil_from_days(days : Int64) -> (Int, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = (z - era * 146097L).to_int()
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era.to_int() * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

///|
fn two_digits(n : Int) -> String {
  n.to_string().pad_start(2, '0')
}

///|
/// `YYYY-MM-DD` in JST for a Unix timestamp in seconds.
pub fn jst_date(unix_seconds : Int64) -> String {
  let shifted = unix_seconds + jst_offset_seconds
  let days = if shifted >= 0L {
    shifted / 86400L
  } else {
    (shifted - 86399L) / 86400L
  }
  let (y, m, d) = civil_from_days(days)
  "\{y}-\{two_digits(m)}-\{two_digits(d)}"
}

///|
/// ISO 8601 UTC timestamp for GraphQL, at midnight `days_ago` days before
/// `unix_seconds`.
pub fn utc_midnight_days_ago(unix_seconds : Int64, days_ago : Int) -> String {
  let days = unix_seconds / 86400L - days_ago.to_int64()
  let (y, m, d) = civil_from_days(days)
  "\{y}-\{two_digits(m)}-\{two_digits(d)}T00:00:00Z"
}

///|
/// ISO 8601 UTC timestamp for GraphQL at the given second.
pub fn utc_timestamp(unix_seconds : Int64) -> String {
  let days = unix_seconds / 86400L
  let rem = (unix_seconds - days * 86400L).to_int()
  let (y, m, d) = civil_from_days(days)
  "\{y}-\{two_digits(m)}-\{two_digits(d)}T\{two_digits(rem / 3600)}:\{two_digits(rem % 3600 / 60)}:\{two_digits(rem % 60)}Z"
}

///|
fn month_number(name : String) -> Int? {
  match name.to_lower() {
    "jan" => Some(1)
    "feb" => Some(2)
    "mar" => Some(3)
    "apr" => Some(4)
    "may" => Some(5)
    "jun" => Some(6)
    "jul" => Some(7)
    "aug" => Some(8)
    "sep" => Some(9)
    "oct" => Some(10)
    "nov" => Some(11)
    "dec" => Some(12)
    _ => None
  }
}

///|
fn parse_number(text : StringView) -> Int? {
  if text.length() == 0 {
    return None
  }
  for i = 0, acc = 0; i < text.length(); {
    let c = text[i]
    if c >= '0' && c <= '9' {
      continue i + 1, acc * 10 + (c - '0').to_int()
    } else {
      break None
    }
  } nobreak {
    Some(acc)
  }
}

///|
/// Parses an RFC 2822 date such as `Sat, 29 Aug 2026 15:00:00 GMT` (as used
/// by RSS `pubDate`) into a Unix timestamp. Only `GMT`/`UT`/`Z` and numeric
/// `+HHMM` offsets are understood; anything else is treated as UTC.
pub fn parse_rfc2822(text : StringView) -> Int64? {
  let parts = text.trim().split(" ").filter(p => p.length() > 0).collect()
  // Optional weekday prefix ends with a comma.
  let start = if parts.length() > 0 && parts[0].has_suffix(",") { 1 } else { 0 }
  guard parts.length() >= start + 4 else { return None }
  guard parse_number(parts[start]) is Some(day) &&
    month_number(parts[start + 1].to_owned()) is Some(month) &&
    parse_number(parts[start + 2]) is Some(year) else {
    return None
  }
  let clock = parts[start + 3].split(":").collect()
  guard clock.length() >= 2 &&
    parse_number(clock[0]) is Some(hour) &&
    parse_number(clock[1]) is Some(minute) else {
    return None
  }
  let second = if clock.length() >= 3 {
    parse_number(clock[2]).unwrap_or(0)
  } else {
    0
  }
  let zone = if parts.length() > start + 4 { parts[start + 4] } else { "GMT" }
  let offset = match zone {
    ['+' | '-' as sign, .. digits] if digits.length() == 4 =>
      match parse_number(digits) {
        Some(hhmm) => {
          let minutes = hhmm / 100 * 60 + hhmm % 100
          if sign == '-' {
            -minutes
          } else {
            minutes
          }
        }
        None => 0
      }
    _ => 0
  }
  let days = days_from_civil(year, month, day)
  Some(
    days * 86400L +
    (hour * 3600 + minute * 60 + second - offset * 60).to_int64(),
  )
}

///|
/// Parses an ISO 8601 UTC timestamp such as `2026-09-22T10:00:00Z` (as used by
/// the GitHub API) into a Unix timestamp. Only the `Z` zone is understood.
pub fn parse_iso8601_utc(text : StringView) -> Int64? {
  guard text.length() == 20 &&
    text[4] == '-' &&
    text[7] == '-' &&
    text[10] == 'T' &&
    text[13] == ':' &&
    text[16] == ':' &&
    text[19] == 'Z' else {
    return None
  }
  guard parse_number(text[:4]) is Some(year) &&
    parse_number(text[5:7]) is Some(month) &&
    parse_number(text[8:10]) is Some(day) &&
    parse_number(text[11:13]) is Some(hour) &&
    parse_number(text[14:16]) is Some(minute) &&
    parse_number(text[17:19]) is Some(second) else {
    return None
  }
  Some(
    days_from_civil(year, month, day) * 86400L +
    (hour * 3600 + minute * 60 + second).to_int64(),
  )
}

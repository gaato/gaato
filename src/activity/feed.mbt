///|
/// Returns the text between the first `<tag>` and `</tag>` in `xml`, with
/// CDATA wrappers removed and entities decoded.
fn element_text(xml : StringView, tag : String) -> String? {
  guard xml.find("<\{tag}>") is Some(open) else {
    // Elements with attributes, e.g. `<title type="html">`.
    guard xml.find("<\{tag} ") is Some(open) else { return None }
    let body = xml[open:]
    guard body.find(">") is Some(close_bracket) else { return None }
    return element_body(body[close_bracket + 1:], tag)
  }
  element_body(xml[open + tag.length() + 2:], tag)
}

///|
fn element_body(body : StringView, tag : String) -> String? {
  guard body.find("</\{tag}>") is Some(close) else { return None }
  let raw = body[:close].trim()
  let inner = match raw {
    [.. "<![CDATA[", .. rest] =>
      match rest.find("]]>") {
        Some(end) => rest[:end].to_owned()
        None => rest.to_owned()
      }
    _ => unescape_xml(raw.to_owned())
  }
  Some(inner.trim().to_owned())
}

///|
/// Parses the `<item>` entries of an RSS 2.0 feed into posts. Entries without
/// a title, link or parseable `pubDate` are skipped.
pub fn parse_rss(xml : String, source~ : String) -> Array[Post] {
  let posts : Array[Post] = []
  let mut rest = xml[:]
  while rest.find("<item") is Some(start) {
    let item_start = rest[start:]
    guard item_start.find("</item>") is Some(end) else { break }
    let item = item_start[:end]
    if element_text(item, "title") is Some(title) &&
      element_text(item, "link") is Some(url) &&
      element_text(item, "pubDate") is Some(date_text) &&
      parse_rfc2822(date_text) is Some(unix) {
      posts.push({ title, url, date: jst_date(unix), source, })
    }
    rest = item_start[end + 7:]
  }
  posts
}

///|
/// Merges post lists, newest first, keeping at most `limit` entries.
pub fn latest_posts(lists : Array[Array[Post]], limit~ : Int) -> Array[Post] {
  let all : Array[Post] = []
  for list in lists {
    for post in list {
      all.push(post)
    }
  }
  all.sort_by((a, b) => {
    if a.date != b.date {
      b.date.compare(a.date)
    } else {
      a.title.compare(b.title)
    }
  })
  all[:all.length().min(limit)].to_owned()
}

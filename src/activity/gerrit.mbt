///|
/// Page size for the change query; Gerrit marks the last change of a page
/// with `_more_changes` when another page follows.
pub let gerrit_page_size : Int32 = 100

///|
/// Path and query for one page of changes owned by `login` and created since
/// `from` (`YYYY-MM-DD`), skipping the first `start` changes.
pub fn gerrit_changes_path(
  login : String,
  from~ : String,
  start~ : Int32,
) -> String {
  "/changes/?q=owner:\{login}+after:\{from}&n=\{gerrit_page_size}&S=\{start}"
}

///|
/// Gerrit prefixes every JSON response with `)]}'` and a newline to defeat
/// cross-site script inclusion; the rest is plain JSON.
pub fn parse_gerrit_response(text : String) -> Json raise {
  guard text.has_prefix(")]}'") && text.find("\n") is Some(newline) else {
    fail("unexpected Gerrit response: \{text}")
  }
  @json.parse(text[newline + 1:])
}

///|
/// Gerrit timestamps are UTC with nanoseconds, e.g.
/// `2026-10-13 06:23:42.000000000`; the fraction is dropped so the shared
/// ISO 8601 parser accepts them.
fn parse_gerrit_timestamp(text : String) -> Int64? {
  guard text.length() >= 19 && text[10] == ' ' else { return None }
  parse_iso8601_utc(text[:10].to_owned() + "T" + text[11:19].to_owned() + "Z")
}

///|
/// Parses one page of the change query against the Gerrit instance at
/// `base_url`, keeping open or merged changes. Returns the changes and whether
/// another page follows. Cherry-picks that Gerrit makes for other branches are
/// owned by a bot, so the query by owner already leaves them out.
pub fn parse_gerrit_changes(
  data : Json,
  base_url~ : String,
) -> (Array[UpstreamPullRequest], Bool) raise {
  guard data is Array(nodes) else {
    fail("unexpected change response: \{data.stringify()}")
  }
  let result : Array[UpstreamPullRequest] = []
  let mut more = false
  for node in nodes {
    guard node
      is {
        "_number": Number(number, ..),
        "project": String(project),
        "subject": String(title),
        "status": String(status),
        "created": String(created),
        ..
      } else {
      fail("unexpected change entry: \{node.stringify()}")
    }
    if node is { "_more_changes": True, .. } {
      more = true
    }
    if status != "NEW" && status != "MERGED" {
      continue
    }
    guard parse_gerrit_timestamp(created) is Some(unix) else {
      fail("unexpected change timestamp: \{created}")
    }
    // `group/subgroup/project`: the repository is the last path segment.
    let (owner, repo) = match project.rev_find("/") {
      Some(slash) =>
        (project[:slash].to_owned(), project[slash + 1:].to_owned())
      None => ("", project)
    }
    let number = number.to_int()
    result.push({
      owner,
      repo,
      number,
      reference: "\{project}~\{number}",
      title,
      url: "\{base_url}/c/\{project}/+/\{number}",
      merged: status == "MERGED",
      date: jst_date(unix),
    })
  }
  (result, more)
}

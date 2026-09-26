///|
/// Page size for the merge request listing; a shorter page is the last one.
pub let gitlab_page_size : Int = 100

///|
/// Path and query for one page of merge requests authored by `login` and
/// created since `from`, across every project the instance lets us see.
pub fn gitlab_merge_requests_path(
  login : String,
  from~ : String,
  page~ : Int,
) -> String {
  "/api/v4/merge_requests?scope=all&author_username=\{login}&created_after=\{from}&per_page=\{gitlab_page_size}&page=\{page}"
}

///|
/// GitLab timestamps carry milliseconds, e.g. `2026-02-02T14:16:10.363Z`;
/// the fraction is dropped so the shared ISO 8601 parser accepts them.
fn parse_gitlab_timestamp(text : String) -> Int64? {
  guard text.length() >= 20 && text.has_suffix("Z") else { return None }
  parse_iso8601_utc(text[:19].to_owned() + "Z")
}

///|
/// Parses one page of the merge request listing, keeping open or merged MRs
/// by `login` to projects outside `login`'s own namespace.
pub fn parse_gitlab_merge_requests(
  data : Json,
  login~ : String,
) -> Array[UpstreamPullRequest] raise {
  guard data is Array(nodes) else {
    fail("unexpected merge request response: \{data.stringify()}")
  }
  let result : Array[UpstreamPullRequest] = []
  for node in nodes {
    guard node
      is {
        "iid": Number(number, ..),
        "title": String(title),
        "state": String(state),
        "created_at": String(created_at),
        "web_url": String(url),
        "author": { "username": String(author), .. },
        "references": { "full": String(reference), .. },
        ..
      } else {
      fail("unexpected merge request entry: \{node.stringify()}")
    }
    if author != login || (state != "opened" && state != "merged") {
      continue
    }
    // `group/subgroup/project!12`: the project is the last path segment.
    guard reference.rev_find("!") is Some(bang) &&
      reference[:bang].rev_find("/") is Some(slash) else {
      fail("unexpected merge request reference: \{reference}")
    }
    let owner = reference[:slash].to_owned()
    if owner == login || owner.has_prefix("\{login}/") {
      continue
    }
    guard parse_gitlab_timestamp(created_at) is Some(unix) else {
      fail("unexpected merge request timestamp: \{created_at}")
    }
    result.push({
      owner,
      repo: reference[slash + 1:bang].to_owned(),
      number: number.to_int(),
      reference,
      title,
      url,
      merged: state == "merged",
      date: jst_date(unix),
    })
  }
  result
}

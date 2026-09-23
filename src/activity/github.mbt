///|
/// The GraphQL query for recent commit contributions.
pub let contributions_query : String =
  #|query($login: String!, $recentFrom: DateTime!, $to: DateTime!) {
  #|  user(login: $login) {
  #|    recent: contributionsCollection(from: $recentFrom, to: $to) {
  #|      commitContributionsByRepository(maxRepositories: 25) {
  #|        repository { nameWithOwner primaryLanguage { name color } }
  #|        contributions { totalCount }
  #|      }
  #|    }
  #|  }
  #|}

///|
/// PRs are ordered newest first so fetching can stop at the 365-day cutoff.
pub let pull_requests_query : String =
  #|query($login: String!, $cursor: String) {
  #|  user(login: $login) {
  #|    pullRequests(first: 100, after: $cursor, states: [OPEN, MERGED], orderBy: {field: CREATED_AT, direction: DESC}) {
  #|      nodes {
  #|        createdAt
  #|        state
  #|        number
  #|        title
  #|        url
  #|        author { login }
  #|        repository { nameWithOwner owner { login } }
  #|      }
  #|      pageInfo { hasNextPage endCursor }
  #|    }
  #|  }
  #|}

///|
/// Colour used for repositories without a primary language.
let no_language_color : String = "#9a948a"

///|
/// Extracts the recently committed repositories from the `data` payload of
/// `contributions_query`.
pub fn parse_repositories(
  data : Json,
  max_repos? : Int = 6,
) -> Array[Repo] raise {
  guard data
    is {
      "user": {
        "recent": { "commitContributionsByRepository": Array(commits), .. },
        ..
      },
      ..
    } else {
    fail("unexpected GraphQL response shape: \{data.stringify()}")
  }
  let repos : Array[Repo] = []
  for entry in commits {
    guard entry
      is {
        "repository": {
          "nameWithOwner": String(name),
          "primaryLanguage": lang,
          ..
        },
        "contributions": { "totalCount": Number(count, ..), .. },
        ..
      } else {
      fail("unexpected commit entry: \{entry.stringify()}")
    }
    let (language, color) = match lang {
      { "name": String(n), "color": String(c), .. } => (n, c)
      { "name": String(n), .. } => (n, no_language_color)
      _ => ("", no_language_color)
    }
    repos.push({ name, commits: count.to_int(), language, color, })
  }
  repos.sort_by((a, b) => {
    if a.commits != b.commits {
      b.commits - a.commits
    } else {
      a.name.compare(b.name)
    }
  })
  repos[:repos.length().min(max_repos)].to_owned()
}

///|
/// Parses the `data` payload of one newest-first page, retaining only PRs
/// created within `from`. Returns the next cursor only when more in-window PRs
/// may remain.
pub fn parse_pull_request_page(
  data : Json,
  from~ : String,
  login~ : String,
) -> (Array[UpstreamPullRequest], String?) raise {
  guard data
    is {
      "user": {
        "pullRequests": {
          "nodes": Array(nodes),
          "pageInfo": {
            "hasNextPage": has_next_json,
            "endCursor": end_cursor,
            ..
          },
          ..
        },
        ..
      },
      ..
    } else {
    fail("unexpected pull request response shape: \{data.stringify()}")
  }
  let has_next = match has_next_json {
    True => true
    False => false
    _ => fail("pull request page has invalid hasNextPage")
  }
  let result : Array[UpstreamPullRequest] = []
  let mut reached_cutoff = false
  for node in nodes {
    guard node
      is {
        "createdAt": String(created_at),
        "state": String(state),
        "number": Number(number, ..),
        "title": String(title),
        "url": String(url),
        "author": { "login": String(author), .. },
        "repository": {
          "nameWithOwner": String(name),
          "owner": { "login": String(owner), .. },
          ..
        },
        ..
      } else {
      fail("unexpected pull request entry: \{node.stringify()}")
    }
    if created_at < from {
      reached_cutoff = true
      break
    }
    if author != login ||
      owner == login ||
      (state != "OPEN" && state != "MERGED") {
      continue
    }
    guard name.strip_prefix("\{owner}/") is Some(repo) else {
      fail("unexpected pull request repository: \{name}")
    }
    guard parse_iso8601_utc(created_at) is Some(unix) else {
      fail("unexpected pull request timestamp: \{created_at}")
    }
    result.push({
      owner,
      repo: repo.to_owned(),
      number: number.to_int(),
      title,
      url,
      merged: state == "MERGED",
      date: jst_date(unix),
    })
  }
  let next = if has_next && !reached_cutoff {
    guard end_cursor is String(cursor) && cursor != "" && nodes.length() > 0 else {
      fail("pull request page is missing its next cursor")
    }
    Some(cursor)
  } else {
    None
  }
  (result, next)
}

///|
/// Orders eligible PRs newest first. Ties break on repository then number so
/// the rendered list is stable between runs.
pub fn sort_upstream(
  prs : Array[UpstreamPullRequest],
) -> Array[UpstreamPullRequest] {
  let sorted = prs.copy()
  sorted.sort_by((a, b) => {
    if a.date != b.date {
      b.date.compare(a.date)
    } else if a.owner != b.owner {
      a.owner.compare(b.owner)
    } else if a.repo != b.repo {
      a.repo.compare(b.repo)
    } else {
      b.number - a.number
    }
  })
  sorted
}

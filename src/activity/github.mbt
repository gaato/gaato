///|
/// The GraphQL query that `parse_contributions` expects a response for.
/// `recent` is the commit window and `year` the pull-request window.
pub let contributions_query : String =
  #|query($login: String!, $recentFrom: DateTime!, $yearFrom: DateTime!, $to: DateTime!) {
  #|  user(login: $login) {
  #|    recent: contributionsCollection(from: $recentFrom, to: $to) {
  #|      commitContributionsByRepository(maxRepositories: 25) {
  #|        repository { nameWithOwner primaryLanguage { name color } }
  #|        contributions { totalCount }
  #|      }
  #|    }
  #|    year: contributionsCollection(from: $yearFrom, to: $to) {
  #|      pullRequestContributionsByRepository(maxRepositories: 100) {
  #|        repository { nameWithOwner owner { login } }
  #|        contributions { totalCount }
  #|      }
  #|    }
  #|  }
  #|}

///|
/// Colour used for repositories without a primary language.
let no_language_color : String = "#9a948a"

///|
/// Extracts the recently committed repositories and the upstream pull
/// requests from a GraphQL response to `contributions_query`.
pub fn parse_contributions(
  response : Json,
  login~ : String,
  max_repos? : Int = 6,
  max_owners? : Int = 5,
) -> (Array[Repo], Array[Upstream]) raise {
  guard response
    is {
      "data": {
        "user": {
          "recent": { "commitContributionsByRepository": Array(commits), .. },
          "year": { "pullRequestContributionsByRepository": Array(prs), .. },
          ..
        },
        ..
      },
      ..
    } else {
    fail("unexpected GraphQL response shape: \{response.stringify()}")
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
  let by_owner : Map[String, Upstream] = Map([])
  for entry in prs {
    guard entry
      is {
        "repository": {
          "nameWithOwner": String(name),
          "owner": { "login": String(owner), .. },
          ..
        },
        "contributions": { "totalCount": Number(count, ..), .. },
        ..
      } else {
      fail("unexpected pull request entry: \{entry.stringify()}")
    }
    if owner == login {
      continue
    }
    let repo = match name.find("/") {
      Some(i) => name[i + 1:].to_owned()
      None => name
    }
    match by_owner.get(owner) {
      Some(u) => {
        u.repos.push(repo)
        by_owner[owner] = { ..u, prs: u.prs + count.to_int(), }
      }
      None => by_owner[owner] = { owner, repos: [repo], prs: count.to_int(), }
    }
  }
  let upstream = by_owner.values().collect()
  upstream.sort_by((a, b) => {
    if a.prs != b.prs {
      b.prs - a.prs
    } else {
      a.owner.compare(b.owner)
    }
  })
  (
    repos[:repos.length().min(max_repos)].to_owned(),
    upstream[:upstream.length().min(max_owners)].to_owned(),
  )
}

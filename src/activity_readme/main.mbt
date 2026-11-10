///|
let login : String = "gaato"

///|
let repo_days : Int32 = 90

///|
let upstream_days : Int32 = 365

///|
let feeds : Array[(String, String)] = [
  ("gaato.net", "https://gaato.net/feed.xml"),
  ("Zenn", "https://zenn.dev/gaato/feed"),
]

///|
/// GitLab instances whose merge requests count as upstream work. Their
/// listing API is public, so no token is needed.
let gitlab_instances : Array[String] = [
  "https://invent.kde.org", "https://gitlab.freedesktop.org",
]

///|
/// Gerrit instances whose changes count as upstream work. Their query API is
/// public, so no account is needed.
let gerrit_instances : Array[String] = ["https://codereview.qt-project.org"]

///|
let obs_api_url : String = "https://api.opensuse.org"

///|
let user_agent : String = "gaato-profile-readme"

///|
let data_path : String = "data/activity.json"

///|
let readme_path : String = "README.md"

///|
/// A received GitHub failure follows the same source fallback as a parser or
/// transport failure; transport errors themselves keep their identity.
fn github_data(result : Result[Json, @github.GitHubFailure]) -> Json raise {
  match result {
    Ok(data) => data
    Err(GraphqlFailure(_, message~, ..)) => fail(message)
    Err(Http(error)) => fail("GitHub HTTP \{error.head().status}")
    Err(Validation(message)) => fail(message)
  }
}

///|
async fn fetch_repositories(
  gh : @github.GitHub,
  now : Int64,
) -> Array[@activity.Repo] {
  let data = github_data(
    gh.graphql(query=@activity.contributions_query, variables={
      "login": login,
      "recentFrom": @activity.utc_midnight_days_ago(now, repo_days),
      "to": @activity.utc_timestamp(now),
    }),
  )
  @activity.parse_repositories(data)
}

///|
/// Follows the cursor until `parse_pull_request_page` returns none, which is
/// the 365-day cutoff or the end of the connection, whichever comes first.
/// A page can hold no upstream PR at all when the profile owner's own
/// repositories fill it, so pagination does not stop at an empty page the way
/// `graphql_paginator` does.
async fn fetch_upstream(
  gh : @github.GitHub,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  let mut cursor : String? = None
  for ;; {
    let data = github_data(
      gh.graphql(query=@activity.pull_requests_query, variables={
        "login": login,
        "cursor": match cursor {
          Some(cursor) => Json::string(cursor)
          None => Json::null()
        },
      }),
    )
    let (page, next) = @activity.parse_pull_request_page(data, from~, login~)
    prs.append(page)
    guard next is Some(_) else { break }
    cursor = next
  }
  @activity.sort_upstream(prs)
}

///|
/// Pages through the MRs `login` opened on one GitLab instance within the
/// upstream window.
async fn fetch_merge_requests(
  client : @client.Client,
  base_url : String,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  for page = 1; ; page = page + 1 {
    let url = base_url +
      @activity.gitlab_merge_requests_path(login, from~, page~)
    let data = @json.parse(fetch_text(client, url))
    guard data is Array(nodes) else {
      fail("unexpected merge request response from \{url}")
    }
    prs.append(@activity.parse_gitlab_merge_requests(data, login~))
    if nodes.length() < @activity.gitlab_page_size {
      break
    }
  }
  prs
}

///|
/// Pages through the changes `login` uploaded to one Gerrit instance within
/// the upstream window.
async fn fetch_changes(
  client : @client.Client,
  base_url : String,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  // Gerrit's `after:` takes a date, so the window's start is cut to its day.
  let from = @activity.utc_midnight_days_ago(now, upstream_days)[:10].to_owned()
  let prs : Array[@activity.UpstreamPullRequest] = []
  for start = 0; ; start = start + @activity.gerrit_page_size {
    let url = base_url + @activity.gerrit_changes_path(login, from~, start~)
    let data = @activity.parse_gerrit_response(fetch_text(client, url))
    let (page, more) = @activity.parse_gerrit_changes(data, base_url~)
    prs.append(page)
    if !more {
      break
    }
  }
  prs
}

///|
/// OBS needs credentials even for reading requests, so `obs` carries the
/// profile owner's account through HTTP Basic auth.
async fn fetch_submit_requests(
  obs : @client.Client,
  now : Int64,
) -> Array[@activity.SubmitRequest] {
  @activity.parse_submit_requests(
    fetch_text(obs, @activity.obs_submit_request_search(login)),
    from=@activity.utc_midnight_days_ago(now, upstream_days),
    login~,
  )
}

///|
async fn fetch_feed(client : @client.Client, url : String) -> String {
  fetch_text(client, url)
}

///|
/// Runs one source's fetch. A failure is reported as a workflow warning and
/// the source keeps its entries from the last run, so one source being down
/// neither aborts the others nor makes its items vanish from the README.
async fn[T] fetch_or_keep(
  source : String,
  previous : Array[T],
  fetch : async () -> Array[T],
) -> Array[T] {
  fetch() catch {
    error => {
      println(@activity.warning_command(source, error.to_string()))
      previous
    }
  }
}

///|
/// The last saved activity, or an empty one when there is none yet or it no
/// longer parses; either way every source then simply starts from nothing.
async fn load_previous() -> @activity.Activity {
  @json.from_json(@json.parse(@fs.read_text(data_path))) catch {
    _ =>
      {
        generated_on: "",
        repo_days,
        upstream_days,
        repos: [],
        upstream: [],
        packaging: [],
        posts: [],
      }
  }
}

///|
async fn build_activity() -> @activity.Activity {
  guard @env.get_env_var("GITHUB_TOKEN") is Some(token) && token != "" else {
    fail("GITHUB_TOKEN is not set")
  }
  guard @env.get_env_var("OBS_PASSWORD") is Some(obs_password) &&
    obs_password != "" else {
    fail("OBS_PASSWORD is not set")
  }
  let previous = load_previous()
  let backend = @backend.AsyncBackend::new()
  defer backend.close()
  let clock = @runtime.AsyncClock::new()
  let gh = @github.GitHub::new(backend, clock, token~, user_agent~)
  let client = source_client(
    @backend.AsyncBackend::new(),
    clock,
    headers=@http.Headers::of([("User-Agent", user_agent)]),
  )
  defer client.close()
  let obs = source_client(
    @backend.AsyncBackend::new(),
    clock,
    base_url=obs_api_url,
    headers=obs_headers(obs_password),
  )
  defer obs.close()
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let repos = fetch_or_keep("GitHub repositories", previous.repos, () => {
    fetch_repositories(gh, now)
  })
  let upstream = fetch_or_keep(
    "GitHub pull requests",
    @activity.upstream_from(previous.upstream, "https://github.com"),
    () => fetch_upstream(gh, now),
  )
  for base_url in gitlab_instances {
    upstream.append(
      fetch_or_keep(
        base_url,
        @activity.upstream_from(previous.upstream, base_url),
        () => fetch_merge_requests(client, base_url, now),
      ),
    )
  }
  for base_url in gerrit_instances {
    upstream.append(
      fetch_or_keep(
        base_url,
        @activity.upstream_from(previous.upstream, base_url),
        () => fetch_changes(client, base_url, now),
      ),
    )
  }
  let packaging = fetch_or_keep("OBS", previous.packaging, () => {
    fetch_submit_requests(obs, now)
  })
  let lists = []
  for feed in feeds {
    let (source, url) = feed
    lists.push(
      fetch_or_keep(source, @activity.posts_from(previous.posts, source), () => {
        @activity.parse_rss(fetch_feed(client, url), source~)
      }),
    )
  }
  {
    generated_on: @activity.jst_date(now),
    repo_days,
    upstream_days,
    repos,
    upstream: @activity.sort_upstream(upstream),
    packaging,
    posts: @activity.latest_posts(lists, limit=3),
  }
}

///|
async fn write_readme(activity : @activity.Activity) -> Unit {
  let readme = @fs.read_text(readme_path)
  let updated = @activity.update_readme(readme, activity, login~)
  if updated != readme {
    @fs.write_text(readme_path, updated)
  }
}

///|
/// `moon run src/activity_readme` fetches fresh data, writes `data/activity.json`
/// and updates the marked README section. `moon run src/activity_readme -- render`
/// only re-renders that section from the saved JSON.
async fn main {
  let args = @env.args()
  if args.length() > 1 && args[1] == "render" {
    let saved = @json.parse(@fs.read_text(data_path))
    write_readme(@json.from_json(saved))
    println("rendered \{readme_path} from \{data_path}")
  } else {
    let activity = build_activity()
    @fs.write_text(data_path, activity.to_json().stringify(indent=2) + "\n")
    write_readme(activity)
    println("wrote \{data_path} and \{readme_path}")
  }
}

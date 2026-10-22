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
/// Reports a parser failure the way the SDK reports one, so a bad payload and
/// a failed query fail alike. The body stays empty: the payload that failed is
/// already in the message, and there are no GraphQL errors to read back.
fn[T] decoded(parse : () -> T raise) -> T raise @runtime.SdkError {
  parse() catch {
    error =>
      raise @runtime.Decode(message=error.to_string(), body=Bytes::new(0))
  }
}

///|
async fn fetch_repositories(
  gh : @github.GitHub,
  now : Int64,
) -> Array[@activity.Repo] raise @runtime.SdkError {
  let data = gh.graphql(query=@activity.contributions_query, variables={
    "login": login,
    "recentFrom": @activity.utc_midnight_days_ago(now, repo_days),
    "to": @activity.utc_timestamp(now),
  })
  decoded(() => @activity.parse_repositories(data))
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
) -> Array[@activity.UpstreamPullRequest] raise @runtime.SdkError {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  let mut cursor : String? = None
  for ;; {
    let data = gh.graphql(query=@activity.pull_requests_query, variables={
      "login": login,
      "cursor": match cursor {
        Some(cursor) => Json::string(cursor)
        None => Json::null()
      },
    })
    let (page, next) = decoded(() => {
      @activity.parse_pull_request_page(data, from~, login~)
    })
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
  client : @requesto.Client,
  base_url : String,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  for page = 1; ; page = page + 1 {
    let url = base_url +
      @activity.gitlab_merge_requests_path(login, from~, page~)
    let data = client.get(url).raise_for_status().json()
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
  client : @requesto.Client,
  base_url : String,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  // Gerrit's `after:` takes a date, so the window's start is cut to its day.
  let from = @activity.utc_midnight_days_ago(now, upstream_days)[:10].to_owned()
  let prs : Array[@activity.UpstreamPullRequest] = []
  for start = 0; ; start = start + @activity.gerrit_page_size {
    let url = base_url + @activity.gerrit_changes_path(login, from~, start~)
    let data = @activity.parse_gerrit_response(
      client.get(url).raise_for_status().text(),
    )
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
  obs : @requesto.Client,
  now : Int64,
) -> Array[@activity.SubmitRequest] {
  @activity.parse_submit_requests(
    obs
    .get(@activity.obs_submit_request_search(login))
    .raise_for_status()
    .text(),
    from=@activity.utc_midnight_days_ago(now, upstream_days),
    login~,
  )
}

///|
async fn fetch_feed(client : @requesto.Client, url : String) -> String {
  client.get(url).raise_for_status().text()
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
  let transport = @httpasync.AsyncTransport::new()
  let gh = @github.GitHub::new(
    transport,
    @httpasync.AsyncClock::new(),
    token~,
    user_agent~,
  )
  let client = @requesto.Client::new(headers=[("User-Agent", user_agent)])
  defer client.close()
  let obs = @requesto.Client::new(
    base_url=obs_api_url,
    headers=[("User-Agent", user_agent), ("Accept", "application/xml")],
    auth=Basic(username=login, password=obs_password),
  )
  defer obs.close()
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let repos = fetch_repositories(gh, now)
  let upstream = fetch_upstream(gh, now)
  for base_url in gitlab_instances {
    upstream.append(fetch_merge_requests(client, base_url, now))
  }
  for base_url in gerrit_instances {
    upstream.append(fetch_changes(client, base_url, now))
  }
  let packaging = fetch_submit_requests(obs, now)
  let lists = []
  for feed in feeds {
    let (source, url) = feed
    lists.push(@activity.parse_rss(fetch_feed(client, url), source~))
  }
  transport.close()
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
  let readme = @fs.read_file(readme_path).text()
  let updated = @activity.update_readme(readme, activity, login~)
  if updated != readme {
    @fs.write_file(readme_path, updated)
  }
}

///|
/// `moon run src/activity_readme` fetches fresh data, writes `data/activity.json`
/// and updates the marked README section. `moon run src/activity_readme -- render`
/// only re-renders that section from the saved JSON.
async fn main {
  let args = @env.args()
  if args.length() > 1 && args[1] == "render" {
    let saved = @json.parse(@fs.read_file(data_path).text())
    write_readme(@json.from_json(saved))
    println("rendered \{readme_path} from \{data_path}")
  } else {
    let activity = build_activity()
    @fs.write_file(data_path, activity.to_json().stringify(indent=2) + "\n")
    write_readme(activity)
    println("wrote \{data_path} and \{readme_path}")
  }
}

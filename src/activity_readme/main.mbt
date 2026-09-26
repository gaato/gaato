///|
let login : String = "gaato"

///|
let repo_days : Int = 90

///|
let upstream_days : Int = 365

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
let obs_api_url : String = "https://api.opensuse.org"

///|
let user_agent : String = "gaato-profile-readme"

///|
let data_path : String = "data/activity.json"

///|
let readme_path : String = "README.md"

///|
/// Reports a parser failure the way the SDK reports one, so a query and a
/// paginator page fail alike. The body stays empty: the payload that failed is
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
/// The paginator stops where `parse_pull_request_page` returns no cursor, which
/// is the 365-day cutoff or the end of the connection, whichever comes first.
async fn fetch_upstream(
  gh : @github.GitHub,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] raise @runtime.SdkError {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  gh
  .graphql_paginator(
    data => {
      decoded(() => @activity.parse_pull_request_page(data, from~, login~))
    },
    query=@activity.pull_requests_query,
    variables={ "login": login },
    cursor_variable="cursor",
  )
  .each(pr => prs.push(pr))
  @activity.sort_upstream(prs)
}

///|
/// Pages through the MRs `login` opened on one GitLab instance within the
/// upstream window.
async fn fetch_merge_requests(
  transport : @httpasync.AsyncTransport,
  base_url : String,
  now : Int64,
) -> Array[@activity.UpstreamPullRequest] {
  let from = @activity.utc_midnight_days_ago(now, upstream_days)
  let prs : Array[@activity.UpstreamPullRequest] = []
  for page = 1; ; page = page + 1 {
    let url = base_url +
      @activity.gitlab_merge_requests_path(login, from~, page~)
    let response = transport.send(
      @ghttp.Request::get(url).header("user-agent", user_agent),
    )
    if response.status != 200 {
      fail("merge request listing \{url} failed with HTTP \{response.status}")
    }
    let data = response.json()
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
/// OBS needs credentials even for reading requests, so this uses the profile
/// owner's account through HTTP Basic auth.
async fn fetch_submit_requests(
  transport : @httpasync.AsyncTransport,
  password : String,
  now : Int64,
) -> Array[@activity.SubmitRequest] {
  let credentials = @base64.encode(@utf8.encode("\{login}:\{password}"))
  let response = transport.send(
    @ghttp.Request::get(
      obs_api_url + @activity.obs_submit_request_search(login),
    )
    .header("user-agent", user_agent)
    .header("accept", "application/xml")
    .header("authorization", "Basic \{credentials}"),
  )
  if response.status != 200 {
    fail("OBS request search failed with HTTP \{response.status}")
  }
  @activity.parse_submit_requests(
    response.text(),
    from=@activity.utc_midnight_days_ago(now, upstream_days),
    login~,
  )
}

///|
async fn fetch_feed(
  transport : @httpasync.AsyncTransport,
  url : String,
) -> String {
  let response = transport.send(
    @ghttp.Request::get(url).header("user-agent", user_agent),
  )
  if response.status != 200 {
    fail("feed request for \{url} failed with HTTP \{response.status}")
  }
  response.text()
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
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let repos = fetch_repositories(gh, now)
  let upstream = fetch_upstream(gh, now)
  for base_url in gitlab_instances {
    upstream.append(fetch_merge_requests(transport, base_url, now))
  }
  let packaging = fetch_submit_requests(transport, obs_password, now)
  let lists = []
  for feed in feeds {
    let (source, url) = feed
    lists.push(@activity.parse_rss(fetch_feed(transport, url), source~))
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

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
let data_path : String = "data/activity.json"

///|
let readme_path : String = "README.md"

///|
fn header(name : String) -> @http.CaseInsensitiveString {
  @http.CaseInsensitiveString(name)
}

///|
async fn fetch_contributions(token : String, now : Int64) -> Json {
  let variables : Json = {
    "login": login,
    "recentFrom": @activity.utc_midnight_days_ago(now, repo_days),
    "yearFrom": @activity.utc_midnight_days_ago(now, upstream_days),
    "to": @activity.utc_timestamp(now),
  }
  let body : Json = {
    "query": @activity.contributions_query,
    "variables": variables,
  }
  let (response, data) = @http.post(
    "https://api.github.com/graphql",
    body,
    headers=Map::from_array([
      (header("Authorization"), "bearer \{token}"),
      (header("Content-Type"), "application/json"),
      (header("User-Agent"), "gaato-profile-readme"),
    ]),
  )
  let text = data.text()
  if response.code != 200 {
    fail("GraphQL request failed with HTTP \{response.code}: \{text}")
  }
  @json.parse(text)
}

///|
async fn fetch_feed(url : String) -> String {
  let (response, data) = @http.get(
    url,
    headers=Map::from_array([(header("User-Agent"), "gaato-profile-readme")]),
  )
  let text = data.text()
  if response.code != 200 {
    fail("feed request for \{url} failed with HTTP \{response.code}")
  }
  text
}

///|
async fn build_activity() -> @activity.Activity {
  guard @env.get_env_var("GITHUB_TOKEN") is Some(token) && token != "" else {
    fail("GITHUB_TOKEN is not set")
  }
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let (repos, upstream) = @activity.parse_contributions(
    fetch_contributions(token, now),
    login~,
  )
  let lists = []
  for feed in feeds {
    let (source, url) = feed
    lists.push(@activity.parse_rss(fetch_feed(url), source~))
  }
  {
    generated_on: @activity.jst_date(now),
    repo_days,
    upstream_days,
    repos,
    upstream,
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

///|
/// A repository the profile owner has committed to recently.
pub(all) struct Repo {
  name : String
  commits : Int
  language : String
  color : String
} derive(ToJson, FromJson)

///|
/// Pull requests sent to repositories owned by someone else, grouped by owner.
pub(all) struct Upstream {
  owner : String
  repos : Array[String]
  prs : Int
  open : Int?
  merged : Int?
} derive(ToJson, FromJson)

///|
/// An eligible pull request, used while grouping paginated GitHub results.
pub(all) struct UpstreamPullRequest {
  owner : String
  repo : String
  merged : Bool
}

///|
/// A published article.
pub(all) struct Post {
  title : String
  url : String
  date : String
  source : String
} derive(ToJson, FromJson)

///|
/// Everything the README activity section shows. `generated_on` and the two windows are
/// in JST calendar days.
pub(all) struct Activity {
  generated_on : String
  repo_days : Int
  upstream_days : Int
  repos : Array[Repo]
  upstream : Array[Upstream]
  posts : Array[Post]
} derive(ToJson, FromJson)

///|
pub extend Repo with ToJson::{to_json}

///|
pub extend Repo with @json.FromJson::{from_json}

///|
pub extend Upstream with ToJson::{to_json}

///|
pub extend Upstream with @json.FromJson::{from_json}

///|
pub extend Post with ToJson::{to_json}

///|
pub extend Post with @json.FromJson::{from_json}

///|
pub extend Activity with ToJson::{to_json}

///|
pub extend Activity with @json.FromJson::{from_json}

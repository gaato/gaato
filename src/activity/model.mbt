///|
/// A repository the profile owner has committed to recently.
pub(all) struct Repo {
  name : String
  commits : Int
  language : String
  color : String
} derive(ToJson, FromJson)

///|
/// A pull request sent to a repository owned by someone else, on GitHub or on a
/// GitLab instance, where it is called a merge request.
pub(all) struct UpstreamPullRequest {
  owner : String
  repo : String
  number : Int
  /// How the forge itself writes the reference: `owner/repo#1` on GitHub,
  /// `group/project!1` on GitLab.
  reference : String
  title : String
  url : String
  merged : Bool
  date : String
} derive(ToJson, FromJson)

///|
/// An OBS submit request to a project outside the profile owner's home.
pub(all) struct SubmitRequest {
  project : String
  pkg : String
  number : Int
  url : String
  accepted : Bool
  date : String
} derive(ToJson, FromJson)

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
  upstream : Array[UpstreamPullRequest]
  packaging : Array[SubmitRequest]
  posts : Array[Post]
} derive(ToJson, FromJson)

///|
pub extend Repo with ToJson::{to_json}

///|
pub extend Repo with @json.FromJson::{from_json}

///|
pub extend UpstreamPullRequest with ToJson::{to_json}

///|
pub extend UpstreamPullRequest with @json.FromJson::{from_json}

///|
pub extend SubmitRequest with ToJson::{to_json}

///|
pub extend SubmitRequest with @json.FromJson::{from_json}

///|
pub extend Post with ToJson::{to_json}

///|
pub extend Post with @json.FromJson::{from_json}

///|
pub extend Activity with ToJson::{to_json}

///|
pub extend Activity with @json.FromJson::{from_json}

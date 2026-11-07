///|
/// A repository the profile owner has committed to recently.
#derive(ToJson, FromJson)
pub(all) struct Repo {
  name : String
  commits : Int32
  language : String
  color : String
}

///|
/// A pull request sent to a repository owned by someone else, on GitHub, on a
/// GitLab instance, where it is called a merge request, or on a Gerrit
/// instance, where it is called a change.
#derive(ToJson, FromJson)
pub(all) struct UpstreamPullRequest {
  owner : String
  repo : String
  number : Int32
  /// How the forge itself writes the reference: `owner/repo#1` on GitHub,
  /// `group/project!1` on GitLab, `group/project~1` on Gerrit.
  reference : String
  title : String
  url : String
  merged : Bool
  date : String
}

///|
/// An OBS submit request to a project outside the profile owner's home.
#derive(ToJson, FromJson)
pub(all) struct SubmitRequest {
  project : String
  pkg : String
  number : Int32
  url : String
  accepted : Bool
  date : String
}

///|
/// A published article.
#derive(ToJson, FromJson)
pub(all) struct Post {
  title : String
  url : String
  date : String
  source : String
}

///|
/// Everything the README activity section shows. `generated_on` and the two windows are
/// in JST calendar days.
#derive(ToJson, FromJson)
pub(all) struct Activity {
  generated_on : String
  repo_days : Int32
  upstream_days : Int32
  repos : Array[Repo]
  upstream : Array[UpstreamPullRequest]
  packaging : Array[SubmitRequest]
  posts : Array[Post]
}

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

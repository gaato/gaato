///|
/// The saved upstream entries that came from one forge, told apart by the
/// forge's base URL. GitHub entries start with `https://github.com`, GitLab
/// and Gerrit ones with their instance's URL.
pub fn upstream_from(
  previous : Array[UpstreamPullRequest],
  base_url : String,
) -> Array[UpstreamPullRequest] {
  let prefix = base_url + "/"
  previous.filter(pr => pr.url.has_prefix(prefix))
}

///|
/// The saved posts that came from one feed, told apart by the feed's name.
pub fn posts_from(previous : Array[Post], source : String) -> Array[Post] {
  previous.filter(post => post.source == source)
}

///|
/// A GitHub Actions workflow command that shows up as an annotation on the
/// run, so a source that fell back to its saved entries is not silent.
/// Newlines would end the command, so they are escaped the way Actions reads
/// them.
pub fn warning_command(source : String, reason : String) -> String {
  let escaped = reason
    .replace(old="%", new="%25")
    .replace(old="\r", new="%0D")
    .replace(old="\n", new="%0A")
  "::warning title=\{source} unavailable::\{source} could not be fetched; keeping the previous entries. \{escaped}"
}

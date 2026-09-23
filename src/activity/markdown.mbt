///|
let activity_start : String = "<!-- activity:start -->"

///|
let activity_end : String = "<!-- activity:end -->"

///|
fn markdown_text(value : String) -> String {
  let sb = StringBuilder()
  for c in value {
    match c {
      '\\' | '`' | '*' | '_' | '[' | ']' | '!' | '|' | '<' | '>' => {
        sb.write_char('\\')
        sb.write_char(c)
      }
      '\n' | '\r' | '\t' => sb.write_char(' ')
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn markdown_url(value : String) -> String {
  let sb = StringBuilder()
  for c in value {
    match c {
      '(' | ')' | '\\' => {
        sb.write_char('\\')
        sb.write_char(c)
      }
      ' ' => sb.write_string("%20")
      '<' => sb.write_string("%3C")
      '>' => sb.write_string("%3E")
      '\n' | '\r' | '\t' => ()
      _ => sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn markdown_link(label : String, url : String) -> String {
  "[\{markdown_text(label)}](\{markdown_url(url)})"
}

///|
fn github_link(label : String, path : String) -> String {
  markdown_link(label, "https://github.com/\{path}")
}

///|
fn short_name(name : String, login~ : String) -> String {
  match name.strip_prefix("\{login}/") {
    Some(rest) => rest.to_owned()
    None => name
  }
}

///|
/// Renders the recent activity section as Markdown for the profile README.
pub fn render_markdown(activity : Activity, login~ : String) -> String {
  let sb = StringBuilder()
  sb <+ "## Recent activity\n\n"
  sb <+ "### Working on\n\n"
  sb <+ "Commits, last \{activity.repo_days} days.\n\n"
  if activity.repos.length() == 0 {
    sb <+ "- Nothing yet.\n"
  }
  for repo in activity.repos {
    let unit = if repo.commits == 1 { "commit" } else { "commits" }
    sb <+
      "- \{github_link(short_name(repo.name, login~), repo.name)} — \{repo.commits} \{unit}"
    if repo.language != "" {
      sb <+ " (\{markdown_text(repo.language)})"
    }
    sb <+ "\n"
  }
  sb <+ "\n### Upstream\n\n"
  sb <+
    "PRs created in the last \{activity.upstream_days} days, currently open or merged.\n\n"
  if activity.upstream.length() == 0 {
    sb <+ "- Nothing yet.\n"
  }
  for upstream in activity.upstream {
    let unit = if upstream.prs == 1 { "PR" } else { "PRs" }
    sb <+
      "- \{github_link(upstream.owner, upstream.owner)} — \{upstream.prs} \{unit}"
    if upstream.repos.length() > 0 {
      let repos = upstream.repos.map(repo => {
        github_link(repo, "\{upstream.owner}/\{repo}")
      })
      sb <+ " in \{repos.join(", ")}"
    }
    sb <+ "\n"
  }
  sb <+ "\n### Writing\n\n"
  if activity.posts.length() == 0 {
    sb <+ "- Nothing yet.\n"
  }
  for post in activity.posts {
    sb <+
      "- \{markdown_text(post.date)} · \{markdown_link(post.title, post.url)}"
    if post.source != "" {
      sb <+ " (\{markdown_text(post.source)})"
    }
    sb <+ "\n"
  }
  sb <+
    "\nUpdated \{markdown_text(activity.generated_on)} · generated with MoonBit\n"
  sb.to_string()
}

///|
/// Replaces exactly one marked activity section, preserving the rest of README.
pub fn update_readme(
  readme : String,
  activity : Activity,
  login~ : String,
) -> String raise {
  guard readme.find(activity_start) is Some(start) else {
    fail("README activity start marker is missing")
  }
  let content_start = start + activity_start.length()
  guard readme[content_start:].find(activity_end) is Some(relative_end) else {
    fail("README activity end marker is missing")
  }
  let end = content_start + relative_end
  guard readme[:start].find(activity_end) is None &&
    readme[content_start:end].find(activity_start) is None &&
    readme[end + activity_end.length():].find(activity_start) is None &&
    readme[end + activity_end.length():].find(activity_end) is None else {
    fail("README activity markers are duplicated or out of order")
  }
  readme[:content_start].to_owned() +
  "\n\n" +
  render_markdown(activity, login~) +
  "\n" +
  readme[end:].to_owned()
}

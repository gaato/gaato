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
/// Pull request state, in GitHub's own colours: purple for merged, green for
/// open. Rendering them at the start of the line keeps the markers in one
/// column, so the mix is readable at a glance.
let merged_marker : String = "\u{1F7E3}"

///|
let open_marker : String = "\u{1F7E2}"

///|
fn short_name(name : String, login~ : String) -> String {
  match name.strip_prefix("\{login}/") {
    Some(rest) => rest.to_owned()
    None => name
  }
}

///|
/// The submit requests for one package, oldest first: the order an update
/// moves through a devel project into openSUSE:Factory.
priv struct PackageSubmissions {
  pkg : String
  requests : Array[SubmitRequest]
}

///|
/// Groups submit requests by package, most recently submitted package first.
fn group_by_package(
  requests : Array[SubmitRequest],
) -> Array[PackageSubmissions] {
  let by_package : Map[String, Array[SubmitRequest]] = Map([])
  for request in requests {
    match by_package.get(request.pkg) {
      Some(list) => list.push(request)
      None => by_package.set(request.pkg, [request])
    }
  }
  let groups : Array[PackageSubmissions] = []
  for pkg, list in by_package {
    list.sort_by((a, b) => {
      if a.date != b.date {
        a.date.compare(b.date)
      } else {
        a.number - b.number
      }
    })
    groups.push({ pkg, requests: list, })
  }
  groups.sort_by((a, b) => {
    let a_date = a.requests[a.requests.length() - 1].date
    let b_date = b.requests[b.requests.length() - 1].date
    if a_date != b_date {
      b_date.compare(a_date)
    } else {
      a.pkg.compare(b.pkg)
    }
  })
  groups
}

///|
/// One package's line: its latest state and date, then each project it was
/// submitted to, with consecutive requests to the same project sharing a name.
fn render_package(sb : StringBuilder, group : PackageSubmissions) -> Unit {
  let latest = group.requests[group.requests.length() - 1]
  let state = if latest.accepted { merged_marker } else { open_marker }
  let package_url = "\{obs_web_url}/package/show/\{latest.project}/\{group.pkg}"
  sb <+
    "- \{state} \{markdown_text(latest.date)} · \{markdown_link(group.pkg, package_url)} —"
  let mut project = ""
  for request in group.requests {
    if request.project != project {
      if project != "" {
        sb <+ " →"
      }
      sb <+ " \{markdown_text(request.project)}"
      project = request.project
    }
    sb <+ " \{markdown_link("#\{request.number}", request.url)}"
  }
  sb <+ "\n"
}

///|
/// Renders the recent activity section as Markdown for the profile README.
/// `max_upstream` and `max_packages` cap the pull request and package lists;
/// the rest is summarised in one trailing line, so the saved JSON can hold more
/// than the README shows.
pub fn render_markdown(
  activity : Activity,
  login~ : String,
  max_upstream? : Int = 20,
  max_packages? : Int = 10,
) -> String {
  let sb = StringBuilder()
  sb <+ "## Recent activity\n\n"
  sb <+ "### Upstream\n\n"
  sb <+
    "PRs and merge requests created in the last \{activity.upstream_days} days, currently \{merged_marker} merged or \{open_marker} open.\n\n"
  if activity.upstream.length() == 0 {
    sb <+ "- Nothing yet.\n"
  }
  let shown = activity.upstream[:activity.upstream.length().min(max_upstream)]
  for pr in shown {
    let state = if pr.merged { merged_marker } else { open_marker }
    sb <+
      "- \{state} \{markdown_text(pr.date)} · \{markdown_link(pr.reference, pr.url)} — \{markdown_text(pr.title)}\n"
  }
  let hidden = activity.upstream.length() - shown.length()
  if hidden > 0 {
    sb <+ "- …and \{hidden} more\n"
  }
  sb <+ "\n### Packaging\n\n"
  sb <+
    "openSUSE packages submitted through [OBS](\{obs_web_url}) in the last \{activity.upstream_days} days, currently \{merged_marker} accepted or \{open_marker} in review.\n\n"
  let packages = group_by_package(activity.packaging)
  if packages.length() == 0 {
    sb <+ "- Nothing yet.\n"
  }
  for group in packages[:packages.length().min(max_packages)] {
    render_package(sb, group)
  }
  if packages.length() > max_packages {
    sb <+ "- …and \{packages.length() - max_packages} more\n"
  }
  sb <+ "\n### Working on\n\n"
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
  sb <+ "\nUpdated \{markdown_text(activity.generated_on)}\n"
  sb.to_string()
}

///|
/// Replaces exactly one marked activity section, preserving the rest of README.
pub fn update_readme(
  readme : String,
  activity : Activity,
  login~ : String,
  max_upstream? : Int = 20,
  max_packages? : Int = 10,
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
  render_markdown(activity, login~, max_upstream~, max_packages~) +
  "\n" +
  readme[end:].to_owned()
}

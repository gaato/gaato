///|
let width : Int = 720

///|
let font : String = "-apple-system, BlinkMacSystemFont, Segoe UI, Hiragino Sans, Noto Sans CJK JP, sans-serif"

///|
let paper : String = "#f7f5ee"

///|
let ink : String = "#211f1b"

///|
let muted : String = "#686257"

///|
let accent : String = "#234f47"

///|
let rule : String = "#e6e2d6"

///|
let row_height : Int = 22

///|
let heading_height : Int = 30

///|
let padding : Int = 24

///|
let column_gap : Int = 24

///|
fn owner_prefix(login : String) -> String {
  "\{login}/"
}

///|
fn short_name(name : String, login~ : String) -> String {
  match name.strip_prefix(owner_prefix(login)) {
    Some(rest) => rest.to_owned()
    None => name
  }
}

///|
fn heading(
  sb : StringBuilder,
  x : Int,
  y : Int,
  title : String,
  note : String,
) -> Unit {
  sb <+
    "<text x=\"\{x}\" y=\"\{y}\" font-family=\"\{font}\" font-size=\"11\"><tspan font-weight=\"600\" letter-spacing=\"1.5\" fill=\"\{accent}\">\{escape_xml(title)}</tspan><tspan dx=\"10\" fill=\"\{muted}\">\{escape_xml(note)}</tspan></text>\n"
}

///|
fn text(
  sb : StringBuilder,
  x : Int,
  y : Int,
  content : String,
  size? : Int = 13,
  fill? : String = ink,
  anchor? : String = "start",
  weight? : String = "400",
) -> Unit {
  sb <+
    "<text x=\"\{x}\" y=\"\{y}\" text-anchor=\"\{anchor}\" font-family=\"\{font}\" font-size=\"\{size}\" font-weight=\"\{weight}\" fill=\"\{fill}\">\{escape_xml(content)}</text>\n"
}

///|
fn render_repos(
  sb : StringBuilder,
  activity : Activity,
  login~ : String,
  x : Int,
  y : Int,
  column_width : Int,
) -> Int {
  heading(sb, x, y, "WORKING ON", "commits, last \{activity.repo_days} days")
  let mut cursor = y + heading_height
  let label_width = 128
  let bar_x = x + label_width
  let count_width = 40
  let bar_max = column_width - label_width - count_width
  let most = activity.repos.fold(init=1, (acc, r) => acc.max(r.commits))
  for repo in activity.repos {
    let name = truncate_to_width(
      short_name(repo.name, login~),
      13.0,
      label_width.to_double() - 8.0,
    )
    text(sb, x, cursor, name)
    let bar = (bar_max * repo.commits / most).max(3)
    sb <+
      "<rect x=\"\{bar_x}\" y=\"\{cursor - 10}\" width=\"\{bar}\" height=\"10\" rx=\"2\" fill=\"\{repo.color}\"/>\n"
    text(
      sb,
      bar_x + bar + 6,
      cursor,
      repo.commits.to_string(),
      size=11,
      fill=muted,
    )
    cursor += row_height
  }
  // Legend: languages in order of first appearance.
  let seen : Map[String, String] = Map([])
  for repo in activity.repos {
    if repo.language != "" && !seen.contains(repo.language) {
      seen[repo.language] = repo.color
    }
  }
  if seen.length() > 0 {
    cursor += 4
    let mut lx = x
    for language, color in seen {
      sb <+
        "<circle cx=\"\{lx + 4}\" cy=\"\{cursor - 4}\" r=\"4\" fill=\"\{color}\"/>\n"
      text(sb, lx + 13, cursor, language, size=11, fill=muted)
      lx += 13 + text_width(language, 11.0).to_int() + 14
    }
    cursor += row_height
  }
  cursor
}

///|
fn render_upstream(
  sb : StringBuilder,
  activity : Activity,
  x : Int,
  y : Int,
  column_width : Int,
) -> Int {
  heading(
    sb,
    x,
    y,
    "UPSTREAM",
    "pull requests, last \{activity.upstream_days} days",
  )
  let mut cursor = y + heading_height
  let owner_width = 104
  let count_width = 28
  for u in activity.upstream {
    text(
      sb,
      x,
      cursor,
      truncate_to_width(u.owner, 13.0, owner_width.to_double() - 8.0),
    )
    let repos = u.repos.join(", ")
    let max_repo_width = (column_width - owner_width - count_width).to_double()
    text(
      sb,
      x + owner_width,
      cursor,
      truncate_to_width(repos, 11.0, max_repo_width),
      size=11,
      fill=muted,
    )
    text(
      sb,
      x + column_width,
      cursor,
      u.prs.to_string(),
      size=11,
      fill=muted,
      anchor="end",
    )
    cursor += row_height
  }
  if activity.upstream.length() == 0 {
    text(sb, x, cursor, "nothing yet", size=11, fill=muted)
    cursor += row_height
  }
  cursor
}

///|
fn render_posts(
  sb : StringBuilder,
  activity : Activity,
  x : Int,
  y : Int,
  column_width : Int,
) -> Int {
  heading(sb, x, y, "WRITING", "latest")
  let mut cursor = y + heading_height
  let date_width = 76
  for post in activity.posts {
    text(sb, x, cursor, post.date, size=11, fill=muted)
    let title = truncate_to_width(
      post.title,
      13.0,
      (column_width - date_width).to_double(),
    )
    sb <+ "<a href=\"\{escape_xml(post.url)}\">"
    text(sb, x + date_width, cursor, title)
    sb <+ "</a>\n"
    cursor += row_height
  }
  if activity.posts.length() == 0 {
    text(sb, x, cursor, "nothing yet", size=11, fill=muted)
    cursor += row_height
  }
  cursor
}

///|
/// Renders the activity card as a standalone SVG document.
pub fn render(activity : Activity, login~ : String) -> String {
  let column_width = (width - padding * 2 - column_gap) / 2
  let left_x = padding
  let right_x = padding + column_width + column_gap
  let top = padding + 12
  let body = StringBuilder()
  let left_end = render_repos(body, activity, login~, left_x, top, column_width)
  let upstream_end = render_upstream(body, activity, right_x, top, column_width)
  let right_end = render_posts(
    body,
    activity,
    right_x,
    upstream_end + 12,
    column_width,
  )
  let content_end = left_end.max(right_end)
  let height = content_end + 36
  let sb = StringBuilder()
  sb <+
    "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 \{width} \{height}\" width=\"\{width}\" height=\"\{height}\" role=\"img\" aria-labelledby=\"title desc\">\n"
  sb <+ "<title id=\"title\">Recent activity</title>\n"
  sb <+
    "<desc id=\"desc\">Repositories committed to, upstream pull requests and latest articles, regenerated daily from GitHub and RSS.</desc>\n"
  sb <+
    "<rect width=\"\{width}\" height=\"\{height}\" rx=\"18\" fill=\"\{paper}\"/>\n"
  sb <+
    "<line x1=\"\{right_x - column_gap / 2}\" y1=\"\{top - 8}\" x2=\"\{right_x - column_gap / 2}\" y2=\"\{content_end - 8}\" stroke=\"\{rule}\" stroke-width=\"1\"/>\n"
  sb.write_string(body.to_string())
  text(
    sb,
    width / 2,
    height - 16,
    "updated \{activity.generated_on} · generated with MoonBit",
    size=11,
    fill=muted,
    anchor="middle",
  )
  sb <+ "</svg>\n"
  sb.to_string()
}

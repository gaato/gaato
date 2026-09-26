///|
let sample_response : Json = {
  "user": {
    "recent": {
      "commitContributionsByRepository": [
        {
          "repository": {
            "nameWithOwner": "gaato/discord.mbt",
            "primaryLanguage": { "name": "MoonBit", "color": "#b92381" },
          },
          "contributions": { "totalCount": 247 },
        },
        {
          "repository": {
            "nameWithOwner": "gaato/zenn-content",
            "primaryLanguage": null,
          },
          "contributions": { "totalCount": 15 },
        },
        {
          "repository": {
            "nameWithOwner": "gaato/cordnim",
            "primaryLanguage": { "name": "Nim", "color": "#ffc200" },
          },
          "contributions": { "totalCount": 34 },
        },
      ],
    },
  },
}

///|
test "parse_repositories sorts recent commits" {
  let repos = @activity.parse_repositories(sample_response, max_repos=2)
  json_inspect(repos, content=[
    {
      "name": "gaato/discord.mbt",
      "commits": 247,
      "language": "MoonBit",
      "color": "#b92381",
    },
    {
      "name": "gaato/cordnim",
      "commits": 34,
      "language": "Nim",
      "color": "#ffc200",
    },
  ])
}

///|
test "parse_repositories rejects an unexpected shape" {
  try @activity.parse_repositories({ "errors": [] }) catch {
    err =>
      assert_true(err.to_string().contains("unexpected GraphQL response shape"))
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "upstream PRs include only recently opened open or merged PRs" {
  assert_true(@activity.pull_requests_query.contains("states: [OPEN, MERGED]"))
  assert_true(
    @activity.pull_requests_query.contains("field: CREATED_AT, direction: DESC"),
  )
  let first : Json = {
    "user": {
      "pullRequests": {
        "nodes": [
          {
            "createdAt": "2026-09-22T10:00:00Z",
            "state": "OPEN",
            "number": 12,
            "title": "Add a timeout to the poller",
            "url": "https://github.com/moonbitlang/async/pull/12",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "moonbitlang/async",
              "owner": { "login": "moonbitlang" },
            },
          },
          {
            "createdAt": "2026-09-20T10:00:00Z",
            "state": "MERGED",
            "number": 34,
            "title": "Fix moon test on Windows",
            "url": "https://github.com/moonbitlang/moon/pull/34",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "moonbitlang/moon",
              "owner": { "login": "moonbitlang" },
            },
          },
          {
            "createdAt": "2026-09-19T10:00:00Z",
            "state": "CLOSED",
            "number": 56,
            "title": "Closed, so excluded",
            "url": "https://github.com/openSUSE/opi/pull/56",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "openSUSE/opi",
              "owner": { "login": "openSUSE" },
            },
          },
          {
            "createdAt": "2026-09-18T10:00:00Z",
            "state": "MERGED",
            "number": 78,
            "title": "Own repository, so excluded",
            "url": "https://github.com/gaato/gaato.net/pull/78",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "gaato/gaato.net",
              "owner": { "login": "gaato" },
            },
          },
          {
            "createdAt": "2026-09-17T10:00:00Z",
            "state": "OPEN",
            "number": 90,
            "title": "Someone else's PR, so excluded",
            "url": "https://github.com/openSUSE/opi/pull/90",
            "author": { "login": "someone-else" },
            "repository": {
              "nameWithOwner": "openSUSE/opi",
              "owner": { "login": "openSUSE" },
            },
          },
        ],
        "pageInfo": { "hasNextPage": true, "endCursor": "cursor-1" },
      },
    },
  }
  let (first_prs, next) = @activity.parse_pull_request_page(
    first,
    from="2025-09-23T00:00:00Z",
    login="gaato",
  )
  debug_inspect(next, content="Some(\"cursor-1\")")
  let second : Json = {
    "user": {
      "pullRequests": {
        "nodes": [
          {
            "createdAt": "2025-09-23T00:00:00Z",
            "state": "MERGED",
            "number": 1,
            "title": "Exactly on the cutoff",
            "url": "https://github.com/moonbitlang/async/pull/1",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "moonbitlang/async",
              "owner": { "login": "moonbitlang" },
            },
          },
          {
            "createdAt": "2025-09-22T23:59:59Z",
            "state": "OPEN",
            "number": 2,
            "title": "Past the cutoff, so excluded",
            "url": "https://github.com/systemd/systemd/pull/2",
            "author": { "login": "gaato" },
            "repository": {
              "nameWithOwner": "systemd/systemd",
              "owner": { "login": "systemd" },
            },
          },
        ],
        "pageInfo": { "hasNextPage": true, "endCursor": "cursor-2" },
      },
    },
  }
  let (second_prs, end) = @activity.parse_pull_request_page(
    second,
    from="2025-09-23T00:00:00Z",
    login="gaato",
  )
  assert_true(end is None)
  json_inspect(@activity.sort_upstream(first_prs + second_prs), content=[
    {
      "owner": "moonbitlang",
      "repo": "async",
      "number": 12,
      "reference": "moonbitlang/async#12",
      "title": "Add a timeout to the poller",
      "url": "https://github.com/moonbitlang/async/pull/12",
      "merged": false,
      "date": "2026-09-22",
    },
    {
      "owner": "moonbitlang",
      "repo": "moon",
      "number": 34,
      "reference": "moonbitlang/moon#34",
      "title": "Fix moon test on Windows",
      "url": "https://github.com/moonbitlang/moon/pull/34",
      "merged": true,
      "date": "2026-09-20",
    },
    {
      "owner": "moonbitlang",
      "repo": "async",
      "number": 1,
      "reference": "moonbitlang/async#1",
      "title": "Exactly on the cutoff",
      "url": "https://github.com/moonbitlang/async/pull/1",
      "merged": true,
      "date": "2025-09-23",
    },
  ])
}

///|
let sample_rss : String =
  #|<?xml version="1.0" encoding="UTF-8"?>
  #|<rss version="2.0">
  #|  <channel>
  #|    <title>gaato</title>
  #|    <item>
  #|      <title>Ctrl &amp; the mouse</title>
  #|      <link>https://gaato.net/articles/stuck-ctrl/</link>
  #|      <pubDate>Sun, 05 Jul 2026 15:00:00 GMT</pubDate>
  #|    </item>
  #|    <item>
  #|      <title><![CDATA[MMD を Wine で動かす <2>]]></title>
  #|      <link>https://zenn.dev/gaato/articles/mmd-wine-linux</link>
  #|      <pubDate>Mon, 23 Mar 2026 13:06:58 GMT</pubDate>
  #|    </item>
  #|    <item>
  #|      <title>no date</title>
  #|      <link>https://example.invalid/</link>
  #|    </item>
  #|  </channel>
  #|</rss>

///|
test "parse_rss decodes entities and CDATA and converts dates to JST" {
  let posts = @activity.parse_rss(sample_rss, source="gaato.net")
  json_inspect(posts, content=[
    {
      "title": "Ctrl & the mouse",
      "url": "https://gaato.net/articles/stuck-ctrl/",
      "date": "2026-07-06",
      "source": "gaato.net",
    },
    {
      "title": "MMD を Wine で動かす <2>",
      "url": "https://zenn.dev/gaato/articles/mmd-wine-linux",
      "date": "2026-03-23",
      "source": "gaato.net",
    },
  ])
}

///|
test "latest_posts merges lists newest first" {
  let a = @activity.parse_rss(sample_rss, source="a")
  let b : Array[@activity.Post] = [
    { title: "newest", url: "u", date: "2026-09-11", source: "b", },
  ]
  let merged = @activity.latest_posts([a, b], limit=2)
  debug_inspect(
    merged.map(p => p.date),
    content="[\"2026-09-11\", \"2026-07-06\"]",
  )
}

///|
test "dates" {
  inspect(@activity.jst_date(1790083609L), content="2026-09-22")
  inspect(@activity.utc_timestamp(1790083609L), content="2026-09-22T13:26:49Z")
  inspect(
    @activity.utc_midnight_days_ago(1790083609L, 90),
    content="2026-06-24T00:00:00Z",
  )
  debug_inspect(
    @activity.parse_rfc2822("Sat, 29 Aug 2026 15:00:00 +0900").map(
      @activity.jst_date,
    ),
    content="Some(\"2026-08-29\")",
  )
  debug_inspect(@activity.parse_rfc2822("garbage"), content="None")
  debug_inspect(
    @activity.parse_iso8601_utc("2026-09-22T13:26:49Z").map(@activity.jst_date),
    content="Some(\"2026-09-22\")",
  )
  // 00:30 UTC is already the next day in JST.
  debug_inspect(
    @activity.parse_iso8601_utc("2026-09-22T00:30:00Z").map(@activity.jst_date),
    content="Some(\"2026-09-22\")",
  )
  debug_inspect(
    @activity.parse_iso8601_utc("2026-09-22T15:30:00Z").map(@activity.jst_date),
    content="Some(\"2026-09-23\")",
  )
  debug_inspect(@activity.parse_iso8601_utc("2026-09-22"), content="None")
  debug_inspect(
    @activity.parse_iso8601_utc("2026-09-22T13:26:49+09:00"),
    content="None",
  )
}

///|
test "RSS text decoding" {
  inspect(
    @activity.unescape_xml("&#x41;&#66;&amp;&unknown;&"),
    content="AB&&unknown;&",
  )
}

///|
test "render Markdown activity and preserve README outside its markers" {
  let activity : @activity.Activity = {
    generated_on: "2026-09-22",
    repo_days: 90,
    upstream_days: 365,
    repos: [
      {
        name: "gaato/discord.mbt",
        commits: 247,
        language: "MoonBit",
        color: "#b92381",
      },
      { name: "gaato/cordnim", commits: 34, language: "Nim", color: "#ffc200", },
    ],
    upstream: [
      {
        owner: "moonbitlang",
        repo: "async",
        number: 12,
        reference: "moonbitlang/async#12",
        title: "Add a timeout to the poller",
        url: "https://github.com/moonbitlang/async/pull/12",
        merged: false,
        date: "2026-09-22",
      },
    ],
    packaging: [],
    posts: [
      {
        title: "Ctrl & the [mouse] <2>\nnext",
        url: "https://gaato.net/articles/stuck-ctrl/(test)?a=1&b=2",
        date: "2026-07-06",
        source: "gaato.net",
      },
    ],
  }
  let readme = "# Intro\n\n<!-- activity:start -->\nold\n<!-- activity:end -->\n\nFooter\n"
  let updated = @activity.update_readme(readme, activity, login="gaato")
  assert_true(updated.has_prefix("# Intro\n\n<!-- activity:start -->\n\n"))
  assert_true(updated.has_suffix("<!-- activity:end -->\n\nFooter\n"))
  assert_true(
    updated.contains(
      "[discord.mbt](https://github.com/gaato/discord.mbt) — 247 commits (MoonBit)",
    ),
  )
  assert_true(
    updated.contains(
      "- 🟢 2026-09-22 · [moonbitlang/async#12](https://github.com/moonbitlang/async/pull/12) — Add a timeout to the poller",
    ),
  )
  assert_true(
    updated.contains(
      "[Ctrl & the \\[mouse\\] \\<2\\> next](https://gaato.net/articles/stuck-ctrl/\\(test\\)?a=1&b=2)",
    ),
  )
  assert_true(updated.contains("Updated 2026-09-22\n"))
  assert_false(updated.contains("generated with MoonBit"))
  assert_false(updated.contains("\nold\n"))
  inspect(
    @activity.update_readme(updated, activity, login="gaato"),
    content=updated,
  )
}

///|
/// Builds an upstream PR whose fields only matter through `number`.
fn upstream_pr(
  number : Int,
  merged? : Bool = true,
  date? : String = "2026-09-22",
) -> @activity.UpstreamPullRequest {
  {
    owner: "openSUSE",
    repo: "opi",
    number,
    reference: "openSUSE/opi#\{number}",
    title: "PR \{number}",
    url: "https://github.com/openSUSE/opi/pull/\{number}",
    merged,
    date,
  }
}

///|
fn upstream_activity(
  prs : Array[@activity.UpstreamPullRequest],
) -> @activity.Activity {
  {
    generated_on: "2026-09-23",
    repo_days: 90,
    upstream_days: 365,
    repos: [],
    upstream: prs,
    packaging: [],
    posts: [],
  }
}

///|
test "each upstream PR renders with its state" {
  let markdown = @activity.render_markdown(
    upstream_activity([
      upstream_pr(1, merged=true),
      upstream_pr(2, merged=false, date="2026-09-21"),
    ]),
    login="gaato",
  )
  assert_true(
    markdown.contains(
      "- 🟣 2026-09-22 · [openSUSE/opi#1](https://github.com/openSUSE/opi/pull/1) — PR 1",
    ),
  )
  assert_true(
    markdown.contains(
      "- 🟢 2026-09-21 · [openSUSE/opi#2](https://github.com/openSUSE/opi/pull/2) — PR 2",
    ),
  )
  assert_false(markdown.contains("more"))
}

///|
test "upstream PRs beyond max_upstream are summarised, not dropped" {
  let prs = []
  for i in 1..<=22 {
    prs.push(upstream_pr(i))
  }
  let activity = upstream_activity(prs)
  let markdown = @activity.render_markdown(activity, login="gaato")
  assert_true(markdown.contains("/pull/20)"))
  assert_false(markdown.contains("/pull/21)"))
  assert_true(markdown.contains("- …and 2 more\n"))
  // The saved activity still holds every PR, so the cap can change without
  // fetching again.
  assert_true(
    @activity.render_markdown(activity, login="gaato", max_upstream=22).contains(
      "/pull/22)",
    ),
  )
  assert_false(
    @activity.render_markdown(activity, login="gaato", max_upstream=22).contains(
      "more",
    ),
  )
}

///|
test "empty activity and invalid README markers" {
  let empty : @activity.Activity = {
    generated_on: "2026-09-22",
    repo_days: 90,
    upstream_days: 365,
    repos: [],
    upstream: [],
    packaging: [],
    posts: [],
  }
  let rendered = @activity.render_markdown(empty, login="gaato")
  assert_true(
    rendered.contains(
      "### Working on\n\nCommits, last 90 days.\n\n- Nothing yet.",
    ),
  )
  assert_true(
    rendered.contains(
      "### Upstream\n\nPRs and merge requests created in the last 365 days, currently 🟣 merged or 🟢 open.\n\n- Nothing yet.",
    ),
  )
  assert_true(rendered.contains("### Packaging\n\nopenSUSE packages"))
  assert_true(
    rendered.contains("in review.\n\n- Nothing yet.\n\n### Working on"),
  )
  assert_true(rendered.contains("### Writing\n\n- Nothing yet."))
  for
    invalid in [
      "no markers", "<!-- activity:start -->\nmissing end", "<!-- activity:end --><!-- activity:start -->",
      "<!-- activity:start --><!-- activity:end --><!-- activity:start --><!-- activity:end -->",
    ] {
    try @activity.update_readme(invalid, empty, login="gaato") catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid README markers to fail")
    }
  }
}

///|
test "OBS request search asks for accepted or pending submit requests" {
  inspect(
    @activity.obs_submit_request_search("gaato"),
    content="/search/request?match=%40creator%3D%27gaato%27%20and%20action%2F%40type%3D%27submit%27%20and%20(state%2F%40name%3D%27accepted%27%20or%20state%2F%40name%3D%27new%27%20or%20state%2F%40name%3D%27review%27)",
  )
}

///|
let sample_submit_requests : String =
  #|<collection matches="5">
  #|  <request id="1377001" creator="gaato">
  #|    <action type="submit">
  #|      <source project="devel:tools:scm" package="ghq" rev="3"/>
  #|      <target project="openSUSE:Factory" package="ghq"/>
  #|    </action>
  #|    <state name="accepted" who="anag_factory" when="2026-09-08T14:53:30" created="2026-09-05T15:38:41">
  #|      <comment/>
  #|    </state>
  #|    <review state="accepted" by_group="factory-staging">
  #|      <history who="staging-bot" when="2026-09-06T15:07:40">
  #|        <description>Review got accepted</description>
  #|      </history>
  #|    </review>
  #|    <description>
  #|
  #|  Update to 1.8.0 &amp; fix &lt;build&gt;&#xD;
  #|  - changelog line</description>
  #|  </request>
  #|  <request id="1377002" creator="gaato">
  #|    <action type="delete">
  #|      <target project="M17N" package="old"/>
  #|    </action>
  #|    <action type="submit">
  #|      <source project="home:gaato:branches:M17N" package="karukan" rev="7"/>
  #|      <target project="M17N" package="karukan"/>
  #|    </action>
  #|    <state name="review" who="gaato" when="2026-09-20T23:00:00" created="2026-09-20T16:00:00"/>
  #|    <description>- Update to 0.3.0 and ship the
  #|  fcitx5 addon separately
  #|- Drop an obsolete patch</description>
  #|  </request>
  #|  <request id="1377003" creator="gaato">
  #|    <action type="submit">
  #|      <source project="home:gaato:branches:foo" package="bar" rev="1"/>
  #|      <target project="home:gaato" package="bar"/>
  #|    </action>
  #|    <state name="accepted" who="gaato" when="2026-09-01T00:00:00" created="2026-09-01T00:00:00"/>
  #|    <description>Own home project</description>
  #|  </request>
  #|  <request id="1377004" creator="gaato">
  #|    <action type="submit">
  #|      <source project="home:gaato" package="baz" rev="1"/>
  #|      <target project="X11:Utilities" package="baz"/>
  #|    </action>
  #|    <state name="declined" who="someone" when="2026-09-02T00:00:00" created="2026-09-01T00:00:00"/>
  #|    <description>Declined</description>
  #|  </request>
  #|  <request id="1200000" creator="gaato">
  #|    <action type="submit">
  #|      <source project="home:gaato" package="old" rev="1"/>
  #|      <target project="X11:Utilities" package="old"/>
  #|    </action>
  #|    <state name="accepted" who="someone" when="2025-01-02T00:00:00" created="2025-01-01T00:00:00"/>
  #|    <description>Too old</description>
  #|  </request>
  #|</collection>

///|
test "OBS submit requests are parsed by element path" {
  let requests = @activity.parse_submit_requests(
    sample_submit_requests,
    from="2025-09-27T00:00:00Z",
    login="gaato",
  )
  json_inspect(requests, content=[
    {
      "project": "openSUSE:Factory",
      "pkg": "ghq",
      "number": 1377001,
      "url": "https://build.opensuse.org/request/show/1377001",
      "accepted": true,
      "date": "2026-09-06",
    },
    {
      "project": "M17N",
      "pkg": "karukan",
      "number": 1377002,
      "url": "https://build.opensuse.org/request/show/1377002",
      "accepted": false,
      "date": "2026-09-21",
    },
  ])
}

///|
fn submit_request(
  project : String,
  pkg : String,
  number : Int,
  date : String,
  accepted? : Bool = true,
) -> @activity.SubmitRequest {
  {
    project,
    pkg,
    number,
    url: "https://build.opensuse.org/request/show/\{number}",
    accepted,
    date,
  }
}

///|
test "packaging groups submit requests by package" {
  let activity : @activity.Activity = {
    ..upstream_activity([]),
    packaging: [
      submit_request("openSUSE:Factory", "ghq", 3, "2026-09-06"),
      submit_request("devel:tools:scm", "ghq", 1, "2026-09-06"),
      submit_request("M17N", "karukan", 10, "2026-03-02"),
      submit_request("M17N", "karukan", 11, "2026-09-20"),
      submit_request(
        "openSUSE:Factory",
        "karukan",
        12,
        "2026-09-22",
        accepted=false,
      ),
    ],
  }
  let markdown = @activity.render_markdown(activity, login="gaato")
  assert_true(
    markdown.contains(
      "### Packaging\n\nopenSUSE packages submitted through [OBS](https://build.opensuse.org) in the last 365 days, currently 🟣 accepted or 🟢 in review.\n\n" +
      "- 🟢 2026-09-22 · [karukan](https://build.opensuse.org/package/show/openSUSE:Factory/karukan) — M17N [#10](https://build.opensuse.org/request/show/10) [#11](https://build.opensuse.org/request/show/11) → openSUSE:Factory [#12](https://build.opensuse.org/request/show/12)\n" +
      "- 🟣 2026-09-06 · [ghq](https://build.opensuse.org/package/show/openSUSE:Factory/ghq) — devel:tools:scm [#1](https://build.opensuse.org/request/show/1) → openSUSE:Factory [#3](https://build.opensuse.org/request/show/3)\n\n### Working on",
    ),
  )
  let capped = @activity.render_markdown(
    activity,
    login="gaato",
    max_packages=1,
  )
  assert_false(capped.contains("[ghq]"))
  assert_true(capped.contains("- …and 1 more\n\n### Working on"))
}

///|
test "parse_submit_requests rejects an unexpected response" {
  try
    @activity.parse_submit_requests(
      "<status code=\"unknown\"/>",
      from="2025-09-27T00:00:00Z",
      login="gaato",
    )
  catch {
    err =>
      assert_true(err.to_string().contains("unexpected OBS request response"))
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
/// One GitLab merge request as the listing API returns it.
fn mr(
  iid : Int,
  state : String,
  reference : String,
  author? : String = "gaato",
) -> Json {
  {
    "iid": iid.to_double(),
    "title": "MR \{iid}",
    "state": state,
    "created_at": "2026-02-02T14:16:10.363Z",
    "web_url": "https://invent.kde.org/\{reference}",
    "author": { "username": author },
    "references": { "full": reference },
  }
}

///|
test "KDE merge requests become upstream entries" {
  inspect(
    @activity.gitlab_merge_requests_path(
      "gaato",
      from="2025-09-27T00:00:00Z",
      page=2,
    ),
    content="/api/v4/merge_requests?scope=all&author_username=gaato&created_after=2025-09-27T00:00:00Z&per_page=100&page=2",
  )
  let prs = @activity.parse_gitlab_merge_requests(
    [
      mr(147, "merged", "frameworks/kholidays!147"),
      mr(3, "opened", "plasma/sub/group/project!3"),
      mr(4, "closed", "frameworks/kholidays!4"),
      mr(5, "merged", "gaato/kholidays!5"),
      mr(6, "merged", "frameworks/kholidays!6", author="someone"),
    ],
    login="gaato",
  )
  json_inspect(prs, content=[
    {
      "owner": "frameworks",
      "repo": "kholidays",
      "number": 147,
      "reference": "frameworks/kholidays!147",
      "title": "MR 147",
      "url": "https://invent.kde.org/frameworks/kholidays!147",
      "merged": true,
      "date": "2026-02-02",
    },
    {
      "owner": "plasma/sub/group",
      "repo": "project",
      "number": 3,
      "reference": "plasma/sub/group/project!3",
      "title": "MR 3",
      "url": "https://invent.kde.org/plasma/sub/group/project!3",
      "merged": false,
      "date": "2026-02-02",
    },
  ])
  let markdown = @activity.render_markdown(
    upstream_activity(prs),
    login="gaato",
  )
  assert_true(
    markdown.contains(
      "- 🟣 2026-02-02 · [frameworks/kholidays\\!147](https://invent.kde.org/frameworks/kholidays!147) — MR 147\n",
    ),
  )
}

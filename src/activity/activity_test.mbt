///|
let sample_response : Json = {
  "data": {
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
    "data": {
      "user": {
        "pullRequests": {
          "nodes": [
            {
              "createdAt": "2026-09-22T10:00:00Z",
              "state": "OPEN",
              "author": { "login": "gaato" },
              "repository": {
                "nameWithOwner": "moonbitlang/async",
                "owner": { "login": "moonbitlang" },
              },
            },
            {
              "createdAt": "2026-09-20T10:00:00Z",
              "state": "MERGED",
              "author": { "login": "gaato" },
              "repository": {
                "nameWithOwner": "moonbitlang/moon",
                "owner": { "login": "moonbitlang" },
              },
            },
            {
              "createdAt": "2026-09-19T10:00:00Z",
              "state": "CLOSED",
              "author": { "login": "gaato" },
              "repository": {
                "nameWithOwner": "openSUSE/opi",
                "owner": { "login": "openSUSE" },
              },
            },
            {
              "createdAt": "2026-09-18T10:00:00Z",
              "state": "MERGED",
              "author": { "login": "gaato" },
              "repository": {
                "nameWithOwner": "gaato/gaato.net",
                "owner": { "login": "gaato" },
              },
            },
            {
              "createdAt": "2026-09-17T10:00:00Z",
              "state": "OPEN",
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
    },
  }
  let (first_prs, next) = @activity.parse_pull_request_page(
    first,
    from="2025-09-23T00:00:00Z",
    login="gaato",
  )
  debug_inspect(next, content="Some(\"cursor-1\")")
  let second : Json = {
    "data": {
      "user": {
        "pullRequests": {
          "nodes": [
            {
              "createdAt": "2025-09-23T00:00:00Z",
              "state": "MERGED",
              "author": { "login": "gaato" },
              "repository": {
                "nameWithOwner": "moonbitlang/async",
                "owner": { "login": "moonbitlang" },
              },
            },
            {
              "createdAt": "2025-09-22T23:59:59Z",
              "state": "OPEN",
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
    },
  }
  let (second_prs, end) = @activity.parse_pull_request_page(
    second,
    from="2025-09-23T00:00:00Z",
    login="gaato",
  )
  assert_true(end is None)
  json_inspect(@activity.group_upstream(first_prs + second_prs), content=[
    {
      "owner": "moonbitlang",
      "repos": ["async", "moon"],
      "prs": 3,
      "open": 1,
      "merged": 2,
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
        repos: ["async", "moon"],
        prs: 5,
        open: Some(1),
        merged: Some(4),
      },
    ],
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
      "[moonbitlang](https://github.com/moonbitlang) — merged 4 · open 1 in [async](https://github.com/moonbitlang/async)",
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
test "saved activity without PR state counts still renders its total" {
  let legacy : @activity.Upstream = @json.from_json({
    "owner": "openSUSE",
    "repos": ["opi"],
    "prs": 2,
  })
  assert_true(legacy.open is None && legacy.merged is None)
  let activity : @activity.Activity = {
    generated_on: "2026-09-23",
    repo_days: 90,
    upstream_days: 365,
    repos: [],
    upstream: [legacy],
    posts: [],
  }
  assert_true(
    @activity.render_markdown(activity, login="gaato").contains(
      "[openSUSE](https://github.com/openSUSE) — 2 PRs in [opi](https://github.com/openSUSE/opi)",
    ),
  )
}

///|
test "single-state upstream owners include zero for the other state" {
  let upstream = @activity.group_upstream([
    { owner: "a", repo: "one", merged: false, },
    { owner: "b", repo: "two", merged: true, },
  ])
  json_inspect(upstream, content=[
    { "owner": "a", "repos": ["one"], "prs": 1, "open": 1, "merged": 0 },
    { "owner": "b", "repos": ["two"], "prs": 1, "open": 0, "merged": 1 },
  ])
  let activity : @activity.Activity = {
    generated_on: "2026-09-23",
    repo_days: 90,
    upstream_days: 365,
    repos: [],
    upstream,
    posts: [],
  }
  let markdown = @activity.render_markdown(activity, login="gaato")
  assert_true(markdown.contains("[a](https://github.com/a) — open 1 in"))
  assert_true(markdown.contains("[b](https://github.com/b) — merged 1 in"))
  assert_false(markdown.contains("open 0"))
  assert_false(markdown.contains("merged 0"))
}

///|
test "empty activity and invalid README markers" {
  let empty : @activity.Activity = {
    generated_on: "2026-09-22",
    repo_days: 90,
    upstream_days: 365,
    repos: [],
    upstream: [],
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
      "### Upstream\n\nPRs created in the last 365 days, currently open or merged.\n\n- Nothing yet.",
    ),
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

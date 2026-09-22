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
      "year": {
        "pullRequestContributionsByRepository": [
          {
            "repository": {
              "nameWithOwner": "moonbitlang/async",
              "owner": { "login": "moonbitlang" },
            },
            "contributions": { "totalCount": 4 },
          },
          {
            "repository": {
              "nameWithOwner": "gaato/gaato.net",
              "owner": { "login": "gaato" },
            },
            "contributions": { "totalCount": 5 },
          },
          {
            "repository": {
              "nameWithOwner": "moonbitlang/moon",
              "owner": { "login": "moonbitlang" },
            },
            "contributions": { "totalCount": 1 },
          },
          {
            "repository": {
              "nameWithOwner": "systemd/systemd",
              "owner": { "login": "systemd" },
            },
            "contributions": { "totalCount": 1 },
          },
        ],
      },
    },
  },
}

///|
test "parse_contributions sorts repos and groups upstream by owner" {
  let (repos, upstream) = @activity.parse_contributions(
    sample_response,
    login="gaato",
    max_repos=2,
  )
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
  json_inspect(upstream, content=[
    { "owner": "moonbitlang", "repos": ["async", "moon"], "prs": 5 },
    { "owner": "systemd", "repos": ["systemd"], "prs": 1 },
  ])
}

///|
test "parse_contributions rejects an unexpected shape" {
  try @activity.parse_contributions({ "errors": [] }, login="gaato") catch {
    err =>
      assert_true(err.to_string().contains("unexpected GraphQL response shape"))
  } noraise {
    _ => fail("expected to fail")
  }
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
test "text helpers" {
  inspect(@activity.escape_xml("a<b&c\"d"), content="a&lt;b&amp;c&quot;d")
  inspect(
    @activity.unescape_xml("&#x41;&#66;&amp;&unknown;&"),
    content="AB&&unknown;&",
  )
  inspect(
    @activity.truncate_to_width("日本語のタイトルです", 13.0, 60.0),
    content="日本語の…",
  )
  inspect(@activity.truncate_to_width("short", 13.0, 60.0), content="short")
}

///|
test "render produces a well-formed card" {
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
    upstream: [{ owner: "moonbitlang", repos: ["async", "moon"], prs: 5, }],
    posts: [
      {
        title: "Ctrl & the mouse",
        url: "https://gaato.net/articles/stuck-ctrl/?a=1&b=2",
        date: "2026-07-06",
        source: "gaato.net",
      },
    ],
  }
  let svg = @activity.render(activity, login="gaato")
  assert_true(svg.has_prefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
  assert_true(svg.has_suffix("</svg>\n"))
  assert_true(svg.contains(">discord.mbt</text>"))
  assert_true(svg.contains(">Ctrl &amp; the mouse</text>"))
  assert_true(
    svg.contains("href=\"https://gaato.net/articles/stuck-ctrl/?a=1&amp;b=2\""),
  )
  assert_true(svg.contains("updated 2026-09-22 · generated with MoonBit"))
  assert_false(svg.contains("gaato/discord.mbt"))
}

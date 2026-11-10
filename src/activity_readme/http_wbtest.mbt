///|
async test "source client retries, follows redirects and bounds exchanges" {
  let requests : Array[@http.Request] = []
  let options : Array[@http.SendOptions] = []
  let mut closed = false
  let backend = @client.from_fn(
    (request, opts) => {
      requests.push(request)
      options.push(opts)
      match requests.length() {
        1 =>
          @http.Response::new(
            503,
            headers=@http.Headers::of([("Retry-After", "0")]),
          )
        2 =>
          @http.Response::new(
            302,
            headers=@http.Headers::of([
              ("Location", "/feed.xml"),
              ("Set-Cookie", "sid=fixture; Path=/; Secure"),
            ]),
          )
        _ => @http.Response::new(200, body=Bytes(b"feed\xff"))
      }
    },
    on_close=() => closed = true,
  )
  let client = source_client(
    backend,
    @runtime.AsyncClock::new(),
    headers=@http.Headers::of([("User-Agent", user_agent)]),
  )
  defer client.close()
  assert_eq(fetch_feed(client, "https://example.test/start"), "feed�")
  assert_eq(requests.map(r => r.url), [
    "https://example.test/start", "https://example.test/start", "https://example.test/feed.xml",
  ])
  for request in requests {
    assert_eq(request.headers.get("User-Agent"), Some(user_agent))
    assert_eq(request.headers.get("Authorization"), None)
  }
  assert_eq(requests[2].headers.get("Cookie"), Some("sid=fixture"))
  for option in options {
    assert_true(option.timeout_ms is Some(ms) && ms > 0 && ms <= 30_000)
    assert_eq(
      option.body,
      @http.BodyTiming::Exchange(max_bytes=64 * 1024 * 1024),
    )
  }
  client.close()
  assert_true(closed)
}

///|
async test "OBS auth follows same origin and is stripped across origins" {
  let requests : Array[@http.Request] = []
  let backend = @client.from_fn((request, _) => {
    requests.push(request)
    match requests.length() {
      1 =>
        @http.Response::new(
          302,
          headers=@http.Headers::of([("Location", "/same-origin")]),
        )
      2 =>
        @http.Response::new(
          302,
          headers=@http.Headers::of([
            ("Location", "https://other.test/requests"),
          ]),
        )
      _ => @http.Response::new(200, body=Bytes(b"<collection/>"))
    }
  })
  let obs = source_client(
    backend,
    @runtime.AsyncClock::new(),
    base_url=obs_api_url,
    headers=obs_headers("fixture"),
  )
  defer obs.close()
  assert_eq(fetch_submit_requests(obs, 0L).length(), 0)
  assert_eq(
    requests[0].url,
    obs_api_url + @activity.obs_submit_request_search(login),
  )
  assert_eq(
    requests[0].headers.get("Authorization"),
    Some("Basic Z2FhdG86Zml4dHVyZQ=="),
  )
  assert_eq(
    requests[1].headers.get("Authorization"),
    requests[0].headers.get("Authorization"),
  )
  assert_eq(requests[2].headers.get("Authorization"), None)
  assert_eq(requests[2].headers.get("Accept"), Some("application/xml"))
}

///|
async test "HTTP rejection and malformed JSON keep previous source entries" {
  let mut calls = 0
  let client = source_client(
    @client.from_fn((_, _) => {
      calls += 1
      if calls == 1 {
        @http.Response::new(404, body=Bytes(b"not found"))
      } else {
        @http.Response::new(200, body=Bytes(b"not JSON"))
      }
    }),
    @runtime.AsyncClock::new(),
    headers=@http.Headers::empty(),
  )
  defer client.close()
  let previous : Array[@activity.UpstreamPullRequest] = [
    {
      owner: "upstream",
      repo: "project",
      number: 1,
      reference: "upstream/project!1",
      title: "saved",
      url: "https://example.test/1",
      merged: false,
      date: "2026-11-10",
    },
  ]
  assert_eq(
    fetch_or_keep("GitLab", previous, () => {
      fetch_merge_requests(client, "https://example.test", 0L)
    }).map(item => item.to_json()),
    previous.map(item => item.to_json()),
  )
  assert_eq(
    fetch_or_keep("GitLab", previous, () => {
      fetch_merge_requests(client, "https://example.test", 0L)
    }).map(item => item.to_json()),
    previous.map(item => item.to_json()),
  )
  assert_eq(calls, 2)
}

///|
async test "GraphQL failure and invalid data keep previous repositories" {
  let mut calls = 0
  let backend = @client.from_fn((_, _) => {
    calls += 1
    let body = if calls == 1 {
      b"{\"errors\":[{\"message\":\"fixture failure\"}]}"
    } else {
      b"{\"data\":{\"unexpected\":true}}"
    }
    @http.Response::new(200, body=Bytes(body))
  })
  defer backend.close()
  let gh = @github.GitHub::new(
    backend,
    @runtime.AsyncClock::new(),
    limiter=@client.NoLimiter::new(),
  )
  let previous : Array[@activity.Repo] = [
    { name: "gaato/saved", commits: 1, language: "", color: "#9a948a", },
  ]
  assert_eq(
    fetch_or_keep("GitHub", previous, () => fetch_repositories(gh, 0L)).map(item => {
      item.to_json()
    }),
    previous.map(item => item.to_json()),
  )
  assert_eq(
    fetch_or_keep("GitHub", previous, () => fetch_repositories(gh, 0L)).map(item => {
      item.to_json()
    }),
    previous.map(item => item.to_json()),
  )
  assert_eq(calls, 2)
}

///|
async test "GraphQL repositories decode the data envelope" {
  let requests : Array[@http.Request] = []
  let payload : Json = {
    "data": {
      "user": {
        "recent": {
          "commitContributionsByRepository": [
            {
              "repository": {
                "nameWithOwner": "gaato/project",
                "primaryLanguage": null,
              },
              "contributions": { "totalCount": 7 },
            },
          ],
        },
      },
    },
  }
  let backend = @client.from_fn((request, _) => {
    requests.push(request)
    @http.Response::new(200, body=Bytes(@utf8.encode(payload.stringify())))
  })
  defer backend.close()
  let gh = @github.GitHub::new(
    backend,
    @runtime.AsyncClock::new(),
    token="fixture",
    user_agent~,
    limiter=@client.NoLimiter::new(),
  )
  let repos = fetch_repositories(gh, 0L)
  assert_eq(repos.length(), 1)
  assert_eq(repos[0].name, "gaato/project")
  assert_eq(repos[0].commits, 7)
  assert_eq(repos[0].language, "")
  assert_eq(repos[0].color, "#9a948a")
  assert_eq(requests[0].url, "https://api.github.com/graphql")
  assert_eq(requests[0].headers.get("Authorization"), Some("Bearer fixture"))
  assert_eq(requests[0].headers.get("User-Agent"), Some(user_agent))
}

///|
async test "transport errors keep their identity at the fallback boundary" {
  let failure = @http.TransportError(kind=Closed, phase=Pool, detail="fixture")
  let client = source_client(
    @client.from_fn((_, _) => raise failure),
    @runtime.AsyncClock::new(),
    headers=@http.Headers::empty(),
  )
  defer client.close()
  try fetch_feed(client, "https://example.test/feed") catch {
    @http.TransportError(kind~, phase~, detail~) => {
      assert_eq(kind, @http.Kind::Closed)
      assert_eq(phase, @http.Phase::Pool)
      assert_eq(detail, "fixture")
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected transport failure")
  }
}

///|
async test "GitHub pagination continues past a page of own repositories" {
  let requests : Array[@http.Request] = []
  let backend = @client.from_fn((request, _) => {
    requests.push(request)
    let first = requests.length() == 1
    let owner = if first { login } else { "upstream" }
    let data : Json = {
      "data": {
        "user": {
          "pullRequests": {
            "nodes": [
              {
                "createdAt": "1970-01-01T00:00:00Z",
                "state": "OPEN",
                "number": 1,
                "title": "fixture",
                "url": "https://github.com/\{owner}/project/pull/1",
                "author": { "login": login },
                "repository": {
                  "nameWithOwner": "\{owner}/project",
                  "owner": { "login": owner },
                },
              },
            ],
            "pageInfo": {
              "hasNextPage": first,
              "endCursor": if first {
                Json::string("next")
              } else {
                Json::null()
              },
            },
          },
        },
      },
    }
    @http.Response::new(200, body=Bytes(@utf8.encode(data.stringify())))
  })
  defer backend.close()
  let gh = @github.GitHub::new(
    backend,
    @runtime.AsyncClock::new(),
    limiter=@client.NoLimiter::new(),
  )
  let prs = fetch_upstream(gh, 0L)
  assert_eq(prs.length(), 1)
  assert_eq(prs[0].reference, "upstream/project#1")
  assert_eq(requests.length(), 2)
  for i, request in requests {
    guard request.body is Bytes(bytes) else { fail("expected buffered query") }
    let payload = @json.parse(@utf8.decode(bytes))
    guard payload is { "query": String(query), "variables": variables, .. } else {
      fail("expected query and variables")
    }
    assert_eq(query, @activity.pull_requests_query)
    assert_eq(variables, {
      "login": login,
      "cursor": if i == 0 {
        Json::null()
      } else {
        Json::string("next")
      },
    })
  }
}

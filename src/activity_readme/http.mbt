///|
/// Keep source requests bounded and retry transient failures as before. Separate
/// backends keep OBS credentials and connection ownership local to its client.
fn source_client(
  backend : &@http.Backend,
  clock : &@rt.Clock,
  headers~ : @http.Headers,
  base_url? : String,
) -> @client.Client {
  @client.Client::new(
    @client.FollowRedirects::new(
      @cookies.Cookies::new(backend, @cookie.CookieJar::new(clock)),
    ),
    clock,
    base_url?,
    headers~,
    timeout_ms=30_000,
    total_ms=150_000,
    timer=@runtime.ClockTimer::new(clock~),
    max_body_bytes=64 * 1024 * 1024,
    retry=@client.RetryPolicy::from_rule({
      max_retries: 3,
      statuses: [
        {
          statuses: [408, 429, 500, 502, 503, 504].map(code => {
            @client.StatusMatch::Code(code)
          }),
          methods: Idempotent,
        },
      ],
      sent_failures: Idempotent,
      unsent_failures: true,
      override_header: None,
      retry_after: {
        source: Header,
        cap: StopAbove(60_000),
        zero_means_backoff: false,
      },
      backoff: { base_ms: 1000, max_ms: 30_000, jitter: Full, },
    }),
  )
}

///|
fn obs_headers(password : String) -> @http.Headers {
  let credentials = @base64.encode(@utf8.encode("\{login}:\{password}"))
  @http.Headers::of([
    ("User-Agent", user_agent),
    ("Accept", "application/xml"),
    ("Authorization", "Basic \{credentials}"),
  ])
}

///|
/// Source failures must reach fetch_or_keep so a rejected HTTP response cannot
/// replace saved entries. Text keeps the previous lossy UTF-8 decoding.
async fn fetch_text(client : @client.Client, url : String) -> String {
  let reply = @client.get(url).send(client)
  match reply.body {
    Ok(text) => text
    Err(error) => fail("HTTP \{error.head().status} for GET \{url}")
  }
}

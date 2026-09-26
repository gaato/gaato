///|
/// Base URL of the public openSUSE Build Service web UI, used for request links.
let obs_web_url : String = "https://build.opensuse.org"

///|
/// Path and query for the OBS request search API, restricted to submit requests
/// by `login` that are accepted or still pending. The API has no creation-date
/// predicate we can rely on, so the window is applied by `parse_submit_requests`.
pub fn obs_submit_request_search(login : String) -> String {
  let xpath = "@creator='\{login}' and action/@type='submit' and (state/@name='accepted' or state/@name='new' or state/@name='review')"
  let sb = StringBuilder()
  for c in xpath {
    match c {
      ' ' => sb.write_string("%20")
      '\'' => sb.write_string("%27")
      '@' => sb.write_string("%40")
      '=' => sb.write_string("%3D")
      '/' => sb.write_string("%2F")
      _ => sb.write_char(c)
    }
  }
  "/search/request?match=\{sb.to_string()}"
}

///|
/// The parts of one `<request>` that the README needs, filled in while its
/// events are read.
priv struct RequestFields {
  id : String
  mut state : String?
  mut created : String?
  mut project : String?
  mut pkg : String?
  mut in_submit : Bool
}

///|
/// Parses an OBS `<collection>` of requests into upstream entries, keeping
/// accepted or pending submit requests created within `from` whose target is
/// outside `login`'s home projects.
pub fn parse_submit_requests(
  xml : String,
  from~ : String,
  login~ : String,
) -> Array[SubmitRequest] raise {
  let reader = @xml.Reader::from_string(xml)
  // Names of the open elements, outermost first, so fields are matched by
  // path: reviews and history entries nest elements of their own.
  let path : Array[String] = []
  let requests : Array[RequestFields] = []
  let mut current : RequestFields? = None
  let mut root_seen = false
  while true {
    let event = reader.read_event()
    let (element, empty) = match event.kind {
      Start(element) => (element, false)
      Empty(element) => (element, true)
      End(_) => {
        let name = path.pop()
        if name is Some("request") &&
          path.length() == 1 &&
          current is Some(request) {
          requests.push(request)
          current = None
        } else if name is Some("action") && current is Some(request) {
          request.in_submit = false
        }
        continue
      }
      Eof => break
      _ => continue
    }
    if !root_seen {
      guard element.name == "collection" else {
        fail("unexpected OBS request response: \{xml}")
      }
      root_seen = true
    }
    match (path.length(), element.name, current) {
      (1, "request", _) => {
        guard element.get("id") is Some(id) else {
          fail("OBS request without an id")
        }
        current = Some({
          id,
          state: None,
          created: None,
          project: None,
          pkg: None,
          in_submit: false,
        })
      }
      (2, "action", Some(request)) =>
        request.in_submit = element.get("type") is Some("submit") &&
          request.project is None
      (3, "target", Some(request)) if request.in_submit => {
        request.project = element.get("project")
        request.pkg = element.get("package")
      }
      (2, "state", Some(request)) => {
        request.state = element.get("name")
        request.created = element.get("created")
      }
      _ => ()
    }
    if !empty {
      path.push(element.name)
    }
  }
  guard root_seen else { fail("unexpected OBS request response: \{xml}") }
  let home = "home:\{login}"
  let result : Array[SubmitRequest] = []
  for request in requests {
    guard parse_number(request.id) is Some(number) &&
      request.state is Some(state) &&
      request.created is Some(created) else {
      fail("unexpected OBS request \{request.id}")
    }
    // Not a submit request, e.g. a delete-only request.
    guard request.project is Some(project) && request.pkg is Some(pkg) else {
      continue
    }
    // OBS timestamps are UTC without a zone suffix.
    let created = created + "Z"
    if created < from ||
      project == home ||
      project.has_prefix("\{home}:") ||
      (state != "accepted" && state != "new" && state != "review") {
      continue
    }
    guard parse_iso8601_utc(created) is Some(unix) else {
      fail("unexpected OBS request timestamp: \{created}")
    }
    result.push({
      project,
      pkg,
      number,
      url: "\{obs_web_url}/request/show/\{number}",
      accepted: state == "accepted",
      date: jst_date(unix),
    })
  }
  result
}

return {

  intro = table.concat({
    "santoku-socket is the framework's native HTTP(S) client: a thin wrapper over ",
    "LuaSocket and LuaSec (ssl.https plus ltn12) with a small, uniform ",
    "request/response shape. The surface is small: fetch for a ",
    "blocking request, request for a cancelable handle whose await runs it, and a ",
    "millisecond sleep built on santoku-system. Those same names are what ",
    "santoku-http expects of a backend, so plugging this module into that front end ",
    "adds retry, hooks, and query building with no glue, and identical client code ",
    "runs over this module's browser and OpenResty siblings. It ",
    "needs native TLS sockets, so it runs in servers, CLIs, and scripts rather than ",
    "in this page: the examples are shown for reading, except the response model, ",
    "which is plain Lua and runs live. The examples run in order: ",
    "fetch, the response contract, failure paths, request and cancel, sleep, ",
    "composition with santoku-http, and the raw TLS stream driver underneath it all.",
  }),

  examples = {

    {
      title = "fetch: a simple GET",
      desc = "A blocking GET returns ok (true for 2xx) and a response table; body is a function returning the full text. The whole ssl.https call sits inside a pcall, so fetch itself never raises on network trouble.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp = socket.fetch("https://example.com/")
print(ok, resp.status)
print(resp.headers["content-type"])
return #resp.body()
]],
    },

    {
      title = "The response shape",
      desc = "Every completed response carries status, ok, headers, and body. Header keys are lowercased on the way in, and resp.ok always equals the first return.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp = socket.fetch("https://example.com/")
print(resp.status)
print(resp.ok == ok)
for k, v in pairs(resp.headers) do
  print(k, v)
end
return resp.body()
]],
    },

    {
      title = "How a response is built, modeled live",
      desc = "The same steps the module takes after ssl.https returns: concatenate the sink chunks into one body, lowercase every header key, compute ok from the 2xx range, and capture the body in a closure so it reads repeatedly. The construction is plain Lua, so this one runs here.",
      code = [[
local arr = require("santoku.array")
local str = require("santoku.string")
local chunks = { "{\"pong\"", ":true}" }
local raw_headers = {
  ["Content-Type"] = "application/json",
  ["X-Request-Id"] = "abc123",
}
local body = arr.concat(chunks)
local headers = {}
for k, v in pairs(raw_headers) do
  headers[str.lower(k)] = v
end
local status = 200
local is2xx = status >= 200 and status < 300
local resp = {
  status = status,
  ok = is2xx,
  headers = headers,
  body = function () return body end,
}
print(resp.status, resp.ok)
print(resp.headers["content-type"], resp.headers["x-request-id"])
print(resp.body())
print(resp.body() == resp.body())
return resp.body()
]],
    },

    {
      title = "POST with a body",
      desc = "Pass method, headers, and body in opts. When a body is present and no content-length header is given, one is derived from the body's byte length.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp = socket.fetch("https://api.example.com/echo", {
  method = "POST",
  headers = { ["content-type"] = "application/json" },
  body = "{\"hello\":\"world\"}",
})
print(ok, resp.status)
return resp.body()
]],
    },

    {
      title = "Methods and headers",
      desc = "Any method string passes straight through to the transport, and an explicit content-length is respected rather than overwritten. Auth is just another header.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local token = "..."
local ok, resp = socket.fetch("https://api.example.com/items/42", {
  method = "PUT",
  headers = {
    ["authorization"] = "Bearer " .. token,
    ["content-type"] = "text/plain",
    ["content-length"] = "5",
  },
  body = "hello",
})
print(ok, resp.status)
return resp.status
]],
    },

    {
      title = "Non-2xx responses",
      desc = "A request that completes with a non-2xx status returns false but still carries the real status, headers, and body, so error pages remain readable.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp = socket.fetch("https://example.com/missing")
print(ok, resp.ok, resp.status)
return resp.body()
]],
    },

    {
      title = "Transport failures",
      desc = "Failures before any status arrives take one of two paths: a raised transport error is caught by the pcall and lands in resp.error, and a nil return from the transport puts its message there instead. Both yield status 0, empty headers, and a body() that returns nil rather than raising.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp = socket.fetch("https://localhost:1/down")
print(ok, resp.status)
print(resp.error)
return resp.body() == nil
]],
    },

    {
      title = "Saving a response to disk",
      desc = "body() hands back the whole text, so persisting a download is one santoku.fs call.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local fs = require("santoku.fs")
local ok, resp = socket.fetch("https://example.com/data.json")
if ok then
  fs.writefile("data.json", resp.body())
end
print(ok, resp.status)
return resp.headers["content-length"]
]],
    },

    {
      title = "request: a cancelable handle",
      desc = "request defers the work: nothing happens until await, which runs the fetch and returns the same ok, resp pair as fetch.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local req = socket.request("https://example.com/")
local ok, resp = req.await()
print(ok, resp.status)
return resp.body()
]],
    },

    {
      title = "cancel before and after the fetch",
      desc = "Canceling before await short-circuits without issuing a request. await also re-checks the flag after the fetch returns, so a cancel raced in from a hook discards the response and yields the canceled sentinel. That sentinel is { status = 0, headers = {}, ok = false, canceled = true } with no body function, so check canceled before reading.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local job = socket.request("https://example.com/slow")
job.cancel()
local ok, resp = job.await()
print(ok, resp.status, resp.canceled)
return resp.canceled
]],
    },

    {
      title = "sleep: milliseconds",
      desc = "sleep takes milliseconds and delegates to santoku.system's second-based sleep, whose C side spends the whole seconds in sleep() and the remainder in usleep(), so fractional pauses like 250ms and 1.5s both work.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
socket.sleep(250)
socket.sleep(1500)
return true
]],
    },

    {
      title = "Polling with backoff",
      desc = "fetch plus sleep is enough for a hand-rolled retry loop: back off a little more on each failed attempt.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local ok, resp
for attempt = 1, 3 do
  ok, resp = socket.fetch("https://api.example.com/status")
  if ok then
    break
  end
  print("attempt " .. attempt .. " failed, retrying")
  socket.sleep(250 * attempt)
end
print(ok, resp.status)
return resp.body()
]],
    },

    {
      title = "One deadline, not a timeout per call",
      desc = "fetch takes no timeout, so bound the sequence instead of the call: fix one deadline up front and check what is left of it before each attempt and before each sleep. That caps how many more attempts you make and how long you wait between them; it cannot interrupt a request already in flight, which is the one thing this module leaves to the transport.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local deadline = os.time() + 60
local function poll (url)
  local wait = 250
  while os.time() < deadline do
    local ok, resp = socket.fetch(url)
    if ok then
      return resp.body()
    end
    if os.time() + wait / 1000 >= deadline then
      break
    end
    socket.sleep(wait)
    wait = wait * 2
  end
  return nil, "no response before the deadline"
end
return poll("https://api.example.com/status")
]],
    },

    {
      title = "A REST wrapper in one function",
      desc = "One function turns method, path, and params into a bearer-authenticated form-encoded request and returns a decoded JSON table or an error string. Because body() returns nil rather than raising on transport failure, the error path can use resp.error or the body without extra guards.",
      runnable = false,
      code = [[
local socket = require("santoku.socket")
local str = require("santoku.string")
local cjson = require("cjson")
local key = "..."
local function stripe (method, path, params)
  local opts = {
    method = method,
    headers = {
      ["authorization"] = "Bearer " .. key,
      ["content-type"] = "application/x-www-form-urlencoded",
    },
  }
  if params then
    opts.body = str.to_formdata(params)
  end
  local ok, resp = socket.fetch("https://api.stripe.com" .. path, opts)
  local body = resp.body()
  if not ok then
    return nil, "request failed: " .. (resp.error or body or "unknown")
  end
  return cjson.decode(body)
end
local session, err = stripe("POST", "/v1/checkout/sessions", {
  mode = "subscription",
})
return session or err
]],
    },

    {
      title = "As the backend of santoku-http",
      desc = "santoku-http expects a backend with fetch, request, and sleep, and prefers request when present, so cancellation flows through. One line adds query params via to_query, request and response hooks, and retry with jittered backoff: by default 3 retries starting at 1000ms with a 3x multiplier, triggered on status 0, 429, 502, 503, and 504.",
      runnable = false,
      code = [[
local http = require("santoku.http")(require("santoku.socket"))
local ok, resp = http.get("https://api.example.com/search", {
  params = { q = "lua" },
})
print(ok, resp.status)
local req = http.fetch("https://api.example.com/slow", { cancelable = true })
req.cancel()
local ok2, r2 = req.await()
print(ok2, r2.canceled)
return r2.canceled
]],
    },

    {
      title = "One contract, three transports",
      desc = "Because the response shape is shared, the same application code runs over three interchangeable backends: this module in native scripts, santoku.web.socket in the browser, and santoku.resty.socket under OpenResty.",
      runnable = false,
      code = [[
local native = require("santoku.http")(require("santoku.socket"))
local browser = require("santoku.http")(require("santoku.web.socket"))
local server = require("santoku.http")(require("santoku.resty.socket"))
local function ping (http)
  local ok, resp = http.get("https://example.com/ping")
  return ok and resp.body()
end
return ping
]],
    },

    {
      title = "santoku.socket.stream: the raw TLS stream driver",
      desc = table.concat({
        "Protocols that are not request and response need bytes rather than ",
        "messages. santoku.socket.stream is that layer: connect(opts, done) dials ",
        "host and port, wraps the socket in TLS unless tls = false, and hands ",
        "done(ok, conn) a connection with write, close and step. Inbound data is ",
        "pushed, not pulled: every chunk the socket produces goes to the data ",
        "callback in whatever fragmentation the network gave it, and reassembly is ",
        "the protocol's job. Because LuaSocket blocks and has no event loop, this ",
        "driver also exposes step(ms), one bounded read delivered through the same ",
        "data callback; it returns true, \"timeout\" when the window passed with ",
        "nothing to read, and false plus a reason once the connection is gone. ",
        "connect_timeout_ms defaults to 30000, and sslname overrides the SNI name ",
        "when it differs from host.",
      }),
      runnable = false,
      code = [[
local stream = require("santoku.socket.stream")
stream.connect({
  host = "imap.example.com",
  port = 993,
  data = function (chunk) print("read", #chunk, "bytes") end,
  closed = function (e) print("closed:", e) end,
}, function (ok, conn)
  if not ok then
    return print("connect failed:", conn)
  end
  print("verified:", conn.tls.verified)
  conn.write("A1 CAPABILITY\r\n")
  for _ = 1, 10 do
    conn.step(200)
  end
  conn.close()
end)
return true
]],
    },

    {
      title = "Verification is on, and the hostname is checked here",
      desc = table.concat({
        "luasec verifies the certificate chain and nothing else, so this driver does ",
        "the rest. It finds a system CA bundle by probing known locations (Termux ",
        "first, then the common Linux paths), verifies the chain against it, and ",
        "matches the target name against the certificate's subjectAltName dNSName ",
        "entries, falling back to commonName and honouring a single leading ",
        "wildcard label. A mismatch closes the connection and reports which names ",
        "the certificate actually carries. No bundle found is a hard error rather ",
        "than a silent downgrade: pass cafile or capath to point at your own, or ",
        "verify = false to opt out deliberately. conn.tls reports the outcome, ",
        "carrying verified, the bundle used, and the names matched against. ",
        "stream.ca_paths is the probe list and can be extended before connecting.",
      }),
      runnable = false,
      code = [[
local stream = require("santoku.socket.stream")
stream.connect({
  host = "imap.example.com",
  port = 993,
  cafile = "/etc/ssl/certs/ca-certificates.crt",
  data = function (chunk) print(#chunk) end,
}, function (ok, conn)
  print(ok, ok and conn.tls.verified, ok and conn.tls.names[1])
end)
stream.connect({
  host = "192.0.2.10",
  port = 993,
  verify = false,
  data = function () end,
}, function (ok, conn)
  print("unverified:", ok, conn.tls.verified)
end)
return true
]],
    },

    {
      title = "One driver contract, every runtime",
      desc = table.concat({
        "The driver is injected, so a protocol written against this contract runs ",
        "unchanged wherever a driver exists: santoku.socket.stream over LuaSocket ",
        "and LuaSec, santoku.web.stream over node tls under wasm, and ",
        "santoku.resty.stream over ngx cosockets. santoku-imap is the consumer to ",
        "read: it takes a driver and detects whether step is present, pumping ",
        "internally on a pull driver so that completion is synchronous there and ",
        "event-driven on a push driver, with the same callback API either way.",
      }),
      runnable = false,
      code = [[
local imap = require("santoku.imap")(require("santoku.socket.stream"))
imap.connect({ host = "imap.example.com", port = 993 }, function (ok, client)
  if not ok then
    return print("connect failed:", client)
  end
  client.login("me@example.com", "app-password", function (okl)
    print("login:", okl)
    client.logout(function () end)
  end)
end)
return true
]],
    },

  },

}

return {

  intro = table.concat({
    "santoku-resty is the OpenResty glue layer: thin wrappers over the upstream ",
    "lua-resty rocks (HTTP client, JWT, WebSocket) that add santoku error handling ",
    "and a smaller, uniform surface. Every module here calls the ngx API and the ",
    "cosocket-based upstream rocks, so it only runs inside an nginx worker: all ",
    "examples on this page are display-only. ",
    "nginx confs templated by santoku-mustache route requests ",
    "into Lua handlers that use these modules for outbound HTTP and token checks.",
  }),

  examples = {

    {
      title = "santoku.resty.http: one-call requests",
      desc = table.concat({
        "request wraps resty.http's request_uri in a single call: pass url, ",
        "method, body, headers, and ssl_verify in one options table and get back ",
        "a plain { status, headers, body } table. On transport failure it raises ",
        "through santoku.error instead of returning nil plus a message.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.resty.http")
local res = http.request({
  url = "https://api.example.com/things",
  method = "POST",
  body = '{"name":"widget"}',
  headers = { ["Content-Type"] = "application/json" },
  ssl_verify = true,
})
print(res.status)
print(res.headers["Content-Type"])
print(res.body)
]],
    },

    {
      title = "santoku.resty.http: configure hook and structured errors",
      desc = table.concat({
        "The configure option receives the underlying resty.http client before ",
        "the request fires, for timeouts and other client-level settings. Because ",
        "failures raise, err.pcall is the idiom for handling them without ",
        "crashing the handler.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.resty.http")
local err = require("santoku.error")
local ok, e = err.pcall(http.request, {
  url = "https://internal.example.com:8443/health",
  configure = function (client)
    client:set_timeout(5000)
  end,
})
if not ok then
  ngx.log(ngx.ERR, "health check failed: ", e)
  ngx.status = 502
  return
end
ngx.say("upstream healthy")
]],
    },

    {
      title = "santoku.resty.socket: fetch without raising",
      desc = table.concat({
        "The second HTTP client never raises: fetch returns ok, response where ",
        "ok reflects a 2xx status. The response normalizes header keys to ",
        "lowercase, exposes the body as a function, and repeats ok as a field. ",
        "A transport error yields { status = 0, ok = false, error = e } with a ",
        "body function that returns nil.",
      }),
      runnable = false,
      code = [[
local socket = require("santoku.resty.socket")
local ok, res = socket.fetch("https://api.example.com/items", {
  method = "GET",
  headers = { ["Accept"] = "application/json" },
})
print(ok, res.status)
print(res.headers["content-type"])
if ok then
  print(res.body())
else
  print("failed:", res.error or res.status)
end
]],
    },

    {
      title = "santoku.resty.socket: cancelable requests and sleep",
      desc = table.concat({
        "request defers the work into a { cancel, await } pair. cancel before ",
        "await short-circuits to { status = 0, ok = false, canceled = true }; ",
        "cancel while in flight closes the underlying client. sleep wraps ",
        "ngx.sleep, taking milliseconds, and yields the current request's ",
        "coroutine instead of blocking the worker.",
      }),
      runnable = false,
      code = [[
local socket = require("santoku.resty.socket")
local req = socket.request("https://api.example.com/big-report", {
  method = "GET",
})
req.cancel()
local ok, res = req.await()
print(ok, res.status, res.canceled)
socket.sleep(500)
local ok2, res2 = socket.fetch("https://api.example.com/big-report")
print(ok2, res2.status)
]],
    },

    {
      title = "A payments client",
      desc = table.concat({
        "socket's fetch/request shape is exactly the backend contract of the ",
        "santoku-http rock, so handing santoku.resty.socket to santoku.http ",
        "yields a server-side client with retries and ",
        "jittered backoff for free.",
      }),
      runnable = false,
      code = [[
local json = require("cjson")
local str = require("santoku.string")
local http = require("santoku.http")(require("santoku.resty.socket"))
local function stripe_request (method, path, params, key)
  local opts = {
    method = method,
    headers = {
      ["Authorization"] = "Bearer " .. key,
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
  }
  if params then
    opts.body = str.to_formdata(params)
  end
  local ok, res = http.fetch("https://api.stripe.com" .. path, opts)
  local body = res.body()
  if not ok then
    return nil, "stripe error " .. res.status .. ": " .. (body or "")
  end
  return json.decode(body)
end
local session = stripe_request("POST", "/v1/checkout/sessions", {
  mode = "subscription",
  ["line_items[0][quantity]"] = "1",
}, secret_key)
print(session and session.url)
]],
    },

    {
      title = "santoku.resty.jwt: parse and verify",
      desc = table.concat({
        "Tokens arrive base64-encoded and are decoded with santoku.string ",
        "before being handed to resty.jwt. parse loads without verification; ",
        "verify resolves an RSA JWK by the token's kid via your callback, ",
        "converts it to PEM, and checks the signature. The default claim spec ",
        "rejects expired tokens against your get_time function. Failures return ",
        "false plus a reason: no kid, no JWK for the kid, a non-RSA key, or a ",
        "failed signature.",
      }),
      runnable = false,
      code = [[
local jwt = require("santoku.resty.jwt")
local parsed = jwt.parse(token)
print(parsed.header.kid)
local ok, data = jwt.verify(token, function (kid)
  return jwks[kid]
end, ngx.time)
if ok then
  print("sub:", data.payload.sub)
else
  print("rejected:", data)
end
]],
    },

    {
      title = "santoku.resty.jwt: JWK to PEM via the C helper",
      desc = table.concat({
        "jwk_to_pem takes an RSA JWK, decodes its base64url modulus and ",
        "exponent to hex with santoku.string, and calls the ",
        "santoku.resty.jwt.capi C extension, whose single function rsa_pem ",
        "builds the key with OpenSSL BIGNUMs and writes it out as a PEM public ",
        "key string. verify uses this internally, but it is exposed for callers ",
        "that cache PEMs or feed other OpenSSL APIs.",
      }),
      runnable = false,
      code = [[
local jwt = require("santoku.resty.jwt")
local capi = require("santoku.resty.jwt.capi")
local str = require("santoku.string")
local pem = jwt.jwk_to_pem({
  kty = "RSA",
  n = jwk.n,
  e = jwk.e,
})
print(pem)
local same = capi.rsa_pem(
  str.to_hex(str.from_base64_url(jwk.n)),
  str.to_hex(str.from_base64_url(jwk.e)))
print(pem == same)
]],
    },

    {
      title = "A bearer-auth guard for handlers",
      desc = table.concat({
        "The verify signature composes into a small middleware: read the ",
        "Authorization header from ngx, verify against a JWKS table, extract ",
        "the subject with santoku.table, and only then run the handler body.",
      }),
      runnable = false,
      code = [[
local tbl = require("santoku.table")
local jwt = require("santoku.resty.jwt")
local keys = require("app.jwks")
local function with_sub (callback)
  local auth = ngx.req.get_headers()["authorization"]
  if not auth then
    ngx.status = 401
    return
  end
  local ok, data = jwt.verify(auth, function (kid)
    return kid and keys[kid] or nil
  end, ngx.time)
  if not ok and data == "expired" then
    ngx.status = 401
    ngx.say(data)
    return
  elseif not ok then
    ngx.status = 401
    return
  end
  local sub = tbl.get(data, { "payload", "sub" })
  if not sub then
    ngx.status = 401
    return
  end
  return callback(sub)
end
with_sub(function (sub)
  ngx.say("hello ", sub)
end)
]],
    },

    {
      title = "santoku.resty.websocket.client",
      desc = table.concat({
        "The module is a constructor: connect(url, nopts, copts) passes nopts ",
        "to resty.websocket.client's new and copts to connect, then returns a ",
        "three-method object. send transmits binary frames; receive loops ",
        "internally, answering pings with pongs, returning the first text or ",
        "binary frame's data, and returning nil after answering a close frame. ",
        "Any frame-level failure raises through santoku.error.",
      }),
      runnable = false,
      code = [[
local connect = require("santoku.resty.websocket.client")
local ws = connect("wss://feed.example.com/socket", {
  timeout = 5000,
})
ws.send('{"subscribe":"updates"}')
local msg = ws.receive()
while msg do
  print("frame:", msg)
  msg = ws.receive()
end
ws.close()
]],
    },

    {
      title = "santoku.resty.websocket.server",
      desc = table.concat({
        "The server side takes one options table for resty.websocket.server's ",
        "new and returns the same three-method shape. Its receive additionally ",
        "reassembles fragmented messages: binary, text, and continuation frames ",
        "accumulate until one is not flagged again, then concatenate into the ",
        "full message. close sends a close frame to the peer.",
      }),
      runnable = false,
      code = [[
local accept = require("santoku.resty.websocket.server")
local ws = accept({
  timeout = 60000,
  max_payload_len = 65535,
})
while true do
  local msg = ws.receive()
  if not msg then
    break
  end
  ws.send("echo: " .. msg)
end
ws.close()
]],
    },

    {
      title = "Where it sits: templated nginx confs and web handlers",
      desc = table.concat({
        "The nginx conf is typically a santoku-template file that renders ",
        "res/nginx.conf through santoku-mustache at build time, mapping each ",
        "API location to content_by_lua_file with a bundled tasks.web module. ",
        "Those handlers own the inbound side with the raw ngx API and lean on ",
        "this library for the outbound side, like the Stripe portal handler ",
        "below: nginx routes in, ",
        "santoku.resty carries the calls out.",
      }),
      runnable = false,
      code = [[
local auth = require("tasks.web.auth")
local stripe = require("tasks.stripe")
local psub, user = auth.signed_header("portal")
auth.require_token(psub)
if not user.stripe_customer_id or user.stripe_customer_id == "none" then
  return auth.fail(400, "no_subscription")
end
local portal_url, e = stripe.create_portal_session(
  user.stripe_customer_id, return_url)
if not portal_url then
  return auth.fail(500, "portal_failed", { detail = e })
end
ngx.header.content_type = "text/plain"
ngx.say(portal_url)
]],
    },

  },

}

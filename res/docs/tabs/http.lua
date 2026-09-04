return {

  intro = table.concat({
    "santoku-http is a transport-agnostic HTTP client front end. Calling the module ",
    "with a backend table yields a client with a five-function surface, fetch, get, ",
    "post, on, and off, that layers query-string building, retry with jittered ",
    "backoff, cancellation, and request/response hooks over a backend that does all ",
    "the network I/O. A backend supplies sleep(ms) plus either fetch(url, opts) ",
    "returning ok, resp or request(url, opts) returning a { cancel, await } handle. ",
    "The same client code runs over santoku.socket in native scripts, ",
    "santoku.web.socket in the browser, and santoku.resty.socket under OpenResty. ",
    "The tour ",
    "below walks the whole surface: the request verbs and the shared response ",
    "shape, the exact arithmetic of the retry loop, cancellation at every phase ",
    "including mid-backoff, both hook flavors and how they interact with retry, ",
    "and three fuller worked examples. The examples use tiny in-memory ",
    "backends, the same technique the test suite uses, so every printed count is ",
    "exact; apart from one query-string interlude that runs live, they are shown ",
    "for reading rather than running in the page.",
  }),

  examples = {

    {
      title = "Building a client over a backend",
      desc = "The module is a factory: pass a backend with fetch(url, opts) and sleep(ms), get back { fetch, get, post, on, off }.",
      runnable = false,
      code = [[
local http = require("santoku.http")
local client = http({
  fetch = function (url, opts)
    return true, { status = 200, body = "hello from " .. url }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/api")
print(ok, resp.status)
return resp.body
]],
    },

    {
      title = "GET with query params",
      desc = table.concat({
        "get sets opts.method and appends str.to_query(opts.params) to the url ",
        "before handing it to the backend. Values are percent-encoded; only ",
        "string, number, and boolean params are kept, anything else is silently ",
        "dropped. This is a get feature: post and fetch forward params untouched ",
        "and no transport reads it, so for other verbs encode the query into the ",
        "url yourself, as in posting to \"/sync?since=\" .. cursor. ",
        "The built string always starts with \"?\", so hand get a url without ",
        "one.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local seen
local client = http({
  fetch = function (url, opts)
    seen = url
    return true, { status = 200 }
  end,
  sleep = function (ms) end,
})
client.get("http://example/search", { params = { q = "hello world" } })
print("get:", seen)
client.post("http://example/search", { params = { q = "hello world" } })
print("post:", seen)
return seen
]],
    },

    {
      title = "Query strings by hand",
      desc = table.concat({
        "The encoding under get lives in santoku.string, so it runs right here: ",
        "to_query builds the \"?k=v\" string the client appends, to_formdata is ",
        "the same pairs minus the leading \"?\" (Stripe bodies below), and ",
        "from_query reverses both, decoding percent escapes and reviving numbers ",
        "and booleans.",
      }),
      code = [[
local str = require("santoku.string")
print(str.to_query({ q = "hello world" }))
print(str.to_formdata({ mode = "subscription" }))
local parsed = str.from_query("?page=2&debug=true&q=hello%20world")
print(parsed.page + 1, parsed.debug, parsed.q)
return str.to_query({ n = 42 })
]],
    },

    {
      title = "POST with headers and a body",
      desc = table.concat({
        "post writes method = \"POST\" into the opts table you pass and forwards ",
        "everything else untouched: headers and body reach the backend exactly as ",
        "given, so encoding is the caller's job (str.to_formdata and cjson.encode ",
        "in practice).",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local seen
local client = http({
  fetch = function (url, opts)
    seen = opts
    return true, { status = 201 }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.post("http://example/items", {
  headers = { ["Content-Type"] = "application/json" },
  body = "{\"name\":\"widget\"}",
})
print(seen.method, seen.headers["Content-Type"])
print(ok, resp.status)
return seen.body
]],
    },

    {
      title = "Any method through fetch",
      desc = table.concat({
        "fetch is the primitive under get and post: set opts.method yourself for ",
        "DELETE, PUT, or PATCH, passing method = \"DELETE\" and the rest unchanged.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local seen
local client = http({
  fetch = function (url, opts)
    seen = opts.method
    return true, { status = 204 }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.fetch("http://example/items/42", { method = "DELETE" })
print("method:", seen)
print(ok, resp.status)
return resp.status
]],
    },

    {
      title = "The response convention",
      desc = table.concat({
        "The client passes responses through untouched; the shape is a convention ",
        "kept by all three shipped transports: ok is true for 2xx, status is a ",
        "number, headers are lowercased, resp.ok mirrors the first return, and ",
        "body is a function so streaming transports can defer the read.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local client = http({
  fetch = function (url, opts)
    local body = "{\"n\":1}"
    return true, {
      status = 200,
      ok = true,
      headers = { ["content-type"] = "application/json" },
      body = function () return body end,
    }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/api")
print(ok, resp.ok, resp.status)
print(resp.headers["content-type"])
return resp.body()
]],
    },

    {
      title = "Transport failure, one shape everywhere",
      desc = table.concat({
        "When the network itself fails, before any status arrives, all three ",
        "transports return the same sentinel: ok false, status 0, empty headers, ",
        "error carrying the transport's reason (the LuaSec message natively, err ",
        "from lua-resty-http, the thrown value in the browser), and body() ",
        "returning nil. Status 0 counts as transient for the default retry ",
        "filter, so probes that must answer fast pair it with retry = false, and a ",
        "status of 0 is the natural place to map \"offline\".",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local client = http({
  fetch = function (url, opts)
    return false, {
      status = 0,
      ok = false,
      headers = {},
      error = "connection refused",
      body = function () return nil end,
    }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/api", { retry = false })
print(ok, resp.status, resp.error)
print(resp.body())
return resp.status
]],
    },

    {
      title = "Retry with jittered backoff",
      desc = table.concat({
        "Retry is on by default: transient failures are re-fetched with a growing ",
        "jittered delay between attempts. Here the third attempt succeeds, so the ",
        "backend saw 3 calls and slept twice.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls, backoffs = 0, 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    if calls < 3 then
      return false, { status = 503 }
    end
    return true, { status = 200, body = "recovered" }
  end,
  sleep = function (ms)
    backoffs = backoffs + 1
  end,
})
local ok, resp = client.get("http://example/flaky")
print("attempts:", calls, "backoffs:", backoffs)
print(ok, resp.status)
return resp.body
]],
    },

    {
      title = "What retries by default",
      desc = table.concat({
        "The default filter retries only when status is missing or 0 (transport ",
        "failure) or one of 429, 502, 503, 504. Everything else, including 500 and ",
        "404, is returned immediately: exactly one backend call here.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls = 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 500 }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/bug")
print("attempts:", calls)
print(ok, resp.status)
return resp.status
]],
    },

    {
      title = "Retry exhaustion, exactly counted",
      desc = table.concat({
        "The default policy is times = 3: the retry loop makes 4 filtered attempts ",
        "with backoff after the first 3, then one final unconditional attempt whose ",
        "result is returned as-is. A permanently failing endpoint therefore sees 5 ",
        "backend calls and 3 sleeps.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls, sleeps = 0, 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 503 }
  end,
  sleep = function (ms)
    sleeps = sleeps + 1
  end,
})
local ok, resp = client.get("http://example/down")
print("calls:", calls, "sleeps:", sleeps)
print(ok, resp.status)
return calls
]],
    },

    {
      title = "Custom retry policies",
      desc = table.concat({
        "opts.retry takes times, backoff (initial ms), multiplier, and ",
        "filter(ok, resp) deciding what counts as transient. With times = 1 the ",
        "loop retries once with backoff, then makes the final unconditional ",
        "attempt: 3 calls, 1 sleep.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls, sleeps = 0, 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 500 }
  end,
  sleep = function (ms)
    sleeps = sleeps + 1
  end,
})
local ok, resp = client.get("http://example/fivehundred", {
  retry = {
    times = 1,
    backoff = 50,
    multiplier = 2,
    filter = function (ok, resp)
      return resp and resp.status == 500
    end,
  },
})
print("calls:", calls, "sleeps:", sleeps)
print(ok, resp.status)
return calls
]],
    },

    {
      title = "Disabling retry",
      desc = table.concat({
        "opts.retry = false makes exactly one attempt and returns whatever comes ",
        "back. Connectivity probes work this way: a nonce fetch with ",
        "retry = false answers \"am I online\" fast instead of backing off for ",
        "seconds.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls = 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 503 }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/nonce", { retry = false })
print("attempts:", calls)
print(ok, resp.status)
return resp.status
]],
    },

    {
      title = "Watching the backoff schedule",
      desc = table.concat({
        "Each delay is backoff + backoff * rand.num(), so between 1x and 2x the ",
        "current backoff, which is then multiplied for the next round. With ",
        "backoff = 100 and multiplier = 2 the recorded delays land in [100, 200) ",
        "and [200, 400).",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local delays = {}
local client = http({
  fetch = function (url, opts)
    return false, { status = 503 }
  end,
  sleep = function (ms)
    delays[#delays + 1] = ms
  end,
})
client.get("http://example/down", {
  retry = { times = 2, backoff = 100, multiplier = 2 },
})
print("sleeps:", #delays)
print(delays[1] >= 100 and delays[1] < 200)
print(delays[2] >= 200 and delays[2] < 400)
return #delays
]],
    },

    {
      title = "Cancelable requests",
      desc = table.concat({
        "With opts.cancelable, fetch returns { cancel, await } instead of ",
        "resolving inline. A request canceled before await never touches the ",
        "backend at all and resolves to false plus the { status = 0, ",
        "canceled = true } sentinel.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls = 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return true, { status = 200 }
  end,
  sleep = function (ms) end,
})
local req = client.fetch("http://example/slow", { cancelable = true })
req.cancel()
local ok, resp = req.await()
print("backend calls:", calls)
print(ok, resp.status, resp.canceled)
return resp.canceled
]],
    },

    {
      title = "Canceling during backoff",
      desc = table.concat({
        "The retry loop re-checks the cancel flag after every sleep, so a ",
        "cancel that lands mid-backoff stops the request before the next ",
        "attempt. Here the backend's sleep stands in for a timeout task that ",
        "fires cancel: one failing call, one sleep, then the sentinel instead ",
        "of retries two through five.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls, sleeps = 0, 0
local req
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 503 }
  end,
  sleep = function (ms)
    sleeps = sleeps + 1
    req.cancel()
  end,
})
req = client.fetch("http://example/slow", { cancelable = true })
local ok, resp = req.await()
print("calls:", calls, "sleeps:", sleeps)
print(ok, resp.status, resp.canceled)
return resp.canceled
]],
    },

    {
      title = "Backends with a request handle",
      desc = table.concat({
        "A backend may expose request(url, opts) returning { cancel, await }; ",
        "when present it is preferred over fetch, and client-side cancel is ",
        "forwarded to the live handle mid-flight. This is how the browser ",
        "transport aborts through AbortController and the resty transport closes ",
        "its cosocket. Fetch-only backends get a no-op cancel plus the sentinel ",
        "checks between attempts.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local used = {}
local client = http({
  request = function (url, opts)
    used[#used + 1] = "request"
    return {
      cancel = function () end,
      await = function ()
        return true, { status = 200 }
      end,
    }
  end,
  fetch = function (url, opts)
    used[#used + 1] = "fetch"
    return true, { status = 200 }
  end,
  sleep = function (ms) end,
})
local ok, resp = client.get("http://example/api")
print("used:", used[1], "count:", #used)
print(ok, resp.status)
return used[1]
]],
    },

    {
      title = "Observing traffic with sync hooks",
      desc = table.concat({
        "on(event, handler) without the async flag registers an observer: it ",
        "sees the values but its return is ignored, so it cannot replace them. ",
        "Hooks fire per backend attempt, so a retried request logs once per try.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local log = {}
local client = http({
  fetch = function (url, opts)
    return true, { status = 200 }
  end,
  sleep = function (ms) end,
})
client.on("request", function (url, opts)
  log[#log + 1] = "-> " .. url
end)
client.on("response", function (ok, resp)
  log[#log + 1] = "<- " .. resp.status
end)
client.get("http://example/a")
client.get("http://example/b")
print(table.concat(log, "\n"))
return #log
]],
    },

    {
      title = "Rewriting traffic with async hooks",
      desc = table.concat({
        "Passing true as the third argument to on makes the handler a ",
        "santoku.async stage: it receives a continuation k first and whatever it ",
        "passes to k replaces the url and opts (request) or ok and resp ",
        "(response) for everything downstream.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local seen
local client = http({
  fetch = function (url, opts)
    seen = url
    return true, { status = 200, body = "raw" }
  end,
  sleep = function (ms) end,
})
client.on("request", function (k, url, opts)
  return k(url .. "?traced=1", opts)
end, true)
client.on("response", function (k, ok, resp)
  resp.body = resp.body .. " (rewritten)"
  return k(ok, resp)
end, true)
local ok, resp = client.get("http://example/api")
print("backend saw:", seen)
print(ok, resp.body)
return resp.body
]],
    },

    {
      title = "Hooks meet the retry filter",
      desc = table.concat({
        "Response hooks run inside each attempt, before the retry filter sees ",
        "the result, so an async hook can rewrite a transient failure into a ",
        "success and the loop never retries at all. A hook serving a cached ",
        "fallback for 503 turns a would-be 5-call exhaustion into a single ",
        "attempt.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local calls = 0
local client = http({
  fetch = function (url, opts)
    calls = calls + 1
    return false, { status = 503 }
  end,
  sleep = function (ms) end,
})
client.on("response", function (k, ok, resp)
  if resp and resp.status == 503 then
    return k(true, { status = 200, ok = true, body = "served from cache" })
  end
  return k(ok, resp)
end, true)
local ok, resp = client.get("http://example/flaky")
print("attempts:", calls)
print(ok, resp.status, resp.body)
return resp.body
]],
    },

    {
      title = "Removing hooks",
      desc = "off(event, handler) unregisters by identity, so keep a reference to the function you passed to on.",
      runnable = false,
      code = [[
local http = require("santoku.http")
local count = 0
local client = http({
  fetch = function (url, opts)
    return true, { status = 200 }
  end,
  sleep = function (ms) end,
})
local tap = function (url, opts)
  count = count + 1
end
client.on("request", tap)
client.get("http://example/one")
client.off("request", tap)
client.get("http://example/two")
print("hook fired:", count)
return count
]],
    },

    {
      title = "One client, three transports",
      desc = table.concat({
        "Everything above is transport-independent. santoku.web.socket wraps ",
        "browser fetch with AbortController; santoku.socket wraps LuaSec's ",
        "ssl.https with ltn12 for scripts and CLIs; santoku.resty.socket wraps ",
        "lua-resty-http cosockets with ngx.sleep. A client-side platform module is ",
        "usually just the single web line.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")
local in_browser = http(require("santoku.web.socket"))
local in_scripts = http(require("santoku.socket"))
local under_nginx = http(require("santoku.resty.socket"))
return in_browser, in_scripts, under_nginx
]],
    },

    {
      title = "Version pinning through hooks",
      desc = table.concat({
        "santoku.web.version.install_hooks is a real hook consumer: an async ",
        "request hook stamps x-client-version on same-origin requests, and a ",
        "response hook compares the server's x-app-version header, firing ",
        "on_mismatch once when the deploy has moved ahead. Server-side, ",
        "version.check under OpenResty answers a stale client with 409.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")(require("santoku.web.socket"))
local version = require("santoku.web.version")
version.install_hooks(http, "42", function ()
  print("server is ahead, reload for the new bundle")
end)
local ok, resp = http.get("/api/items")
print(ok, resp.status)
return resp.body()
]],
    },

    {
      title = "Stripe from OpenResty",
      desc = table.concat({
        "A billing integration in miniature: form-encoded bodies via ",
        "str.to_formdata, bearer auth in headers, and body() read once up front ",
        "so both the error path and the success path can use it.",
      }),
      runnable = false,
      code = [[
local json = require("cjson")
local str = require("santoku.string")
local http = require("santoku.http")(require("santoku.resty.socket"))
local secret_key = "sk_test_..."
local ok, resp = http.fetch("https://api.stripe.com/v1/checkout/sessions", {
  method = "POST",
  headers = {
    ["Authorization"] = "Bearer " .. secret_key,
    ["Content-Type"] = "application/x-www-form-urlencoded",
  },
  body = str.to_formdata({
    mode = "subscription",
    success_url = "https://example.com/ok",
    ["line_items[0][quantity]"] = "1",
  }),
})
local body = resp.body()
if not ok then
  return nil, "request failed: " .. (resp.error or body or "unknown")
end
if resp.status < 200 or resp.status >= 300 then
  return nil, "stripe error " .. resp.status .. ": " .. (body or "")
end
return json.decode(body).url
]],
    },

    {
      title = "A cancelable sync loop",
      desc = table.concat({
        "A sync orchestrator in miniature: the in-flight post is ",
        "held in a module-local so lock or teardown can abort it mid-flight; the ",
        "canceled sentinel, offline (status 0), and protocol statuses each route ",
        "differently, and the connectivity probe runs with retry = false while ",
        "the sync post keeps the default retry.",
      }),
      runnable = false,
      code = [[
local http = require("santoku.http")(require("santoku.web.socket"))
local active
local function sync (cursor, body, headers)
  active = http.post("/sync?since=" .. cursor, {
    cancelable = true,
    headers = headers,
    body = body,
  })
  local _, response = active.await()
  active = nil
  if not response then return "offline" end
  if response.canceled then return nil end
  local status = tonumber(response.status) or 0
  if status == 0 then return "offline" end
  if status == 401 then return "auth-required" end
  if status == 409 then return "resync" end
  if not response.ok then return false end
  return response.body()
end
local function stop ()
  if active then active.cancel() end
end
return sync, stop
]],
    },

  },

}

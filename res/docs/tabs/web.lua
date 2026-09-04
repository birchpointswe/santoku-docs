return {

  intro = table.concat({
    "santoku-web is the browser runtime of the framework: a Lua to JavaScript ",
    "marshaling layer (val), unwrapped js proxies, coroutine-based async over ",
    "promises, batched DOM access over a binary command buffer, and a ring of ",
    "browser integrations (fetch, websockets, history, worker RPC, OPFS SQLite, ",
    "PWA scaffolding), all compiled to WebAssembly with Emscripten. This page ",
    "itself runs on it: the tabs, the editors, and the Run buttons are Lua ",
    "driving the DOM through these modules. One philosophy holds throughout: ",
    "application code never writes JavaScript. The EM_JS shims live inside the ",
    "library's C core, and app Lua reaches the platform only through val, js, ",
    "and dom. Display-only examples show APIs that settle asynchronously, need ",
    "a worker or a network, or target elements this page does not have; the ",
    "rest run live.",
  }),

  examples = {

    {
      title = "santoku.web.val",
      desc = "Marshal Lua values to JavaScript and back: typeof, live proxies, deep copies.",
      code = [[
local val = require("santoku.web.val")
local v = val("hello")
print("typeof:", v:typeof():lua())
print("value:", v:lua())
print("number:", val(100.6):lua())
local source = { a = 1 }
local proxy = val(source)
proxy:set("b", 2)
print("b through proxy:", source.b)
local copy = val({ { a = 1 }, { b = 2 } }, true):lua()
print("deep copy:", copy[1].a, copy[2].b)
return val(true):lua()
]],
    },

    {
      title = "The conversion matrix",
      desc = "Primitives copy by value; tables proxy by default and deep-copy with recurse = true; val.lua converts from the unwrapped side.",
      code = [[
local val = require("santoku.web.val")
local js = require("santoku.web.js")
print("string:", val("hi"):typeof():lua())
print("number:", val(42):lua())
print("boolean:", val(true):lua())
local source = { a = 1, b = "2" }
local proxy = val(source)
proxy:set("c", 3)
print("same table back:", proxy:lua() == source)
print("mutation visible:", source.c)
local o = js.Object:new()
o.a = 1
o.nested = js.Object:new()
o.nested.b = 2
local t = val.lua(o, true)
print("val.lua deep:", t.a, t.nested.b)
print("val.lua primitive:", val.lua(1))
return js.JSON:stringify(t)
]],
    },

    {
      title = "santoku.web.js",
      desc = "Unwrapped globals: js.Name forwards index, newindex, and calls straight to JavaScript.",
      code = [[
local js = require("santoku.web.js")
print("max:", js.Math:max(1, 3, 2))
print("json:", js.JSON:stringify({ a = { b = 1 } }))
local m = js.Map:new()
m:set("k", 42)
print("map get:", m:get("k"))
print("instanceof Map:", m:instanceof(js.Map))
return js.JSON:stringify({ 1, 2, 3 })
]],
    },

    {
      title = "val get, set, call, new",
      desc = "The explicit handle API, including a Lua function stored on a JS object and called from JavaScript.",
      code = [[
local val = require("santoku.web.val")
local obj = val.global("Object"):call(nil)
obj:set("a", 1)
print("a:", obj:get("a"):lua())
obj:set("square", function (_, n)
  return n * n
end)
print("square(20):", obj:get("square"):call(obj, 20):lua())
local m = val.global("Map"):new()
m:get("set"):call(m, "k", 2)
print("map get:", m:get("get"):call(m, "k"):lua())
return obj:get("a"):typeof():lua()
]],
    },

    {
      title = "Callbacks and the this-first convention",
      desc = "A Lua function called from JavaScript receives this as its first argument; called directly from Lua it gets its arguments straight.",
      code = [[
local val = require("santoku.web.val")
local js = require("santoku.web.js")
local fn = function (a) return a + 4 end
print("direct call:", val(fn):lua()(2))
local obj = js.Object:new()
obj.square = function (_, n)
  return n * n
end
print("called from JS:", obj:square(20))
local ki = 0
js.Object:keys({ 1, 2, 3 }):forEach(function (_, k)
  print("js key:", k)
  ki = ki + 1
end)
return ki
]],
    },

    {
      title = "Arrays across the boundary",
      desc = "Lua is 1-indexed and JS is 0-indexed; array proxies convert at the boundary, so JS index 0 is Lua element 1.",
      code = [[
local val = require("santoku.web.val")
local js = require("santoku.web.js")
local a = val({ 1, 2, 3, 4 })
print("js index 0:", a:get(0):lua())
print("js index 3:", a:get(3):lua())
local target = {}
local t = val(target)
t:set(0, 10)
print("lua index 1:", target[1])
print("stringified:", js.JSON:stringify({ 1, 2, 3, 4 }))
return js.JSON:stringify({ 1, 2, 3, 4 })
]],
    },

    {
      title = "val.bytes and Uint8Array",
      desc = "Binary round trips: Lua string to Uint8Array with val.bytes, back with str.",
      code = [[
local val = require("santoku.web.val")
local b = val.bytes("ABC")
print("instanceof Uint8Array:", b:instanceof(val.global("Uint8Array")))
print("back to string:", b:str())
print("empty:", "[" .. val.global("Uint8Array"):new():lua():str() .. "]")
local u = val.global("Uint8Array"):new({ 104, 105 })
return u:lua():str()
]],
    },

    {
      title = "Operators, equality, tostring",
      desc = "Proxies carry metamethods: equality compares the underlying JS handles, arithmetic applies the JS operator, tostring forwards, and BigInt narrows to a Lua integer.",
      code = [[
local val = require("santoku.web.val")
local js = require("santoku.web.js")
local a = val.global("console"):lua()
local b = val.global("console"):lua()
print("same object:", a == b)
print("sum:", val(1) + val(2))
local e = js.Error:new("boom")
print("tostring:", tostring(e):match("[^\n]*"))
print("bigint:", js.BigInt(nil, 1))
return tostring(e):match("[^\n]*")
]],
    },

    {
      title = "val.class",
      desc = "Build a JS class from Lua: the config function receives the prototype, a second argument extends a parent, and instances answer instanceof up the chain.",
      code = [[
local val = require("santoku.web.val")
local Parent = val.class(function (proto)
  proto.greet = function () return "parent" end
end)
local Child = val.class(function (proto)
  proto.kind = function () return "child" end
end, Parent)
local c = Child:new()
print("instanceof Child:", c:instanceof(Child))
print("instanceof Parent:", c:instanceof(Parent))
print("greet:", c:get("greet"):call(c):lua())
print("kind:", c:get("kind"):call(c):lua())
return c:typeof():lua()
]],
    },

    {
      title = "santoku.web.async",
      desc = "Promise resolution as straight-line code: await returns TWO values, ok then result, and async blocks return promises that nest. Outside an async block, :await() without a callback raises; the callback form works anywhere.",
      runnable = false,
      code = [[
local js = require("santoku.web.js")
local async = require("santoku.web.async")
local Promise = js.Promise
async(function ()
  local ok, result = Promise:resolve(42):await()
  print("resolved:", ok, result)
  local ok2, e = Promise:reject("boom"):await()
  print("rejected:", ok2, e)
  local inner = async(function ()
    local _, v = Promise:resolve(21):await()
    return v * 2
  end)
  print("returns a promise:", inner:instanceof(Promise))
  local ok3, doubled = inner:await()
  print("nested:", ok3, doubled)
end)
Promise:resolve("later"):await(function (_, ok, v)
  print("callback form:", ok, v)
end)
]],
    },

    {
      title = "The DOM command buffer: writes",
      desc = "Every mutation queues into a shared linear-memory buffer and hits the DOM once on flush(); a nil attr value removes the attribute, style names starting with - set custom properties, prop passes true and false through as booleans, and focus takes an optional caret offset.",
      runnable = false,
      code = [[
local dom = require("santoku.web.dom")
dom.text("title", "hello")
dom.html("container", "<p>hi</p>")
dom.attr("title", "title", "a tooltip")
dom.attr("title", "title", nil)
dom.data("title", "sync", "dirty")
dom.style("title", "color", "teal")
dom.style("title", "--accent", "#f80")
dom.class_add("title", "active")
dom.class_rm("title", "hidden")
dom.insert_html("list", "beforeend", '<li id="item-1">first</li>')
dom.prop("item-1", "contentEditable", "true")
dom.focus("item-1", 3)
dom.blur("item-1")
dom.popover_show("menu")
dom.popover_hide("menu")
dom.scroll_to(0, 120)
dom.remove_children("container")
dom.remove("item-1")
dom.flush()
]],
    },

    {
      title = "The DOM command buffer: reads",
      desc = "read runs its queries immediately and returns one result per query in order, nil for missing elements; it does not flush queued writes, so flush first if reads must see them. rect is { top, left, bottom, right, width, height }, scroll is { scrollX, scrollY, innerWidth, innerHeight, scrollHeight }, cursor is the caret offset, and element_at returns the id of the closest data-id ancestor under a point.",
      runnable = false,
      code = [[
local dom = require("santoku.web.dom")
local text, tip, sync, active = dom.read(
  { "text", "title" },
  { "attr", "title", "title" },
  { "data", "title", "sync" },
  { "has_class", "title", "active" }
)
print(text, tip, sync, active)
local rect, scroll = dom.read({ "rect", "title" }, { "scroll" })
print("rect:", rect[1], rect[2], rect[3], rect[4], rect[5], rect[6])
print("scroll:", scroll[1], scroll[2], scroll[3], scroll[4], scroll[5])
local cursor, hit, checked = dom.read(
  { "cursor", "editor" },
  { "element_at", 40, 200 },
  { "prop", "note-1", "checked" }
)
print(cursor, hit, checked)
]],
    },

    {
      title = "dom.listen",
      desc = "Attach event handlers by element id, with window and body accepted as ids; a fourth argument passes addEventListener options, and handlers follow the this-first convention.",
      runnable = false,
      code = [[
local dom = require("santoku.web.dom")
dom.listen("item-1", "click", function ()
  dom.text("item-1", "clicked")
  dom.flush()
end)
dom.listen("window", "resize", function ()
  local scroll = dom.read({ "scroll" })
  print("viewport now:", scroll[3], scroll[4])
end)
dom.listen("body", "touchstart", function ()
  dom.class_add("body", "touch-active")
  dom.flush()
end, { passive = true })
]],
    },

    {
      title = "santoku.web.util: timing",
      desc = "Timer helpers over the platform: set_timeout and clear_timeout, after_frame (two requestAnimationFrames, so layout has settled), throttle (drops calls inside the window), and debounce (returns a promise for the eventual call; superseded calls resolve nil). atleast(fn, min_ms) pads fn to a minimum duration and needs an async context because it awaits a timer.",
      runnable = false,
      code = [[
local util = require("santoku.web.util")
util.set_timeout(function ()
  print("fires once, 100ms later")
end, 100)
util.after_frame(function ()
  print("layout settled")
end)
local log = util.throttle(function (msg)
  print("throttled:", msg)
end, 250)
log("first passes")
log("second inside 250ms is dropped")
local search = util.debounce(function (q)
  print("searching:", q)
  return q
end, 300)
search("l")
search("lu")
search("lua")
]],
    },

    {
      title = "santoku.web.util: promises",
      desc = "promise(fn) hands fn a single completion callback whose first argument picks resolve or reject; resolved and rejected build settled promises, and never() builds one that never settles.",
      runnable = false,
      code = [[
local util = require("santoku.web.util")
local async = require("santoku.web.async")
local p = util.promise(function (complete)
  util.set_timeout(function ()
    complete(true, "done")
  end, 50)
end)
async(function ()
  local ok, v = p:await()
  print("promise:", ok, v)
  local ok2, v2 = util.resolved(1):await()
  print("resolved:", ok2, v2)
  local ok3, e = util.rejected("nope"):await()
  print("rejected:", ok3, e)
end)
]],
    },

    {
      title = "santoku.web.util: web components",
      desc = "component(tag, opts) wraps val.class over HTMLElement and registers a custom element: shadow attaches a closed shadow root, sheets adopts constructed stylesheets, style and html fill the root, and connected/disconnected receive the element and its root. A build-time sibling, santoku.web.component, compiles an HTML component file to a JS custom-element definition.",
      runnable = false,
      code = [[
local util = require("santoku.web.util")
local js = require("santoku.web.js")
local sheet = util.stylesheet("p { color: teal }")
util.component("hello-card", {
  shadow = true,
  sheets = { sheet },
  style = "b { font-weight: 600 }",
  html = "<p>hello <b>world</b></p>",
  connected = function (this, root)
    print("attached, shadow root:", root ~= this)
  end,
  disconnected = function ()
    print("detached")
  end,
})
js.document.body:insertAdjacentHTML("beforeend", "<hello-card></hello-card>")
]],
    },

    {
      title = "santoku.web.util: storage, dates, responses",
      desc = "localStorage with nil-deletes, epoch-seconds date conversion in both directions, and a Response builder for service worker fetch handlers (request_text, request_json, and request_formdata read the other direction and await inside, so they need an async context).",
      runnable = false,
      code = [[
local util = require("santoku.web.util")
util.set_local("theme", "dark")
print("stored:", util.get_local("theme"))
util.set_local("theme", nil)
print("removed:", util.get_local("theme"))
local d = util.utc_date(1652745600)
print("round trip:", util.date_utc(d))
local resp = util.response('{"ok":true}', {
  status = 200,
  content_type = "application/json",
  headers = { ["Cache-Control"] = "no-store" },
})
print("status:", resp.status)
]],
    },

    {
      title = "santoku.web.socket: fetch",
      desc = "A fetch wrapper shaped for async blocks: fetch awaits inline and returns ok plus a response with status, lowercased headers, the raw Response, and a body() reader; request defers the await and adds cancel() via AbortController, marking aborted responses canceled; sleep awaits a timeout.",
      runnable = false,
      code = [[
local socket = require("santoku.web.socket")
local async = require("santoku.web.async")
async(function ()
  local ok, resp = socket.fetch("/api/items", { method = "GET" })
  print("ok:", ok, "status:", resp.status)
  print("content type:", resp.headers["content-type"])
  print("body:", resp.body())
  local req = socket.request("/api/slow")
  req.cancel()
  local ok2, resp2 = req.await()
  print("canceled:", ok2, resp2.canceled)
  socket.sleep(100)
  print("100ms later")
end)
]],
    },

    {
      title = "santoku.web.util: websockets",
      desc = "ws returns a send function and a close function: sends buffer until the socket opens, dropped connections retry with a backoff in seconds, and the each callback receives message (decoded text), reconnect, close, and error events.",
      runnable = false,
      code = [[
local util = require("santoku.web.util")
local send, close = util.ws({
  url = "wss://example.app/sync",
  retries = 3,
  backoffs = 2,
  each = function (event, ...)
    print("ws:", event, ...)
  end,
})
send("hello")
close()
]],
    },

    {
      title = "santoku.web.history",
      desc = "Hash-based navigation with mark tracking: state carries a monotonic id, a path-to-id mark map, and user data; back_to walks the real history back to a path's mark when one is in reach and replaces otherwise; anchors never prune and other marks expire past prune_distance.",
      runnable = false,
      code = [[
local history = require("santoku.web.history")({
  anchors = { "/" },
  prune_distance = 10,
})
history.push("/settings", { section = "profile" })
history.mark("/settings")
history.replace("/settings/security")
history.on_popstate(function ()
  print("state id now:", history.get_current_id())
end)
local walked = history.back_to("/")
print("walked back:", walked)
]],
    },

    {
      title = "santoku.web.rpc",
      desc = "Method calls across workers over MessageChannels: call(port, method, ...) deep-copies arguments (ports, buffers, and streams transfer) and resolves an array of the handler's return values; server(table) builds the event handler for the other side, and create_port performs the REGISTER_PORT handshake, resolving once the worker posts port_ready.",
      runnable = false,
      code = [[
local rpc = require("santoku.web.rpc")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local async = require("santoku.web.async")
local worker = js.Worker:new("/worker.js")
async(function ()
  local ok, port = rpc.create_port(worker):await()
  local ok2, results = rpc.call(port, "add", 1, 2):await()
  print("sum:", val.lua(results, true)[1])
end)
local handler = rpc.server({
  add = function (a, b) return a + b end,
})
]],
    },

    {
      title = "santoku.web.sqlite: the worker side",
      desc = "SQLite persists to OPFS through a SyncAccessHandle pool, which only exists in dedicated workers, so the database lives behind one: worker(path, handler) opens the file under the cooperative OPFS lock, hands your handler the santoku.sqlite wrapper, and serves the closure table it returns over rpc.",
      runnable = false,
      code = [[
require("santoku.web.sqlite.worker")("app.db", function (_, db)
  db.exec("create table if not exists items (id integer primary key, name text)")
  return true, {
    add = db.inserter("insert into items (name) values (?)"),
    name_of = db.getter("select name from items where id = ?"),
  }
end)
]],
    },

    {
      title = "santoku.web.sqlite: the main-thread proxy",
      desc = "proxy(bundle_path) spawns the worker, registers an rpc port, and returns a core whose every method is a remote call that awaits inline and spreads the worker's return values, plus a promise that resolves when the worker signals ready.",
      runnable = false,
      code = [[
local proxy = require("santoku.web.sqlite.proxy")
local async = require("santoku.web.async")
local core, ready = proxy("/db-worker.js")
async(function ()
  ready:await()
  local id = core.add("milk")
  print("inserted:", id)
  print("read back:", core.name_of(id))
end)
]],
    },

    {
      title = "santoku.web.pwa: content security policy",
      desc = "Build-time PWA scaffolding: csp.script_hashes collects sha256 hashes of inline scripts, policy assembles a strict CSP around them (self plus wasm-unsafe-eval for the runtime), and meta wraps it in a tag; sibling templates render index.html, manifest.json, and the service worker with precache and no_cache lists.",
      code = [[
local csp = require("santoku.web.pwa.csp")
local html = '<html><head><script>window.__boot = 1</script></head></html>'
local hashes = csp.script_hashes(html)
print("hash:", hashes[1])
print(csp.policy(hashes, { connect = "'self' https://api.example.app" }))
print(csp.meta(hashes))
]],
    },

    {
      title = "santoku.web.sqlite.proxy: the main-thread side of the database",
      desc = table.concat({
        "proxy(bundle_path, opts) spawns the dedicated worker from the same bundle ",
        "and returns two values: a core table and a readiness promise. core is a ",
        "metatable proxy, so any key you call on it becomes an RPC to the table your ",
        "worker returned, with arguments forwarded and multiple return values spread ",
        "back. That is why client code reads like ordinary function calls. Await the ",
        "second value before using core; it resolves true when the worker signals ",
        "ready. On failure the proxy adds a db-error class to document.body and ",
        "dispatches a db-error CustomEvent carrying detail.error, which is the ",
        "contract to hook if you want to show a database failure in your own UI.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local proxy = require("santoku.web.sqlite.proxy")

local bundle_js = js.document:querySelector('meta[name="bundle-js"]').content
local core, ready = proxy(bundle_js, {
  verbose = false,               -- log [proxy] lines to the console
  on_worker_connection = nil,    -- called once, when the worker signals ready
})

async(function ()
  local ok = ready:await()       -- await returns two values; ok is the first
  if ok == false then
    return                       -- body already carries the db-error class
  end
  local rows = core.list()       -- becomes an RPC call named "list"
end)
]],
    },

    {
      title = "santoku.web.pwa.index: the document generator",
      desc = table.concat({
        "index(opts) renders a complete HTML document. Every key below is a real ",
        "template slot; unknown keys are silently ignored, so a typo shows up as a ",
        "missing tag rather than an error. charset defaults to utf-8 and lang to en. ",
        "Two keys are handled in Lua rather than the template: transforms runs your ",
        "minifiers over the output, and csp = true injects a Content Security Policy ",
        "meta tag built from the hashes of the inline scripts actually present, which ",
        "errors if the document has no head to inject into.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local index = require("santoku.web.pwa.index")

index({
  title = ..., description = ..., keywords = ...,
  lang = "en", charset = "utf-8", viewport = ...,
  head = ..., body = ..., body_attrs = ..., body_content = ...,
  base_href = ..., plain = ...,
  manifest = "/manifest.json",
  icon = ..., ios_icon = ..., ms_icon = ...,
  favicon = ..., favicon_svg = ..., favicon_ico = ...,
  theme_color = ...,
  sw = "/serviceworker.js", sw_target = ...,
  initial = ...,                    -- emit the script that REGISTERS the worker
  broadcast_channel = ...,
  update_redirect = ..., update_redirect_delay = ...,
  verbose = ...,
  transforms = { html = ..., js = ..., css = ... },
  csp = true,
})
]],
    },

    {
      title = "santoku.web.pwa.sw: generating the service worker",
      desc = table.concat({
        "sw(opts) is a BUILD-TIME generator: it returns JavaScript as a string, which ",
        "you write to a served file. It is not a runtime module and requiring it in ",
        "client code does nothing useful. The option surface is exactly four keys, and ",
        "anything else you pass is ignored silently. precache paths are normalised to ",
        "start with a slash, no_cache entries become RegExp objects, and index_html is ",
        "the document served for navigation requests, which is how an offline app ",
        "answers a route it has never seen.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- in a client/static/serviceworker.tk.js template:
<%
  local sw = require("santoku.web.pwa.sw")
  return sw({
    nonce = ...,             -- changes the cache name, forcing a refill
    precache = { "/index.css", "/bundle.js" },
    no_cache = { "^/sync$", "^/api/" },   -- Lua patterns compiled to RegExp
    index_html = app_html,   -- served for navigations
  })
%>
]],
    },

    {
      title = "santoku.web.pwa.manifest: the web app manifest",
      desc = table.concat({
        "manifest(opts) renders a web app manifest as JSON, and is what makes an app ",
        "installable. It needs cjson available at build time. Render it to a served ",
        "file and point the document at it with index's manifest option. Note that ",
        "nothing in santoku-make reads a pwa block in your descriptor; these values ",
        "reach the manifest only because your own template passes them here.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local manifest = require("santoku.web.pwa.manifest")

manifest({
  name = ..., description = ..., id = ...,
  start_url = "/", scope = "/",
  display = "standalone",
  theme_color = ..., background_color = ...,
  orientation = ..., categories = { ... },
  handle_links = ..., launch_handler = ...,
  icons = { { src = "/icon-192.png", sizes = "192x192",
              type = "image/png", purpose = "any" } },
  screenshots = { ... },
})
]],
    },

  },

}

return {

  intro = table.concat({
    "santoku-mustache is the runtime template renderer of the framework: a single C module ",
    "wrapping the vendored mustach 1.2.10 library with every extension enabled, rendering ",
    "Mustache templates against plain Lua values. The module is one function: calling it ",
    "compiles a template (optionally with partials, and dedented by default) and returns a ",
    "render closure; calling that closure with a table, number, boolean, or nil produces a ",
    "string. On top of core Mustache (variables, dotted paths, sections, inversion, ",
    "iteration, partials, comments, custom delimiters) the extension set adds equality and ",
    "comparison guards on tag names, object iteration with {{*}}, and escaped-dot and JSON ",
    "pointer syntax for awkward keys. It is what toku web projects use for nginx config ",
    "generation and HTML template packs; ",
    "it is distinct from santoku-template, which expands <% ... %> Lua blocks at ",
    "build time.",
  }),

  examples = {

    {
      title = "Compile once, render many",
      desc = "Variables, dot notation, and missing keys. Numbers format through %.14g, booleans render as true or false, and the template is captured at compile time so one closure serves many contexts.",
      code = [[
local mch = require("santoku.mustache")
local render = mch("{{greeting}} {{target}}")
print(render({ greeting = "hello", target = "world" }))
print(mch("{{a.b.c}}")({ a = { b = { c = "value" } } }))
print("missing renders empty:", "[" .. mch("{{missing}}")({}) .. "]")
print(mch("{{num}} {{flag}}")({ num = 42, flag = true }))
print(mch("{{a}} {{b}}")({ a = 2.5, b = 1e15 }))
return render({ greeting = "goodbye", target = "moon" })
]],
    },

    {
      title = "Scalar contexts",
      desc = "The root context does not have to be a table: numbers, booleans, and nil are accepted, reached with {{.}} and testable with sections. Strings are not valid roots.",
      code = [[
local mch = require("santoku.mustache")
local dot = mch("{{.}}")
print(dot(42))
print(dot(true))
print("nil root:", "[" .. dot(nil) .. "]")
print(mch("{{#.}}yes{{/.}}")(true))
print(mch("{{^.}}no{{/.}}")(false))
return mch("{{.}} bottles")(99)
]],
    },

    {
      title = "Sections and truthiness",
      desc = "Sections gate on Lua-flavored truthiness: nil, false, 0, the empty string, and the empty table are falsy; everything else, including a single space, is truthy.",
      code = [[
local mch = require("santoku.mustache")
local sec = mch("{{#show}}yes{{/show}}{{^show}}no{{/show}}")
print("true:", sec({ show = true }))
print("false:", sec({ show = false }))
print("zero:", sec({ show = 0 }))
print("empty string:", sec({ show = "" }))
print("empty table:", sec({ show = {} }))
print("space:", sec({ show = " " }))
return sec({ show = "truthy" })
]],
    },

    {
      title = "Inverted sections as fallbacks",
      desc = "Pairing a section with its inversion is the idiomatic default-value pattern: render the value when present, a literal otherwise.",
      code = [[
local mch = require("santoku.mustache")
local host = mch("{{#host}}{{.}}{{/host}}{{^host}}localhost{{/host}}")
print(host({ host = "db1.internal" }))
print(host({}))
local flag = mch("{{^quiet}}verbose logging on{{/quiet}}")
print(flag({}))
return flag({ quiet = true })
]],
    },

    {
      title = "Iterating arrays",
      desc = "A contiguous array-like table repeats its section once per element: {{.}} is the element itself, and field tags read from element records.",
      code = [[
local mch = require("santoku.mustache")
print(mch("{{#items}}{{.}} {{/items}}")({ items = { 1, 2, 3 } }))
print(mch("{{#items}}{{.}}{{/items}}")({ items = {} }))
local rows = mch("{{#items}}{{name}}={{val}};{{/items}}")
return rows({ items = {
  { name = "a", val = 1 },
  { name = "b", val = 2 },
} })
]],
    },

    {
      title = "Nested context and the scope chain",
      desc = "Inside a section, bare names walk outward through every enclosing scope until one has the key. Dotted paths are stricter: only the first key uses the chain, the rest must resolve directly.",
      code = [[
local mch = require("santoku.mustache")
local ctx = { top = "T", name = "outer", child = { name = "inner" } }
print(mch("{{name}}-{{#child}}{{name}}{{/child}}")(ctx))
print(mch("{{#child}}{{top}}/{{name}}{{/child}}")(ctx))
print("no chain for dots:", "[" .. mch("{{child.top}}")(ctx) .. "]")
return mch("{{child.name}}")(ctx)
]],
    },

    {
      title = "Sections over scalars and nested arrays",
      desc = "Entering a truthy scalar exposes it as {{.}}, and {{#.}} re-enters the current item, which makes matrices walkable without names.",
      code = [[
local mch = require("santoku.mustache")
print(mch("{{#n}}n is {{.}}{{/n}}")({ n = 5 }))
print(mch("{{#rows}}{{#.}}{{.}}{{/.}}|{{/rows}}")({
  rows = { { 1, 2 }, { 3, 4 } },
}))
return mch("{{#word}}[{{.}}]{{/word}}")({ word = "hi" })
]],
    },

    {
      title = "What counts as an array",
      desc = "Iteration requires integer keys 1..n with no gaps. A sparse or mixed table is entered once as a plain object scope instead, and a table interpolated as a value renders empty.",
      code = [[
local mch = require("santoku.mustache")
print(mch("{{#items}}x {{/items}}")({ items = { 1, 2, 3 } }))
local sparse = { 1, 2, 3 }
sparse[5] = 9
print(mch("{{#items}}x {{/items}}")({ items = sparse }))
local mixed = { "a", "b", label = "tagged" }
print(mch("{{#m}}{{label}}{{/m}}")({ m = mixed }))
return "[" .. mch("{{t}}")({ t = { 1, 2 } }) .. "]"
]],
    },

    {
      title = "Object iteration with .* and {{*}}",
      desc = "Appending .* to a section name iterates a table's key-value pairs: {{*}} is the current key, {{.}} the value, and record fields resolve normally. A bare {{#*}} iterates the root. Order follows Lua's pairs and is unspecified for multi-key tables.",
      code = [[
local mch = require("santoku.mustache")
print(mch("{{#config.*}}{{*}}={{.}}{{/config.*}}")({
  config = { host = "localhost" },
}))
print(mch("{{#users.*}}{{*}}:{{name}}{{/users.*}}")({
  users = { u1 = { name = "Ada" } },
}))
return mch("{{#*}}{{*}}={{.}};{{/*}}")({ greeting = "hello" })
]],
    },

    {
      title = "HTML escaping",
      desc = "Double braces escape exactly four characters: angle brackets, ampersand, and double quote (single quotes pass through). Triple braces and the ampersand form emit raw.",
      code = [[
local mch = require("santoku.mustache")
print(mch("{{h}}")({ h = "<b>" }))
print(mch("{{{h}}}")({ h = "<b>" }))
print(mch("{{&h}}")({ h = "<b>" }))
print(mch("{{q}}")({ q = "\"a\" & 'b'" }))
return mch("<span>{{{icon}}}</span>")({
  icon = "<svg viewBox=\"0 0 24 24\"></svg>",
})
]],
    },

    {
      title = "Comments and custom delimiters",
      desc = "{{! ... }} emits nothing, and {{=open close=}} swaps the delimiter pair (up to 8 characters each) for the rest of the template, useful when the output format itself uses braces.",
      code = [[
local mch = require("santoku.mustache")
print(mch("a{{! hidden note }}b")({}))
local alt = mch("{{=<% %>=}}<% name %> and <%# on %>a section<%/ on %>")
print(alt({ name = "world", on = true }))
return mch("{{=[ ]=}}[greeting]")({ greeting = "hi" })
]],
    },

    {
      title = "Awkward key names",
      desc = "A backslash-escaped dot keeps a literal dot inside one key, a leading colon takes the rest of the tag verbatim, and a colon plus slash switches to JSON pointer syntax where slashes separate keys and dots are literal.",
      code = [[
local mch = require("santoku.mustache")
local ctx = { a = { b = "nested" }, ["a.b"] = "flat" }
print(mch("{{a.b}}")(ctx))
print(mch("{{a\\.b}}")(ctx))
print(mch("{{:#tag}}")({ ["#tag"] = "hash key" }))
print(mch("{{:/server/host}}")({ server = { host = "db1" } }))
return mch("{{:/a.b}}")(ctx)
]],
    },

    {
      title = "Equality guards",
      desc = "{{#name=value}} enters only when the selected value equals the literal, {{#name=!value}} only when it differs; numbers compare numerically, booleans as true/false. The same guard on a value tag renders the value conditionally.",
      code = [[
local mch = require("santoku.mustache")
local guard = mch("{{#env=prod}}PROD{{/env=prod}}{{#env=!prod}}NOT PROD{{/env=!prod}}")
print(guard({ env = "prod" }))
print(guard({ env = "dev" }))
print(mch("{{#n=42}}the answer{{/n=42}}")({ n = 42 }))
print(mch("{{#ok=true}}enabled{{/ok=true}}")({ ok = true }))
return mch("{{env=prod}}")({ env = "prod" })
]],
    },

    {
      title = "Comparison guards",
      desc = "Sections can compare with <, >, <=, >=: numbers numerically (parsed from the literal), strings byte-wise. The closing tag repeats the full guarded name.",
      code = [[
local mch = require("santoku.mustache")
local size = mch("{{#n>=10}}big{{/n>=10}}{{#n<10}}small{{/n<10}}")
print(size({ n = 42 }))
print(size({ n = 3 }))
print(mch("{{#price<=99.5}}deal{{/price<=99.5}}")({ price = 42.5 }))
return mch("{{#name>m}}late alphabet{{/name>m}}")({ name = "zed" })
]],
    },

    {
      title = "Partials",
      desc = "The partials table maps names to template strings or already compiled render closures (the compiled template is recovered from the closure). A partial name with no match renders empty.",
      code = [[
local mch = require("santoku.mustache")
local item = mch("<li>{{.}}</li>")
local list = mch("{{#items}}{{>item}}{{/items}}", {
  partials = { item = item },
})
print(list({ items = { 1, 2, 3 } }))
local wrap = mch("({{>inner}})", {
  partials = { inner = "[{{val}}]" },
})
print(wrap({ val = "hello" }))
return mch("a{{>nope}}b")({})
]],
    },

    {
      title = "Dedent",
      desc = "Compile strips the shared indentation of nonblank lines and one leading newline, so long-string templates can sit indented in source; pass dedent = false to keep the text verbatim.",
      code = [=[
local mch = require("santoku.mustache")
local tpl = mch([[
      hello
        world
    ]])
print(tpl({}))
print(mch("\nhello")({}))
local raw = mch("\n  hello\n    world\n", { dedent = false })
return raw({})
]=],
    },

    {
      title = "Render-time errors",
      desc = "Compile only dedents and captures: parsing happens per render, so malformed templates and bad roots (anything other than table, number, boolean, nil) raise when the closure is called. Extra arguments beyond the context are ignored.",
      code = [[
local mch = require("santoku.mustache")
local render = mch("{{x}}")
print(render({ x = 1 }, "extra args ignored"))
print("string root:", (pcall(render, "nope")))
local unclosed = mch("{{#a}}never closed")
print("compiles, fails on render:", (pcall(unclosed, { a = true })))
return "errors surface at render time"
]],
    },

    {
      title = "Templating an nginx server block",
      desc = "santoku server projects render their nginx conf from a context table, iterating location blocks and falling back on defaults.",
      code = [=[
local mch = require("santoku.mustache")
local conf = mch([[
server {
  listen {{port}};
  server_name {{domain}};
  worker_connections {{#workers}}{{.}}{{/workers}}{{^workers}}512{{/workers}};
{{#locations}}
  location {{path}} {
    proxy_pass {{upstream}};
  }
{{/locations}}
}
]])
return conf({
  port = 8080,
  domain = "docs.example.com",
  locations = {
    { path = "/api", upstream = "http://127.0.0.1:9001" },
    { path = "/", upstream = "http://127.0.0.1:9000" },
  },
})
]=],
    },

    {
      title = "The nginx pipeline",
      desc = "A server/nginx.tk.conf is a santoku-template block expanded by the build harness: it computes hashed asset names, then hands res/nginx.conf to santoku.mustache with the project config as context. That conf reaches nested config with dotted paths like {{nginx.port}} and {{nginx.error_log}}, and uses escaped dots, {{modules.my-app\\.search\\.init}}, to index a module table whose keys are full dotted module names.",
      code = [[
<%
  local ctx = nginx
  ctx.context_path = (client and client.context_path) or ""
  ctx.index_hashed = hashed("index.html")
  ctx.common_js_hashed = hashed("common.js")
  local env_lines = {}
  for _, k in ipairs((server or {}).nginx_env_vars or {}) do
    env_lines[#env_lines + 1] = "env " .. k .. ";"
  end
  ctx.nginx_env_lines = table.concat(env_lines, "\n")
  return require("santoku.mustache")(readfile("res/nginx.conf"))(ctx)
%>
]],
      runnable = false,
    },

    {
      title = "Template packs with mutual partials",
      desc = "The loader below reads every file under res/web/templates, keys it by dotted path, then compiles each one with the whole set as its partials table, so any template can include any sibling with {{>path.name}}. The runtime branch goes further: it mustaches out a Lua module that embeds the serialized pack and recompiles it on load.",
      code = [=[
local fs = require("santoku.fs")
local str = require("santoku.string")
local mch = require("santoku.mustache")
local serialize = require("santoku.serialize")

return function (readfile, root_dir, runtime)
  local tpl_dir = fs.join(root_dir, "res/web/templates")
  local tpl = {}
  for path, tp in fs.files(tpl_dir, true) do
    if tp == "file" then
      local key = str.match(path, "^.*/res/web/templates/(.*)%.[^.]+$")
      if key then
        tpl[str.gsub(key, "/", ".")] = readfile(path)
      end
    end
  end
  if not runtime then
    for k, v in pairs(tpl) do
      tpl[k] = mch(v, { partials = tpl })
    end
    return tpl
  else
    return mch([[
      local mch = require("santoku.mustache")
      local tpl = {{{embed}}}
      for k, v in pairs(tpl) do
        tpl[k] = mch(v, { partials = tpl })
      end
      return tpl
    ]])({ embed = serialize(tpl) })
  end
end
]=],
      runnable = false,
    },

  },

}

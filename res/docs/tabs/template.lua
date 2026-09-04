return {

  intro = table.concat({
    "santoku-template is a compile-once template engine: text with embedded <% ... %> ",
    "Lua blocks becomes a render function that runs each block in an environment you ",
    "provide. The surface is six functions (compile, compilefile, render, renderfile, ",
    "serialize_deps, deserialize_deps) plus three names injected into every block ",
    "(push, pop, showing), and the behavior on top is small and exact: blocks that ",
    "return a string emit it, blocks that return nothing run for side effects and ",
    "collapse the blank line they sit on, and a push/pop stack gates regions of ",
    "output. It is the engine behind .tk file expansion in the toku build harness, ",
    "where nginx confs, index.html, service workers, and Lua sources are rendered ",
    "against the project configuration before bundling. String-based examples run ",
    "in the page; the file-based and build-harness ones need a filesystem and are ",
    "shown for reading.",
  }),

  examples = {

    {
      title = "Compile once, render many",
      desc = "compile parses the template and returns a render function; call it with a fresh env each time.",
      code = [[
local template = require("santoku.template")
local render = template.compile("<title><% return title %></title>")
print(render({ title = "Hello, World!" }))
return render({ title = "Second render" })
]],
    },

    {
      title = "The entry points",
      desc = "render(data, env, global) is compile-then-call in one step; text without blocks passes through verbatim. compilefile and renderfile are the same pair reading through santoku.fs.",
      code = [[
local template = require("santoku.template")
print(template.render("plain text passes through verbatim"))
local via_render = template.render("<h1><% return heading %></h1>", { heading = "Docs" })
local via_compile = template.compile("<h1><% return heading %></h1>")({ heading = "Docs" })
print(via_render)
return tostring(via_render == via_compile)
]],
    },

    {
      title = "Environments and globals",
      desc = "Blocks resolve names from env first, then fall back to the global table you pass (often _G), wired onto the env's __index chain.",
      code = [[
local template = require("santoku.template")
print(template.render("<% return string.upper(word) %>", { word = "loud" }, _G))
return template.render("<% return table.concat(names, ', ') %>", { names = { "ada", "grace" } }, _G)
]],
    },

    {
      title = "Each render gets a fresh environment",
      desc = "The render call copies env into a new table, so blocks share state within one render but assignments never write back to your table and never leak into the next render.",
      code = [[
local template = require("santoku.template")
local t = template.compile("<% n = n + 1 %><% return 'n is ' .. n %>")
local env = { n = 1 }
print(t(env))
print(t(env))
return "caller still sees n = " .. env.n
]],
    },

    {
      title = "Blocks return strings, or nothing",
      desc = "A returned value must be a string (convert numbers with tostring; anything else raises); a block with no return contributes only its side effects, visible to later blocks in the same render.",
      code = [[
local template = require("santoku.template")
print(template.render("count: <% return tostring(count) %>", { count = 3 }, _G))
return template.render("<% total = price * qty %>total: <% return tostring(total) %>",
  { price = 3, qty = 4 }, _G)
]],
    },

    {
      title = "Loops and markup from library helpers",
      desc = "Blocks are plain Lua, so list rendering is just santoku.array passed through env; this is the exact pattern the library's own spec uses to emit repeated attributes.",
      code = [[
local template = require("santoku.template")
local arr = require("santoku.array")
local t = template.compile(
  "<ul><% return arr.concat(arr.map(items, function (x) return '<li>' .. x .. '</li>' end)) %></ul>")
return t({ arr = arr, items = { "one", "two", "three" } })
]],
    },

    {
      title = "Conditional sections with push and pop",
      desc = "push(cond) gates output until pop(); text and returned strings are dropped while the top is false.",
      code = [[
local template = require("santoku.template")
local t = template.compile("<% push(admin) %>[admin panel] <% pop() %>welcome")
print(t({ admin = true }))
return t({ admin = false })
]],
    },

    {
      title = "Nested gates compose with AND",
      desc = "push ANDs its condition with the current top, so an outer false gate silences everything inside it; showing() reads the current state from a block.",
      code = [[
local template = require("santoku.template")
local t = template.compile("<% push(a) %>A<% push(b) %>B<% pop() %>a-tail<% pop() %>end")
print(t({ a = true, b = true }))
print(t({ a = true, b = false }))
return t({ a = false, b = true })
]],
    },

    {
      title = "Hidden blocks still execute",
      desc = "Gating filters output only: every block runs regardless of the stack, so side effects made inside a false gate are visible afterward.",
      code = [[
local template = require("santoku.template")
local t = template.compile(table.concat({
  "<% push(false) %><% ran = true %>",
  "<% return 'hidden' %><% pop() %>",
  "<% return ran and 'the hidden block ran' or 'it did not run' %>",
}))
return t()
]],
    },

    {
      title = "Whitespace collapsing",
      desc = "A block that returns nothing joins the blank line it would leave behind, and trailing whitespace after the final block is trimmed.",
      code = [[
local template = require("santoku.template")
local out = template.render("first\n<% skipped = true %>\nlast")
print(out == "first\nlast")
local trimmed = template.render("value: <% return 'x' %>\n   ")
return "[" .. trimmed .. "]"
]],
    },

    {
      title = "Failures are immediate",
      desc = "A block that is not valid Lua raises during compile, before any render; a block returning a non-string raises during render. Both trap under santoku.error.pcall.",
      code = [[
local err = require("santoku.error")
local template = require("santoku.template")
local ok = err.pcall(function ()
  return template.compile("<% if %>")
end)
print("bad block compiles:", ok)
local ok2 = err.pcall(function ()
  return template.render("<% return 42 %>")
end)
print("number return renders:", ok2)
return tostring(ok) .. " " .. tostring(ok2)
]],
    },

    {
      title = "Includes are just env functions",
      desc = "The engine has no built-in include; pass a render helper through env and call it from a block.",
      code = [[
local template = require("santoku.template")
local pages = {
  layout = "<html><% return render(pages.body) %></html>",
  body = "<b><% return msg %></b>",
}
local env
env = {
  pages = pages,
  msg = "hello",
  render = function (s)
    return template.compile(s)(env)
  end,
}
return template.compile(pages.layout)(env)
]],
    },

    {
      title = "Files: compilefile, renderfile, include chains",
      desc = "File variants read through santoku.fs; a renderfile helper threading a shared env nests templates across files, as in the library's index -> body -> body-content fixtures.",
      runnable = false,
      code = [[
local template = require("santoku.template")
local fs = require("santoku.fs")
print(template.renderfile("test/res/template/title.html", { title = "Hello, World!" }))
local env
local function renderfile (fp)
  return template.compile(fs.readfile(fp))(env, _G)
end
env = { renderfile = renderfile, title = "Hello, World!" }
return template.render("<% return renderfile('test/res/template/index.html') %>", env)
]],
    },

    {
      title = "Makefile-style dependency rules",
      desc = "serialize_deps emits a rule from a dep set the caller recorded; deserialize_deps parses one back.",
      code = [[
local template = require("santoku.template")
print(template.serialize_deps("index.html.tk", "index.html", { ["res/header.html"] = true }))
local deps = template.deserialize_deps("index.html.tk: res/header.html res/footer.html")
local names = {}
for name in pairs(deps) do
  names[#names + 1] = name
end
table.sort(names)
return table.concat(names, ", ")
]],
    },

    {
      title = "How toku expands a .tk file",
      desc = "Any file with .tk in its name is templated and the .tk stripped from the destination (rules.copy, rules.exclude, and rules.template override the default); the harness renders against the project env plus a dep-recording readfile, then writes the output and a .d rule beside it.",
      runnable = false,
      code = [[
local template = require("santoku.template")
local fs = require("santoku.fs")
local deps = {}
local env = {
  client = { verbose = false },
  readfile = function (fp)
    deps[fp] = true
    return fs.readfile(fp)
  end,
}
local out = template.renderfile("client/lib/tasks/main.tk.lua", env, _G)
fs.writefile("client/lib/tasks/main.lua", out)
fs.writefile("client/lib/tasks/main.lua.d",
  template.serialize_deps("client/lib/tasks/main.tk.lua", "client/lib/tasks/main.lua", deps))
print("wrote main.lua and its dependency rule")
]],
    },

    {
      title = "Config values into Lua source",
      desc = "A .tk.lua file bakes project configuration into the shipped module. toku web projects hand every template an env carrying name, version, client, server, nginx, environment, component, target, dist_dir, work_dir, hashed, and readfile.",
      runnable = false,
      code = [[
return {
  name = <% return string.format("%q", name) %>,
  version = <% return string.format("%q", version) %>,
  verbose = <% return tostring(client.verbose or false) %>,
}
]],
    },

    {
      title = "Templating an nginx conf",
      desc = "A server/nginx.tk.conf is one block: it resolves content-hashed filenames with the build's hashed helper, assembles env directives from config, then hands the body off to santoku.mustache against a context table. The block's readfile calls are recorded as dependencies, so the conf rebuilds when res/nginx.conf changes.",
      runnable = false,
      code = [[
<%
  local ctx = nginx
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
    },

    {
      title = "Templating a PWA index.html",
      desc = "A static/index.tk.html builds the page with the santoku.web.pwa helpers: hashed asset links, the shared index builder over client.pwa config, and a CSP meta tag computed from the finished markup's script hashes.",
      runnable = false,
      code = [[
<%
  local tbl = require("santoku.table")
  local index = require("santoku.web.pwa.index")
  local csp = require("santoku.web.pwa.csp")
  local html = index(tbl.merge({
    manifest = "/" .. hashed("manifest.json"),
    favicon_svg = "/" .. hashed("favicon.svg"),
  }, client.pwa, {
    title = "Example App",
    sw = "/sw.js",
    head = '<link rel="stylesheet" href="/' .. hashed("index.css") .. '">',
  }))
  local meta = csp.meta(csp.script_hashes(html))
  return (html:gsub("<head>", function () return "<head>\n" .. meta end, 1))
%>
]],
    },

    {
      title = "The build engine templates itself",
      desc = "santoku-make's web project module is itself a .tk.lua file: when the engine is built, blocks inline its shell and config resources as base64 string constants, and at project build time add_templated_target_base64 decodes and renders them against the project env, so the shipped module carries its own templates.",
      runnable = false,
      code = [[
add_templated_target_base64(server_dir(base_server_run_sh),
  <% return str.quote(str.to_base64(readfile("res/web/run.sh"))) %>, server_env)
add_templated_target_base64(server_dir(base_server_luarocks_cfg),
  <% return str.quote(str.to_base64(readfile("res/web/luarocks.lua"))) %>, server_env)
]],
    },

    {
      title = "What a .tk file can see, in a web project",
      desc = table.concat({
        "The names available inside <% %> depend on which environment is rendering ",
        "the file, and this is the part most easily discovered by accident. The list ",
        "below is what web projects inject. readfile and root_dir let a template pull ",
        "in a sibling file, which is how a small .tk.conf renders a large template ",
        "kept in res. hashed maps a logical asset name to its content-hashed filename ",
        "and is the correct way to reference an asset from a template. The nginx ",
        "table is your descriptor's own block, and modules maps a module name to the ",
        "file path nginx should load it from. Note also that .tk expansion applies to ",
        "every file in an environment, including test/spec, so a spec may be a ",
        "template and embed build-time data the same way a source file can.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- available inside <% %> when rendering a web project's templates:
readfile(path)          -- read a file, relative to the project root
root_dir                -- absolute path to the project root
hashed(name)            -- a deferred token, resolved after hashing;
                        -- in server/nginx.tk.conf it is the final name
version                 -- the descriptor's version
client, nginx           -- the descriptor's client and nginx blocks
modules["a.b.c"]        -- path of the file nginx should load for that module
openresty_dir           -- the resolved OpenResty installation
lua_package_path        -- this environment's private rock tree
lua_package_cpath
dist_dir, public_dir    -- output directories for this environment
registered_public_files             -- client.public, as a set
public_files_static_for_precache    -- static files eligible for precaching
]],
    },

  },

}

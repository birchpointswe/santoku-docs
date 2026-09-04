local fs = require("santoku.fs")
local sys = require("santoku.system")

local hl_script = [[
const fs = require("fs");
const path = require("path");
const vendor = process.argv[2];
const dir = process.argv[3];
global.Prism = require(path.join(vendor, "prism-core.min.js"));
for (const c of process.argv.slice(4)) {
  if (c !== "core") {
    require(path.join(vendor, "prism-" + c + ".min.js"));
  }
}
for (const f of fs.readdirSync(dir).sort()) {
  if (!f.endsWith(".in")) continue;
  const raw = fs.readFileSync(path.join(dir, f), "utf8");
  const nl = raw.indexOf("\n");
  const lang = raw.slice(0, nl);
  const code = raw.slice(nl + 1);
  const grammar = Prism.languages[lang] || Prism.languages.text;
  const out = Prism.highlight(code, grammar, lang);
  fs.writeFileSync(path.join(dir, f.replace(/\.in$/, ".out")), out);
}
]]

local link_cls =
  "text-inherit underline decoration-dotted underline-offset-2 break-all hover:decoration-solid"

local btn_base =
  "block no-underline w-full text-left font-mono text-sm min-h-10 px-3 py-2 rounded-lg " ..
  "border-none cursor-pointer transition-colors duration-150 outline-none " ..
  "focus-visible:ring-2 focus-visible:ring-emerald-500 "
local btn_active = btn_base ..
  "bg-emerald-600/15 text-emerald-900 font-medium dark:bg-emerald-400/15 dark:text-emerald-200"
local btn_idle = btn_base ..
  "bg-transparent text-slate-600 hover:bg-slate-900/5 hover:text-slate-900 active:bg-slate-900/10 " ..
  "dark:text-slate-400 dark:hover:bg-white/5 dark:hover:text-slate-100 dark:active:bg-white/10"

local group_cls =
  "mt-5 first:mt-0 mb-1 px-3 text-xs font-medium uppercase tracking-wider " ..
  "text-slate-400 dark:text-slate-500"

local editor_cls =
  "block w-full box-border border-0 border-y border-solid " ..
  "border-slate-200 dark:border-slate-700 bg-stone-50 dark:bg-slate-900 " ..
  "text-slate-800 dark:text-slate-200 font-mono text-sm leading-relaxed p-4 outline-none " ..
  "focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-emerald-500"

local run_cls =
  "self-start inline-flex items-center justify-center min-h-10 px-5 rounded-full " ..
  "text-sm font-medium cursor-pointer border-none bg-emerald-600 text-white " ..
  "hover:bg-emerald-500 active:bg-emerald-700 transition-colors duration-150 outline-none " ..
  "focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2 " ..
  "focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-800"

local console_cls = "hidden font-mono text-xs leading-relaxed rounded-lg bg-slate-900 p-3"

local escapes = {
  ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ["\""] = "&quot;",
}

local function escape_html (s)
  return (string.gsub(s, "[&<>\"]", escapes))
end

local function pusher (out)
  return function (...)
    for i = 1, select("#", ...) do
      out[#out + 1] = (select(i, ...))
    end
  end
end

local function linkify (txt)
  local out = {}
  local pos = 1
  while true do
    local s, e = string.find(txt, "https?://%S+", pos)
    if not s then
      break
    end
    local url = string.match(string.sub(txt, s, e), "^(.-)[%.,;:%)%]]*$")
    e = s + #url - 1
    out[#out + 1] = escape_html(string.sub(txt, pos, s - 1))
    out[#out + 1] = "<a class=\"" .. link_cls .. "\" href=\"" .. escape_html(url) ..
      "\" target=\"_blank\" rel=\"noopener\">" .. escape_html(url) .. "</a>"
    pos = e + 1
  end
  out[#out + 1] = escape_html(string.sub(txt, pos))
  return table.concat(out)
end

local function load_docs (root_dir, gen_dir)
  local saved = package.path
  package.path = fs.join(gen_dir, "?.lua") .. ";"
    .. fs.join(root_dir, "client/lib/?.lua") .. ";" .. saved
  for k in pairs(package.loaded) do
    if string.match(k, "^docs%.") then
      package.loaded[k] = nil
    end
  end
  local ok, content = pcall(require, "docs.content")
  local ok_ids, ids = pcall(require, "docs.ids")
  package.path = saved
  if not ok then
    error(content)
  end
  if not ok_ids then
    error(ids)
  end
  return content, ids
end

local function highlight_all (content, opts)
  local dir = fs.join(opts.work_dir, "render-hl")
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  local script = fs.join(opts.work_dir, "render-hl.js")
  fs.writefile(script, hl_script)
  local keys = {}
  local n = 0
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      for j = 1, #tab.content.examples do
        local ex = tab.content.examples[j]
        n = n + 1
        local key = string.format("%04d", n)
        keys[tab.id .. "/" .. j] = key
        fs.writefile(fs.join(dir, key .. ".in"),
          (ex.lang or "lua") .. "\n" .. ex.code)
      end
    end
  end
  local cmd = { "node", script, opts.vendor_dir, dir }
  for i = 1, #opts.prism do
    cmd[#cmd + 1] = opts.prism[i]
  end
  sys.execute(cmd)
  local highlighted = {}
  for k, key in pairs(keys) do
    highlighted[k] = fs.readfile(fs.join(dir, key .. ".out"))
  end
  sys.execute({ "rm", "-rf", dir })
  fs.rm(script)
  return highlighted
end

local function group_tabs (tabs)
  local order, groups = {}, {}
  for i = 1, #tabs do
    local tab = tabs[i]
    local name = tab.group or "Libraries"
    if not groups[name] then
      groups[name] = {}
      order[#order + 1] = name
    end
    local items = groups[name]
    items[#items + 1] = tab
  end
  return order, groups
end

local function render_nav (order, groups, active_id)
  local out = {}
  local push = pusher(out)
  for i = 1, #order do
    local name = order[i]
    push("<div class=\"", group_cls, "\">", escape_html(name), "</div>")
    local items = groups[name]
    for j = 1, #items do
      local tab = items[j]
      if tab.id == active_id then
        push("<a href=\"/", tab.id, "\" aria-current=\"page\" class=\"", btn_active, "\">",
          escape_html(tab.label), "</a>")
      else
        push("<a href=\"/", tab.id, "\" class=\"", btn_idle, "\">",
          escape_html(tab.label), "</a>")
      end
    end
  end
  return table.concat(out)
end

local function render_card (ex, id, hl)
  local out = {}
  local push = pusher(out)
  local runnable = ex.runnable ~= false
  push("<div id=\"", id, "\" class=\"mb-5 scroll-mt-20 rounded-xl border border-solid ",
    "border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm overflow-hidden\">")
  push("<div class=\"px-4 pt-4 pb-3 flex items-start justify-between gap-3\">")
  push("<div class=\"min-w-0\">")
  push("<h3 class=\"m-0 text-base font-semibold font-mono\">", escape_html(ex.title), "</h3>")
  push("<p class=\"m-0 mt-1 text-sm text-slate-500 dark:text-slate-400\">", linkify(ex.desc), "</p>")
  push("</div>")
  if runnable then
    push("<span class=\"shrink-0 rounded-full bg-emerald-600/10 px-2.5 py-0.5 text-xs font-medium ",
      "text-emerald-700 dark:bg-emerald-400/15 dark:text-emerald-300\">Runnable</span>")
  else
    push("<span class=\"shrink-0 rounded-full border border-solid border-slate-300 px-2.5 py-0.5 ",
      "text-xs font-medium text-slate-500 dark:border-slate-600 dark:text-slate-400\">Illustrative</span>")
  end
  push("</div>")
  push("<code class=\"", editor_cls, " code-editor whitespace-pre-wrap language-",
    ex.lang or "lua", "\">", hl, "</code>")
  if runnable then
    push("<div class=\"px-4 py-3 flex flex-col gap-3\">")
    push("<button type=\"button\" data-run=\"", id, "\" class=\"", run_cls, "\">Run</button>")
    push("<div data-console class=\"", console_cls, "\"></div>")
    push("</div>")
  else
    push("<div class=\"px-4 py-3\">")
    push("<div class=\"text-xs text-slate-400 dark:text-slate-500\">",
      "Illustrative: runs outside the browser.</div>")
    push("</div>")
  end
  push("</div>")
  return table.concat(out)
end

local function render_panel_head (label, url, desc)
  local out = {}
  local push = pusher(out)
  push("<div class=\"mb-5\">")
  push("<div class=\"flex items-baseline justify-between gap-3 flex-wrap\">")
  push("<h2 class=\"m-0 text-xl md:text-2xl font-semibold tracking-tight font-mono\">",
    escape_html(label), "</h2>")
  if url then
    push("<a class=\"text-sm font-medium text-emerald-700 dark:text-emerald-400 no-underline ",
      "hover:underline\" href=\"", escape_html(url),
      "\" target=\"_blank\" rel=\"noopener\">View on GitHub</a>")
  end
  push("</div>")
  if desc then
    push("<p class=\"m-0 mt-1 text-sm md:text-base text-slate-500 dark:text-slate-400 max-w-prose\">",
      escape_html(desc), "</p>")
  end
  push("</div>")
  return table.concat(out)
end

local function render_tab_panel (tab, ids, highlighted)
  local out = {}
  local push = pusher(out)
  push("<div class=\"panel-in\">")
  push(render_panel_head(tab.label, tab.url, tab.desc))
  if tab.content then
    push("<p class=\"m-0 mb-6 text-sm md:text-base leading-relaxed text-slate-600 ",
      "dark:text-slate-300 max-w-prose\">", linkify(tab.content.intro), "</p>")
    local ex_ids = ids.example_ids(tab)
    for i = 1, #tab.content.examples do
      push(render_card(tab.content.examples[i], ex_ids[i],
        highlighted[tab.id .. "/" .. i]))
    end
  else
    push("<div class=\"rounded-xl border border-dashed border-slate-300 dark:border-slate-700 ",
      "p-8 text-sm text-slate-500 dark:text-slate-400\">",
      escape_html(tab.label), " documentation is coming soon.</div>")
  end
  push("</div>")
  return table.concat(out)
end

local function render_index_panel (order, groups)
  local out = {}
  local push = pusher(out)
  push("<div class=\"panel-in\">")
  push(render_panel_head("Documentation", nil, nil))
  for i = 1, #order do
    local name = order[i]
    push("<section class=\"mb-8\">")
    push("<h2 class=\"", group_cls, "\">", escape_html(name), "</h2>")
    local items = groups[name]
    for j = 1, #items do
      local tab = items[j]
      push("<a href=\"/", tab.id, "\" class=\"block mb-3 no-underline rounded-xl border ",
        "border-solid border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 ",
        "shadow-sm px-4 py-3\">")
      push("<div class=\"font-mono text-sm font-semibold text-slate-800 dark:text-slate-200\">",
        escape_html(tab.label), "</div>")
      push("<div class=\"m-0 mt-1 text-sm text-slate-500 dark:text-slate-400\">",
        escape_html(tab.desc), "</div>")
      push("</a>")
    end
    push("</section>")
  end
  push("</div>")
  return table.concat(out)
end

local function render_loader (bundle_path)
  return table.concat({
    "<script>(function () {\n",
    "var doc = document;\n",
    "var bundle = \"/", bundle_path, "\";\n",
    "var loaded = false;\n",
    "function load () {\n",
    "  if (loaded) { return; }\n",
    "  loaded = true;\n",
    "  var s = doc.createElement(\"script\");\n",
    "  s.src = bundle;\n",
    "  doc.head.appendChild(s);\n",
    "}\n",
    "doc.addEventListener(\"click\", function (ev) {\n",
    "  var t = ev.target;\n",
    "  while (t && t !== doc && !(t.getAttribute && t.getAttribute(\"data-run\"))) {\n",
    "    t = t.parentNode;\n",
    "  }\n",
    "  if (!t || t === doc || window.__docs_ready) { return; }\n",
    "  t.textContent = \"Loading...\";\n",
    "  t.setAttribute(\"data-pending\", \"1\");\n",
    "  load();\n",
    "});\n",
    "var rail = doc.getElementById(\"tab-rail\");\n",
    "var scrim = doc.getElementById(\"nav-scrim\");\n",
    "var toggle = doc.getElementById(\"nav-toggle\");\n",
    "var panels = doc.getElementById(\"tab-panels\");\n",
    "var top_bar = doc.getElementById(\"top-bar\");\n",
    "var sentinel = doc.getElementById(\"hero-sentinel\");\n",
    "var search = doc.getElementById(\"search-input\");\n",
    "var search_toggle = doc.getElementById(\"search-toggle\");\n",
    "var results = doc.getElementById(\"search-results\");\n",
    "rail.setAttribute(\"tabindex\", \"-1\");\n",
    "function close_nav () {\n",
    "  rail.classList.remove(\"nav-open\");\n",
    "  scrim.classList.remove(\"nav-open\");\n",
    "  doc.body.classList.remove(\"nav-locked\");\n",
    "  toggle.setAttribute(\"aria-expanded\", \"false\");\n",
    "  panels.removeAttribute(\"inert\");\n",
    "}\n",
    "function open_nav () {\n",
    "  rail.classList.add(\"nav-open\");\n",
    "  scrim.classList.add(\"nav-open\");\n",
    "  doc.body.classList.add(\"nav-locked\");\n",
    "  toggle.setAttribute(\"aria-expanded\", \"true\");\n",
    "  panels.setAttribute(\"inert\", \"\");\n",
    "  rail.focus();\n",
    "}\n",
    "toggle.addEventListener(\"click\", function () {\n",
    "  if (rail.classList.contains(\"nav-open\")) { close_nav(); } else { open_nav(); }\n",
    "});\n",
    "scrim.addEventListener(\"click\", close_nav);\n",
    "var desktop = window.matchMedia(\"(min-width: 768px)\");\n",
    "desktop.addEventListener(\"change\", function () {\n",
    "  close_nav();\n",
    "  top_bar.classList.remove(\"search-open\");\n",
    "});\n",
    "var trigger = 0;\n",
    "var scrolled = false;\n",
    "function measure () {\n",
    "  trigger = (sentinel.offsetTop || 0) - 56;\n",
    "  if (trigger < 0) { trigger = 0; }\n",
    "}\n",
    "function on_scroll () {\n",
    "  var now = (window.scrollY || 0) > trigger;\n",
    "  if (now !== scrolled) {\n",
    "    scrolled = now;\n",
    "    top_bar.classList.toggle(\"scrolled\", now);\n",
    "  }\n",
    "}\n",
    "measure();\n",
    "on_scroll();\n",
    "window.addEventListener(\"scroll\", on_scroll);\n",
    "window.addEventListener(\"resize\", function () { measure(); on_scroll(); });\n",
    "function close_search () {\n",
    "  top_bar.classList.remove(\"search-open\");\n",
    "  search_toggle.setAttribute(\"aria-expanded\", \"false\");\n",
    "  search.value = \"\";\n",
    "  results.classList.remove(\"open\");\n",
    "}\n",
    "window.__docs_close_search = close_search;\n",
    "search_toggle.addEventListener(\"click\", function () {\n",
    "  if (top_bar.classList.contains(\"search-open\")) {\n",
    "    close_search();\n",
    "  } else {\n",
    "    top_bar.classList.add(\"search-open\");\n",
    "    search_toggle.setAttribute(\"aria-expanded\", \"true\");\n",
    "    search.focus();\n",
    "  }\n",
    "});\n",
    "search.addEventListener(\"focus\", load);\n",
    "doc.getElementById(\"search-wrap\").addEventListener(\"click\", function (ev) {\n",
    "  ev.stopPropagation();\n",
    "});\n",
    "doc.addEventListener(\"click\", function () {\n",
    "  results.classList.remove(\"open\");\n",
    "  if (search.value === \"\") { close_search(); }\n",
    "});\n",
    "doc.addEventListener(\"keydown\", function (ev) {\n",
    "  if (ev.key !== \"Escape\") { return; }\n",
    "  if (rail.classList.contains(\"nav-open\")) {\n",
    "    close_nav();\n",
    "    toggle.focus();\n",
    "  } else if (results.classList.contains(\"open\")) {\n",
    "    results.classList.remove(\"open\");\n",
    "    search.blur();\n",
    "  } else if (top_bar.classList.contains(\"search-open\")) {\n",
    "    close_search();\n",
    "  }\n",
    "});\n",
    "doc.documentElement.classList.add(\"smooth-scroll\");\n",
    "})();</script>",
  })
end

local function render_shim (tabs)
  local out = {}
  local push = pusher(out)
  push("<script>(function () {\n")
  push("var tabs = {")
  for i = 1, #tabs do
    push("\"", tabs[i].id, "\":1")
    if i < #tabs then
      push(",")
    end
  end
  push("};\n")
  push("var h = window.location.hash.replace(/^#/, \"\");\n")
  push("if (!h) { return; }\n")
  push("var i = h.indexOf(\"--\");\n")
  push("var t = i > 0 ? h.slice(0, i) : h;\n")
  push("if (!tabs[t]) { return; }\n")
  push("window.location.replace(\"/\" + t + (i > 0 ? \"#\" + h : \"\"));\n")
  push("})();</script>")
  return table.concat(out)
end

local function render_head (m, title, desc, canonical, extra)
  local out = {}
  local push = pusher(out)
  push("<!doctype html>\n<html lang=\"en\">\n<head>\n")
  push("<meta charset=\"utf-8\">\n")
  push("<title>", escape_html(title), "</title>\n")
  push("<meta name=\"description\" content=\"", escape_html(desc), "\">\n")
  push("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n")
  push("<meta name=\"theme-color\" content=\"#1e293b\">\n")
  push("<link rel=\"canonical\" href=\"", canonical, "\">\n")
  push("<link rel=\"manifest\" href=\"/", m("manifest.json"), "\">\n")
  push("<link rel=\"apple-touch-icon\" href=\"/", m("apple-touch-icon.png"), "\">\n")
  push("<link rel=\"icon\" href=\"/", m("favicon.svg"), "\" type=\"image/svg+xml\">\n")
  push("<link rel=\"stylesheet\" href=\"/", m("index.css"), "\">\n")
  if extra then
    push(extra, "\n")
  end
  push("</head>\n")
  return table.concat(out)
end

local function render_body (shell, m, tab_id, lua_position, nav_html, panel_html, loader_html)
  local body = shell
  local n
  local body_open = "<body data-tab=\"" .. (tab_id or "") .. "\" class=\""
  body, n = string.gsub(body, "<body class=\"", function ()
    return body_open
  end, 1)
  assert(n == 1, "render: no <body class= anchor in res/body.html")
  local favicon_ref = "src=\"/" .. m("favicon.svg") .. "\""
  body, n = string.gsub(body, "src=\"/favicon%.svg\"", function ()
    return favicon_ref
  end)
  assert(n > 0, "render: no /favicon.svg reference in res/body.html")
  local function pat (s)
    return (string.gsub(s, "%p", "%%%0"))
  end
  local pos_anchor = "id=\"lua-position\" class=\"m-0 text-sm leading-relaxed " ..
    "text-slate-600 dark:text-slate-300\">"
  local pos_text = escape_html(lua_position)
  body, n = string.gsub(body, pat(pos_anchor),
    function (s)
      return s .. pos_text
    end, 1)
  assert(n == 1, "render: no lua-position anchor in res/body.html")
  local rail_anchor = "md:px-0 md:py-0 md:max-h-[calc(100vh-6rem)]\"></nav>"
  body, n = string.gsub(body, pat(rail_anchor),
    function (s)
      return string.sub(s, 1, #s - #"</nav>") .. nav_html .. "</nav>"
    end, 1)
  assert(n == 1, "render: no tab-rail anchor in res/body.html")
  local panels_anchor = "id=\"tab-panels\" class=\"flex-1 min-w-0 pt-5 md:pt-0\"></main>"
  body, n = string.gsub(body, pat(panels_anchor),
    function (s)
      return string.sub(s, 1, #s - #"</main>") .. panel_html .. "</main>"
    end, 1)
  assert(n == 1, "render: no tab-panels anchor in res/body.html")
  body, n = string.gsub(body, "</body>", function ()
    return loader_html .. "\n</body>"
  end, 1)
  assert(n == 1, "render: no </body> in res/body.html")
  return body
end

local function render_sitemap (site, tabs)
  local out = {}
  local push = pusher(out)
  push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  push("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
  push("<url><loc>", site, "/</loc></url>\n")
  for i = 1, #tabs do
    push("<url><loc>", site, "/", tabs[i].id, "</loc></url>\n")
  end
  push("</urlset>\n")
  return table.concat(out)
end

local function check_pages (pages, tabs, manifest)
  local assets = {
    ["/llms.txt"] = true,
    ["/llms-full.txt"] = true,
    ["/setup-toku.sh"] = true,
    ["/sitemap.xml"] = true,
    ["/logo.svg"] = true,
    ["/logo.png"] = true,
  }
  for _, h in pairs(manifest) do
    assets["/" .. h] = true
  end
  for i = 1, #tabs do
    if not pages["/" .. tabs[i].id] then
      error("render claim failed: tab " .. tabs[i].id .. " has no rendered page")
    end
  end
  for path, page in pairs(pages) do
    local html = string.gsub(page, "<code.-</code>", "")
    for ref in string.gmatch(html, "href=\"(/[^\"]*)\"") do
      local p, frag = string.match(ref, "^([^#]*)#?(.*)$")
      if not (pages[p] or assets[p] or string.match(p, "^/logo%-[%w%-]+%.png$")) then
        error("render claim failed: " .. path .. " links to " .. ref ..
          ", which resolves to nothing in the output")
      end
      if frag ~= "" and pages[p]
        and not string.find(pages[p], "id=\"" .. frag .. "\"", 1, true)
      then
        error("render claim failed: " .. path .. " links to " .. ref ..
          ", and " .. p .. " has no element with that id")
      end
    end
    for ref in string.gmatch(html, "src=\"(/[^\"]*)\"") do
      if not assets[ref] then
        error("render claim failed: " .. path .. " references " .. ref ..
          ", which resolves to nothing in the output")
      end
    end
  end
end

return function (opts)
  local content, ids = load_docs(opts.root_dir, opts.gen_dir)
  local manifest = dofile(opts.manifest_path)
  local function m (name)
    local h = manifest[name]
    if not h then
      error("render: hash manifest has no entry for " .. name)
    end
    return h
  end
  local shell = fs.readfile(fs.join(opts.root_dir, "res/body.html"))
  local highlighted = highlight_all(content, opts)
  local order, groups = group_tabs(content.tabs)
  local loader = render_loader(m("bundle.js"))
  local pages = {}
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    local head = render_head(m,
      tab.label .. " - " .. content.title, tab.desc,
      opts.site .. "/" .. tab.id)
    local body = render_body(shell, m, tab.id, content.lua_position,
      render_nav(order, groups, tab.id),
      render_tab_panel(tab, ids, highlighted),
      loader)
    pages["/" .. tab.id] = head .. body .. "</html>\n"
  end
  local index_head = render_head(m,
    content.title, content.summary,
    opts.site .. "/", render_shim(content.tabs))
  local index_body = render_body(shell, m, nil, content.lua_position,
    render_nav(order, groups, nil),
    render_index_panel(order, groups),
    loader)
  pages["/"] = index_head .. index_body .. "</html>\n"
  check_pages(pages, content.tabs, manifest)
  for path, html in pairs(pages) do
    local fp = path == "/" and fs.join(opts.public_dir, "index.html")
      or fs.join(opts.public_dir, string.sub(path, 2), "index.html")
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, html)
  end
  fs.writefile(fs.join(opts.public_dir, "sitemap.xml"),
    render_sitemap(opts.site, content.tabs))
end

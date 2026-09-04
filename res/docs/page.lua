local fs = require("santoku.fs")
local mch = require("santoku.mustache")
local content = require("docs.content")
local ids = require("docs.ids")
local highlighted = require("docs.highlighted")

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

local function render_tab_panel (tab)
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

local function render_head (hashed, title, desc, canonical, extra)
  local out = {}
  local push = pusher(out)
  push("<!doctype html>\n<html lang=\"en\">\n<head>\n")
  push("<meta charset=\"utf-8\">\n")
  push("<title>", escape_html(title), "</title>\n")
  push("<meta name=\"description\" content=\"", escape_html(desc), "\">\n")
  push("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n")
  push("<meta name=\"theme-color\" content=\"#1e293b\">\n")
  push("<link rel=\"canonical\" href=\"", canonical, "\">\n")
  push("<link rel=\"manifest\" href=\"/", hashed("manifest.json"), "\">\n")
  push("<link rel=\"apple-touch-icon\" href=\"/", hashed("apple-touch-icon.png"), "\">\n")
  push("<link rel=\"icon\" href=\"/", hashed("favicon.svg"), "\" type=\"image/svg+xml\">\n")
  push("<link rel=\"stylesheet\" href=\"/", hashed("index.css"), "\">\n")
  if extra then
    push(extra, "\n")
  end
  push("</head>\n")
  return table.concat(out)
end

return function (opts, tab_id)
  local readfile = opts.readfile
  local hashed = opts.hashed
  local site = opts.site
  local body_tpl = mch(readfile(fs.join(opts.root_dir, "res/docs/templates/body.html")))
  local loader_tpl = mch(readfile(fs.join(opts.root_dir, "res/docs/templates/loader.html")))
  local loader = loader_tpl({ bundle = hashed("bundle.js") })
  local order, groups = group_tabs(content.tabs)
  local head, body
  if tab_id then
    local tab
    for i = 1, #content.tabs do
      if content.tabs[i].id == tab_id then
        tab = content.tabs[i]
      end
    end
    if not tab then
      error("page: no tab with id " .. tab_id)
    end
    head = render_head(hashed,
      tab.label .. " - " .. content.title, tab.desc,
      site .. "/" .. tab.id)
    body = body_tpl({
      tab_id = tab_id,
      favicon = hashed("favicon.svg"),
      lua_position = content.lua_position,
      nav = render_nav(order, groups, tab_id),
      panel = render_tab_panel(tab),
      loader = loader,
    })
  else
    head = render_head(hashed,
      content.title, content.summary,
      site .. "/", render_shim(content.tabs))
    body = body_tpl({
      tab_id = "",
      favicon = hashed("favicon.svg"),
      lua_position = content.lua_position,
      nav = render_nav(order, groups, nil),
      panel = render_index_panel(order, groups),
      loader = loader,
    })
  end
  return head .. body .. "</html>\n"
end

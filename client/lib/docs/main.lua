-- luacheck: globals loadstring setfenv

local js = require("santoku.web.js")
local content = require("docs.content")

local document = js.document
local window = js.window

local btn_base =
  "w-full text-left font-mono text-sm min-h-10 px-3 py-2 rounded-lg border-none " ..
  "cursor-pointer transition-colors duration-150 outline-none " ..
  "focus-visible:ring-2 focus-visible:ring-emerald-500 "
local btn_active = btn_base ..
  "bg-emerald-600/15 text-emerald-900 font-medium dark:bg-emerald-400/15 dark:text-emerald-200"
local btn_idle = btn_base ..
  "bg-transparent text-slate-600 hover:bg-slate-900/5 hover:text-slate-900 active:bg-slate-900/10 " ..
  "dark:text-slate-400 dark:hover:bg-white/5 dark:hover:text-slate-100 dark:active:bg-white/10"

local group_cls =
  "mt-5 first:mt-0 mb-1 px-3 text-xs font-medium uppercase tracking-wider " ..
  "text-slate-400 dark:text-slate-500"

local line_cls = "whitespace-pre-wrap break-words text-slate-300"
local result_cls = "whitespace-pre-wrap break-words text-emerald-400"
local error_cls = "whitespace-pre-wrap break-words text-red-400"

local function create (tag, cls)
  local e = document:createElement(tag)
  if cls then
    e.className = cls
  end
  return e
end

local function text_el (tag, cls, txt)
  local e = create(tag, cls)
  e.textContent = txt
  return e
end

local function count_lines (s)
  local n = 1
  for _ in s:gmatch("\n") do
    n = n + 1
  end
  return n
end

local function append_text (el, txt)
  if #txt > 0 then
    el:appendChild(document:createTextNode(txt))
  end
end

local function rich_text_el (tag, cls, txt)
  local el = create(tag, cls)
  local pos = 1
  while true do
    local s, e = txt:find("https?://%S+", pos)
    if not s then
      break
    end
    local url = txt:sub(s, e):match("^(.-)[%.,;:%)%]]*$")
    e = s + #url - 1
    append_text(el, txt:sub(pos, s - 1))
    local a = create("a",
      "text-inherit underline decoration-dotted underline-offset-2 break-all " ..
      "hover:decoration-solid")
    a.textContent = url
    a:setAttribute("href", url)
    a:setAttribute("target", "_blank")
    a:setAttribute("rel", "noopener")
    el:appendChild(a)
    pos = e + 1
  end
  append_text(el, txt:sub(pos))
  return el
end

local function run_snippet (code)
  local lines = {}
  local chunk, syntax_err = loadstring(code, "=example")
  if not chunk then
    return lines, false, { tostring(syntax_err) }, 1
  end
  local fenv = setmetatable({
    print = function (...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
      end
      lines[#lines + 1] = table.concat(parts, "\t")
    end,
    os = setmetatable({
      exit = function (code)
        error("os.exit(" .. tostring(code or 0) .. ") called", 2)
      end,
    }, { __index = os }),
  }, { __index = _G })
  setfenv(chunk, fenv)
  local function collect (ok, ...)
    local n = select("#", ...)
    local vals = {}
    for i = 1, n do
      vals[i] = tostring((select(i, ...)))
    end
    return ok, vals, n
  end
  local has_hook = type(debug) == "table" and type(debug.sethook) == "function"
  if has_hook then
    debug.sethook(function ()
      error("instruction limit exceeded", 2)
    end, "", 10000000)
  end
  local real_print = _G.print
  _G.print = fenv.print
  local ok, vals, nvals = collect(pcall(chunk))
  _G.print = real_print
  if has_hook then
    debug.sethook()
  end
  return lines, ok, vals, nvals
end

local function render_console (con, lines, ok, vals, nvals)
  con.innerHTML = ""
  for i = 1, #lines do
    con:appendChild(text_el("div", line_cls, lines[i]))
  end
  if ok then
    local shown
    if nvals == 0 then
      shown = "(no return value)"
    else
      shown = table.concat(vals, ", ")
    end
    con:appendChild(text_el("div", result_cls, "=> " .. shown))
  else
    con:appendChild(text_el("div", error_cls, "error: " .. tostring(vals[1])))
  end
end

local function badge (runnable)
  if runnable then
    return text_el("span",
      "shrink-0 rounded-full bg-emerald-600/10 px-2.5 py-0.5 text-xs font-medium " ..
      "text-emerald-700 dark:bg-emerald-400/15 dark:text-emerald-300",
      "Runnable")
  end
  return text_el("span",
    "shrink-0 rounded-full border border-solid border-slate-300 px-2.5 py-0.5 text-xs " ..
    "font-medium text-slate-500 dark:border-slate-600 dark:text-slate-400",
    "Illustrative")
end

local function render_card (ex, id)
  local card = create("div",
    "mb-5 scroll-mt-20 rounded-xl border border-solid border-slate-200 dark:border-slate-700 " ..
    "bg-white dark:bg-slate-800 shadow-sm overflow-hidden")
  card.id = id
  local head = create("div", "px-4 pt-4 pb-3 flex items-start justify-between gap-3")
  local titles = create("div", "min-w-0")
  titles:appendChild(text_el("h3", "m-0 text-base font-semibold font-mono", ex.title))
  titles:appendChild(rich_text_el("p", "m-0 mt-1 text-sm text-slate-500 dark:text-slate-400", ex.desc))
  head:appendChild(titles)
  head:appendChild(badge(ex.runnable ~= false))
  card:appendChild(head)
  local editor_cls =
    "block w-full box-border border-0 border-y border-solid " ..
    "border-slate-200 dark:border-slate-700 bg-stone-50 dark:bg-slate-900 " ..
    "text-slate-800 dark:text-slate-200 font-mono text-sm leading-relaxed p-4 outline-none " ..
    "focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-emerald-500"
  local prism = window.Prism
  if ex.runnable == false then
    local code_el = create("code",
      editor_cls .. " code-editor whitespace-pre-wrap language-" .. (ex.lang or "lua"))
    code_el.textContent = ex.code
    if prism then
      prism:highlightElement(code_el)
    end
    card:appendChild(code_el)
    local foot = create("div", "px-4 py-3")
    foot:appendChild(text_el("div",
      "text-xs text-slate-400 dark:text-slate-500",
      "Illustrative: runs outside the browser."))
    card:appendChild(foot)
    return card
  end
  local get_code
  local codejar = window.CodeJar
  if prism and codejar then
    local code_el = create("code", editor_cls .. " code-editor language-lua")
    code_el.textContent = ex.code
    window:CodeJar(code_el, function (_, ed)
      prism:highlightElement(ed)
    end)
    prism:highlightElement(code_el)
    card:appendChild(code_el)
    get_code = function ()
      return code_el.textContent
    end
  else
    local ta = create("textarea", editor_cls .. " resize-y")
    ta:setAttribute("spellcheck", "false")
    ta:setAttribute("autocomplete", "off")
    ta:setAttribute("autocapitalize", "off")
    ta:setAttribute("wrap", "off")
    ta.rows = count_lines(ex.code)
    ta.value = ex.code
    card:appendChild(ta)
    get_code = function ()
      return ta.value
    end
  end
  local foot = create("div", "px-4 py-3 flex flex-col gap-3")
  local btn = text_el("button",
    "self-start inline-flex items-center justify-center min-h-10 px-5 rounded-full " ..
    "text-sm font-medium cursor-pointer border-none bg-emerald-600 text-white " ..
    "hover:bg-emerald-500 active:bg-emerald-700 transition-colors duration-150 outline-none " ..
    "focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2 " ..
    "focus-visible:ring-offset-white dark:focus-visible:ring-offset-slate-800",
    "Run")
  foot:appendChild(btn)
  local con = create("div",
    "hidden font-mono text-xs leading-relaxed rounded-lg bg-slate-900 p-3")
  foot:appendChild(con)
  card:appendChild(foot)
  btn:addEventListener("click", function ()
    con.classList:remove("hidden")
    local lines, ok, vals, nvals = run_snippet(get_code())
    render_console(con, lines, ok, vals, nvals)
  end)
  return card
end

local function render_panel_head (panel, tab)
  local head = create("div", "mb-5")
  local row = create("div", "flex items-baseline justify-between gap-3 flex-wrap")
  row:appendChild(text_el("h2",
    "m-0 text-xl md:text-2xl font-semibold tracking-tight font-mono", tab.label))
  if tab.url then
    local a = create("a",
      "text-sm font-medium text-emerald-700 dark:text-emerald-400 no-underline hover:underline")
    a.textContent = "View on GitHub"
    a:setAttribute("href", tab.url)
    a:setAttribute("target", "_blank")
    a:setAttribute("rel", "noopener")
    row:appendChild(a)
  end
  head:appendChild(row)
  if tab.desc then
    head:appendChild(text_el("p",
      "m-0 mt-1 text-sm md:text-base text-slate-500 dark:text-slate-400 max-w-prose", tab.desc))
  end
  panel:appendChild(head)
end

local function slug (s)
  local out = string.lower(s or "")
  out = string.gsub(out, "[^%w]+", "-")
  out = string.gsub(out, "^%-+", "")
  out = string.gsub(out, "%-+$", "")
  return out
end

local function example_ids (tab)
  local ids, seen = {}, {}
  for i = 1, #tab.content.examples do
    local base = tab.id .. "--" .. slug(tab.content.examples[i].title)
    local id, n = base, 1
    while seen[id] do
      n = n + 1
      id = base .. "-" .. n
    end
    seen[id] = true
    ids[i] = id
  end
  return ids
end

local function render_panel (panel, tab)
  render_panel_head(panel, tab)
  if tab.content then
    panel:appendChild(rich_text_el("p",
      "m-0 mb-6 text-sm md:text-base leading-relaxed text-slate-600 dark:text-slate-300 max-w-prose",
      tab.content.intro))
    local ids = example_ids(tab)
    for i = 1, #tab.content.examples do
      panel:appendChild(render_card(tab.content.examples[i], ids[i]))
    end
  else
    panel:appendChild(text_el("div",
      "rounded-xl border border-dashed border-slate-300 dark:border-slate-700 " ..
      "p-8 text-sm text-slate-500 dark:text-slate-400",
      tab.label .. " documentation is coming soon."))
  end
end

local function boot ()
  local tabs = content.tabs
  local position = document:getElementById("lua-position")
  position.textContent = content.lua_position
  local rail = document:getElementById("tab-rail")
  local panels = document:getElementById("tab-panels")
  local scrim = document:getElementById("nav-scrim")
  local toggle = document:getElementById("nav-toggle")
  local top_bar = document:getElementById("top-bar")
  local sentinel = document:getElementById("hero-sentinel")
  local search = document:getElementById("search-input")
  local search_toggle = document:getElementById("search-toggle")
  local results = document:getElementById("search-results")
  local body = document.body
  local desktop = window:matchMedia("(min-width: 768px)")

  rail:setAttribute("tabindex", "-1")

  if window.history and window.history.scrollRestoration then
    window.history.scrollRestoration = "manual"
  end

  local function close_nav ()
    rail.classList:remove("nav-open")
    scrim.classList:remove("nav-open")
    body.classList:remove("nav-locked")
    toggle:setAttribute("aria-expanded", "false")
    panels:removeAttribute("inert")
  end

  local function open_nav ()
    rail.classList:add("nav-open")
    scrim.classList:add("nav-open")
    body.classList:add("nav-locked")
    toggle:setAttribute("aria-expanded", "true")
    panels:setAttribute("inert", "")
    rail:focus()
  end

  toggle:addEventListener("click", function ()
    if rail.classList:contains("nav-open") then
      close_nav()
    else
      open_nav()
    end
  end)

  scrim:addEventListener("click", function ()
    close_nav()
  end)

  desktop:addEventListener("change", function ()
    close_nav()
    top_bar.classList:remove("search-open")
  end)

  local trigger = 0
  local scrolled = false

  local function measure ()
    trigger = (sentinel.offsetTop or 0) - 56
    if trigger < 0 then
      trigger = 0
    end
  end

  local function on_scroll ()
    local now = (window.scrollY or 0) > trigger
    if now ~= scrolled then
      scrolled = now
      if now then
        top_bar.classList:add("scrolled")
      else
        top_bar.classList:remove("scrolled")
      end
    end
  end

  measure()
  on_scroll()
  window:addEventListener("scroll", on_scroll)
  window:addEventListener("resize", function ()
    measure()
    on_scroll()
  end)

  local index = {}
  local entries = {}

  local function activate (id, no_scroll)
    for i = 1, #entries do
      local entry = entries[i]
      if entry.id == id then
        if not entry.rendered then
          entry.rendered = true
          render_panel(entry.panel, entry.tab)
        end
        entry.btn.className = btn_active
        entry.btn:setAttribute("aria-current", "true")
        entry.panel.classList:remove("hidden")
      else
        entry.btn.className = btn_idle
        entry.btn:removeAttribute("aria-current")
        entry.panel.classList:add("hidden")
      end
    end
    if not no_scroll then
      local anchor = document:getElementById("content-top")
      if anchor then
        anchor:scrollIntoView()
      end
    end
  end

  local groups = {}
  local group_order = {}
  for i = 1, #tabs do
    local tab = tabs[i]
    local name = tab.group or "Libraries"
    local group = groups[name]
    if not group then
      group = {}
      groups[name] = group
      group_order[#group_order + 1] = name
    end
    group[#group + 1] = tab
  end

  for gi = 1, #group_order do
    local name = group_order[gi]
    rail:appendChild(text_el("div", group_cls, name))
    local group = groups[name]
    for ti = 1, #group do
      local tab = group[ti]
      local btn = text_el("button", btn_idle, tab.label)
      btn:setAttribute("type", "button")
      rail:appendChild(btn)
      local panel = create("div", "hidden panel-in")
      panels:appendChild(panel)
      entries[#entries + 1] = { id = tab.id, btn = btn, panel = panel, tab = tab }
      index[#index + 1] = {
        id = tab.id,
        tab_id = tab.id,
        label = tab.label,
        sub = name,
        is_tab = true,
        title_hay = string.lower(tab.label),
        hay = string.lower(tab.label .. " " .. (tab.desc or "")),
      }
      if tab.content then
        local ids = example_ids(tab)
        for ei = 1, #tab.content.examples do
          local ex = tab.content.examples[ei]
          index[#index + 1] = {
            id = ids[ei],
            tab_id = tab.id,
            label = ex.title,
            sub = tab.label,
            title_hay = string.lower(ex.title),
            hay = string.lower(ex.title .. " " .. (ex.desc or "") .. " " .. (ex.code or "")),
          }
        end
      end
      btn:addEventListener("click", function ()
        activate(tab.id)
        close_nav()
      end)
    end
  end

  local function goto_entry (item)
    activate(item.tab_id, true)
    close_nav()
    local el = document:getElementById(item.is_tab and "content-top" or item.id)
    if el then
      el:scrollIntoView()
    end
    if window.history and window.history.replaceState then
      window.history:replaceState(nil, "", "#" .. item.id)
    end
  end

  local function close_results ()
    results.classList:remove("open")
  end

  local close_search

  local function render_results (matches, total, query)
    results.innerHTML = ""
    results:appendChild(text_el("div",
      "px-4 pb-2 text-xs font-medium uppercase tracking-wider text-slate-400 dark:text-slate-500",
      query == "" and "All libraries" or "Results"))
    if #matches == 0 then
      results:appendChild(text_el("div",
        "px-4 py-3 text-sm text-slate-500 dark:text-slate-400",
        "Nothing matches that search."))
      return
    end
    for i = 1, #matches do
      local item = matches[i]
      local row = create("button",
        "w-full text-left px-4 py-2 border-none bg-transparent cursor-pointer " ..
        "hover:bg-slate-900/5 dark:hover:bg-white/5 outline-none " ..
        "focus-visible:bg-slate-900/5 dark:focus-visible:bg-white/5")
      row:setAttribute("type", "button")
      row:appendChild(text_el("div",
        "font-mono text-sm text-slate-800 dark:text-slate-200", item.label))
      row:appendChild(text_el("div",
        "text-xs text-slate-500 dark:text-slate-400",
        item.is_tab and (item.sub .. " library") or item.sub))
      row:addEventListener("click", function ()
        goto_entry(item)
        close_search()
      end)
      results:appendChild(row)
    end
    if total > #matches then
      results:appendChild(text_el("div",
        "px-4 pt-2 text-xs text-slate-400 dark:text-slate-500",
        "Showing " .. #matches .. " of " .. total .. " matches. Keep typing to narrow."))
    end
  end

  local max_results = 30

  local function run_search ()
    local query = string.lower(search.value or "")
    local titled, bodied = {}, {}
    for i = 1, #index do
      local item = index[i]
      if query == "" then
        if item.is_tab then
          titled[#titled + 1] = item
        end
      elseif string.find(item.title_hay, query, 1, true) then
        titled[#titled + 1] = item
      elseif string.find(item.hay, query, 1, true) then
        bodied[#bodied + 1] = item
      end
    end
    local total = #titled + #bodied
    local matches = {}
    for i = 1, #titled do
      if #matches >= max_results then break end
      matches[#matches + 1] = titled[i]
    end
    for i = 1, #bodied do
      if #matches >= max_results then break end
      matches[#matches + 1] = bodied[i]
    end
    render_results(matches, total, query)
    results.classList:add("open")
  end

  search:addEventListener("input", run_search)
  search:addEventListener("focus", run_search)

  close_search = function ()
    top_bar.classList:remove("search-open")
    search_toggle:setAttribute("aria-expanded", "false")
    search.value = ""
    close_results()
  end

  search_toggle:addEventListener("click", function ()
    if top_bar.classList:contains("search-open") then
      close_search()
    else
      top_bar.classList:add("search-open")
      search_toggle:setAttribute("aria-expanded", "true")
      search:focus()
    end
  end)

  document:addEventListener("keydown", function (ev)
    if ev.key ~= "Escape" then
      return
    end
    if rail.classList:contains("nav-open") then
      close_nav()
      toggle:focus()
    elseif results.classList:contains("open") then
      close_results()
      search:blur()
    elseif top_bar.classList:contains("search-open") then
      close_search()
    end
  end)

  document:getElementById("search-wrap"):addEventListener("click", function (ev)
    ev:stopPropagation()
  end)

  document:addEventListener("click", function ()
    close_results()
    if search.value == "" then
      close_search()
    end
  end)

  local by_id = {}
  for i = 1, #index do
    by_id[index[i].id] = index[i]
  end

  local hash = string.gsub(window.location.hash or "", "^#", "")
  local target = hash ~= "" and by_id[hash] or nil
  if target then
    activate(target.tab_id, true)
    local el = document:getElementById(target.id)
    if el and not target.is_tab then
      el:scrollIntoView()
    end
  else
    activate(tabs[1].id, true)
    window:scrollTo(0, 0)
  end
  measure()
  on_scroll()
  document.documentElement.classList:add("smooth-scroll")
end
if document.readyState == "loading" then
  document:addEventListener("DOMContentLoaded", function ()
    boot()
  end)
else
  boot()
end

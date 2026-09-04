-- luacheck: globals loadstring setfenv

local js = require("santoku.web.js")
local content = require("docs.content")
local ids = require("docs.ids")

local document = js.document
local window = js.window

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

local function enhance_examples ()
  local prism = window.Prism
  local codejar = window.CodeJar
  local btns = document:querySelectorAll("[data-run]")
  for i = 0, btns.length - 1 do
    local btn = btns:item(i)
    local card = document:getElementById(btn:getAttribute("data-run"))
    local code_el = card and card:querySelector("code.code-editor")
    local con = card and card:querySelector("[data-console]")
    if code_el and con then
      if prism and codejar then
        window:CodeJar(code_el, function (_, ed)
          prism:highlightElement(ed)
        end)
      end
      btn.textContent = "Run"
      btn:addEventListener("click", function ()
        con.classList:remove("hidden")
        local lines, ok, vals, nvals = run_snippet(code_el.textContent)
        render_console(con, lines, ok, vals, nvals)
      end)
    end
  end
end

local function run_pending ()
  local pending = document:querySelectorAll("[data-run][data-pending]")
  for i = 0, pending.length - 1 do
    local btn = pending:item(i)
    btn:removeAttribute("data-pending")
    btn:click()
  end
end

local function setup_search ()
  local search = document:getElementById("search-input")
  local results = document:getElementById("search-results")
  local current_tab = document.body:getAttribute("data-tab")

  local index = {}
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    index[#index + 1] = {
      id = tab.id,
      tab_id = tab.id,
      url = "/" .. tab.id,
      label = tab.label,
      sub = tab.group or "Libraries",
      is_tab = true,
      title_hay = string.lower(tab.label),
      hay = string.lower(tab.label .. " " .. (tab.desc or "")),
    }
    if tab.content then
      local ex_ids = ids.example_ids(tab)
      for ei = 1, #tab.content.examples do
        local ex = tab.content.examples[ei]
        index[#index + 1] = {
          id = ex_ids[ei],
          tab_id = tab.id,
          url = "/" .. tab.id .. "#" .. ex_ids[ei],
          label = ex.title,
          sub = tab.label,
          title_hay = string.lower(ex.title),
          hay = string.lower(ex.title .. " " .. (ex.desc or "") .. " " .. (ex.code or "")),
        }
      end
    end
  end

  local function goto_entry (item)
    if item.tab_id == current_tab then
      local el = document:getElementById(item.is_tab and "content-top" or item.id)
      if el then
        el:scrollIntoView()
      end
      if not item.is_tab and window.history and window.history.replaceState then
        window.history:replaceState(nil, "", "#" .. item.id)
      end
      window:__docs_close_search()
    else
      window.location.href = item.url
    end
  end

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

  if search.value ~= "" or search:matches(":focus") then
    run_search()
  end
end

local function boot ()
  window.__docs_ready = true
  enhance_examples()
  run_pending()
  setup_search()
end

if document.readyState == "loading" then
  document:addEventListener("DOMContentLoaded", function ()
    boot()
  end)
else
  boot()
end

local fs = require("santoku.fs")
local env = require("santoku.env")

local loadchunk = loadstring or load

local function fail (what, lines)
  local out = { "docs claim check failed: " .. what }
  for i = 1, #lines do
    out[#out + 1] = "  " .. lines[i]
  end
  error(table.concat(out, "\n"), 0)
end

local function sorted (set)
  local out = {}
  for k in pairs(set) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

local function absent (a, b)
  local out = {}
  for _, k in ipairs(sorted(a)) do
    if not b[k] then
      out[#out + 1] = k
    end
  end
  return out
end

local function same (what, doc, doc_label, real, real_label, fix)
  local invented = absent(doc, real)
  local undocumented = absent(real, doc)
  if #invented == 0 and #undocumented == 0 then
    return
  end
  local lines = {}
  if #invented > 0 then
    lines[#lines + 1] = doc_label .. " names " .. table.concat(invented, ", ")
      .. ", absent from " .. real_label
  end
  if #undocumented > 0 then
    lines[#lines + 1] = real_label .. " has " .. table.concat(undocumented, ", ")
      .. ", unnamed by " .. doc_label
  end
  lines[#lines + 1] = fix
  fail(what, lines)
end

local function subset (what, sub, sub_label, super, why, fix)
  local extra = absent(sub, super)
  if #extra == 0 then
    return
  end
  fail(what, {
    sub_label .. " uses " .. table.concat(extra, ", ") .. "; " .. why,
    fix,
  })
end

local function names (src, pat)
  local out = {}
  for name in string.gmatch(src, pat) do
    out[name] = true
  end
  return out
end

local function brace_table (src, opener, where)
  local s = string.find(src, opener, 1, true)
  if not s then
    fail("snippet parse", { where .. ": no " .. opener .. " found" })
  end
  local i = s + #opener - 1
  local depth, j = 0, i
  while true do
    local c = string.sub(src, j, j)
    if c == "" then
      fail("snippet parse", { where .. ": unbalanced braces after " .. opener })
    elseif c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
    end
    j = j + 1
    if depth == 0 then
      break
    end
  end
  return string.sub(src, i + 1, j - 2)
end

local function table_keys (body, where)
  local src = string.gsub(body, "%.%.%.", "_")
  local stub = {}
  setmetatable(stub, {
    __index = function () return stub end,
    __call = function () return stub end,
  })
  local sandbox = setmetatable({}, { __index = function () return stub end })
  local chunk, cerr
  if setfenv then
    chunk, cerr = loadchunk("return {" .. src .. "\n}", where)
    if chunk then
      setfenv(chunk, sandbox)
    end
  else
    chunk, cerr = loadchunk("return {" .. src .. "\n}", where, "t", sandbox)
  end
  if not chunk then
    fail("snippet parse", { where .. ": " .. tostring(cerr) })
  end
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then
    fail("snippet parse", { where .. ": " .. tostring(t) })
  end
  local out = {}
  for k in pairs(t) do
    if type(k) == "string" then
      out[k] = true
    end
  end
  return out
end

local function module_source (path, mod)
  local fp = env.searchpath(mod, path)
  if not fp then
    fail("source lookup", {
      "cannot resolve " .. mod,
      "searched " .. path,
      "these checks read installed rocks, so the rock tree must exist first",
    })
  end
  return fs.readfile(fp)
end

local function split_template (src, where)
  local tpl = string.match(src, "mustache%(%[%[(.*)%]%]%)")
  if not tpl then
    fail("source parse", { where .. ": no mustache([[ ... ]]) template" })
  end
  return tpl, (string.gsub(src, "mustache%(%[%[.*%]%]%)", "", 1))
end

local function slots (tpl)
  return names(tpl, "{{[#^/{&]?%s*([%a_][%w_]*)")
end

local function example (tab, tab_name, title)
  for _, ex in ipairs(tab.examples) do
    if ex.title == title then
      return ex
    end
  end
  fail("tab structure", {
    "tabs/" .. tab_name .. ".lua has no example titled " .. string.format("%q", title),
    "these checks key off titles; rename them here when you rename a section",
  })
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
  local tabs = {}
  local err
  for _, name in ipairs({ "start_lib", "start_web", "start_server", "web", "socket" }) do
    local ok, tab = pcall(require, "docs.tabs." .. name)
    if not ok then
      err = err or ("docs.tabs." .. name .. ": " .. tostring(tab))
    else
      tabs[name] = tab
    end
  end
  local ok, scaffold = pcall(require, "docs.scaffold")
  if not ok then
    err = err or ("docs.scaffold: " .. tostring(scaffold))
  end
  package.path = saved
  if err then
    fail("tab load", { err })
  end
  return tabs, scaffold
end

local function check_scaffold_listing (tab, tab_name, title, group, command)
  local code = example(tab, tab_name, title).code
  local esc = string.gsub(group.name, "(%W)", "%%%1")
  local doc = {}
  for line in string.gmatch(code, "[^\n]+") do
    if string.match(line, "^" .. esc .. "/") then
      doc[line] = true
    end
  end
  local real = {}
  for _, rel in ipairs(group.all) do
    real[group.name .. "/" .. rel] = true
  end
  same(command .. " file listing",
    doc, "the find output in tabs/" .. tab_name .. ".lua",
    real, "the tree " .. command .. " actually produces",
    "fix the listing, and the file count named in the tab intro")
end

local function check_index_options (tabs, lua_path)
  local src = module_source(lua_path, "santoku.web.pwa.index")
  local tpl, rest = split_template(src, "santoku.web.pwa.index")
  local real = slots(tpl)
  for k in pairs(names(rest, "opts%.([%a_][%w_]*)")) do
    real[k] = true
  end
  local where = "tabs/web.lua index({...})"
  local doc = table_keys(brace_table(
    example(tabs.web, "web", "santoku.web.pwa.index: the document generator").code,
    "index({", where), where)
  same("santoku.web.pwa.index options",
    doc, "the index snippet in tabs/web.lua",
    real, "the installed santoku.web.pwa.index",
    "the option table claims to list every real slot, so add or drop the key there")
  local prod_where = "tabs/start_web.lua index({...})"
  local prod = table_keys(brace_table(
    example(tabs.start_web, "start_web",
      "Going to production: the document and manifest").code,
    "index({", prod_where), prod_where)
  subset("santoku.web.pwa.index options",
    prod, "the production index snippet in tabs/start_web.lua",
    real, "the installed santoku.web.pwa.index has no such slot",
    "drop the key, or add it to santoku-web and release it")
end

local function check_sw_options (tabs, lua_path)
  local src = module_source(lua_path, "santoku.web.pwa.sw")
  local _, rest = split_template(src, "santoku.web.pwa.sw")
  local real = names(rest, "opts%.([%a_][%w_]*)")
  local where = "tabs/web.lua sw({...})"
  local doc = table_keys(brace_table(
    example(tabs.web, "web", "santoku.web.pwa.sw: generating the service worker").code,
    "sw({", where), where)
  same("santoku.web.pwa.sw options",
    doc, "the sw snippet in tabs/web.lua",
    real, "the installed santoku.web.pwa.sw",
    "the tab says the surface is exactly these keys, so keep both sides in step")
  local prod_where = "tabs/start_web.lua sw({...})"
  local prod = table_keys(brace_table(
    example(tabs.start_web, "start_web",
      "Going to production: the service worker").code,
    "sw({", prod_where), prod_where)
  subset("santoku.web.pwa.sw options",
    prod, "the production sw snippet in tabs/start_web.lua",
    real, "the installed santoku.web.pwa.sw ignores it silently",
    "drop the key, or add it to santoku-web and release it")
end

local function check_manifest_options (tabs, lua_path)
  local src = module_source(lua_path, "santoku.web.pwa.manifest")
  local tpl, rest = split_template(src, "santoku.web.pwa.manifest")
  local real = slots((string.gsub(tpl, "{{#icons}}.*{{/icons}}", "")))
  real.icons = true
  local dwhere = "santoku.web.pwa.manifest defaults"
  local defaults = table_keys(brace_table(rest, "defaults = {", dwhere), dwhere)
  for k in pairs(names(rest, "%.([%a_][%w_]*)%s*=[^=]")) do
    if not defaults[k] then
      real[k] = nil
    end
  end
  local where = "tabs/web.lua manifest({...})"
  local doc = table_keys(brace_table(
    example(tabs.web, "web", "santoku.web.pwa.manifest: the web app manifest").code,
    "manifest({", where), where)
  same("santoku.web.pwa.manifest options",
    doc, "the manifest snippet in tabs/web.lua",
    real, "the installed santoku.web.pwa.manifest",
    "the option table claims to list every real slot, so add or drop the key there")
end

local function check_nginx_context (tabs)
  local code = example(tabs.start_web, "start_web", "Going to production: TLS").code
  local where = "tabs/start_web.lua nginx = {...}"
  local provided = table_keys(brace_table(code, "nginx = {", where), where)
  for k in pairs(names(code, "nginx_cfg%.([%a_][%w_]*)")) do
    provided[k] = true
  end
  local wsrc = module_source(package.path, "santoku.make.project.web")
  local iwhere = "santoku.make.project.web compute_nginx_context"
  for k in pairs(table_keys(brace_table(
    wsrc, "nginx = tbl.merge({}, nginx_cfg, {", iwhere), iwhere))
  do
    provided[k] = true
  end
  subset("the nginx template variables in the production TLS snippet",
    names(code, "%f[%w]n%.([%a_][%w_]*)"), "the snippet",
    provided,
    "the snippet's own nginx table does not declare it, its configure hook does "
      .. "not set it, and santoku-make does not inject it, so it renders as nil",
    "declare the key in the snippet's nginx block, or stop referencing it")
end

local function check_socket_surface (tabs, lua_path)
  local real = names(module_source(lua_path, "santoku.http"),
    "backend%.([%a_][%w_]*)")
  local doc = {}
  for _, ex in ipairs(tabs.socket.examples) do
    for k in pairs(names(ex.code, "%f[%w]socket%.([%a_][%w_]*)")) do
      doc[k] = true
    end
  end
  same("the santoku-socket surface",
    doc, "the santoku.socket calls in tabs/socket.lua",
    real, "the backend contract santoku.http calls",
    "the tab says the module is exactly these three functions and that they are "
      .. "exactly the santoku-http backend contract; both claims fail if these differ")
end

local function check_setup_pins (root_dir)
  local fp = fs.join(root_dir, "res/setup-toku.sh")
  local src = fs.readfile(fp)
  local lua_v = string.match(src, "\nLUA_VERSION=(%S+)") or string.match(src, "^LUA_VERSION=(%S+)")
  local lr_v = string.match(src, "\nLUAROCKS_VERSION=(%S+)")
  local ok, cli = pcall(require, "santoku.cli.setup")
  if not ok then
    fail("setup-toku.sh pins", {
      "cannot require santoku.cli.setup: " .. tostring(cli),
      "this check compares the script's pinned versions against the santoku-cli running the build",
    })
  end
  if lua_v ~= cli.pins.lua.version or lr_v ~= cli.pins.luarocks.version then
    fail("setup-toku.sh pins", {
      "res/setup-toku.sh pins lua " .. tostring(lua_v) .. " and luarocks " .. tostring(lr_v),
      "the santoku-cli running this build pins lua " .. cli.pins.lua.version
        .. " and luarocks " .. cli.pins.luarocks.version,
      "the served script must provision exactly what toku expects, so align the pins "
        .. "in res/setup-toku.sh and lib/santoku/cli/setup.lua and release both",
    })
  end
end

return function (opts)
  check_setup_pins(opts.root_dir)
  local tabs, scaffold = load_docs(opts.root_dir, opts.gen_dir)
  check_scaffold_listing(tabs.start_lib, "start_lib",
    "Scaffold a library project", scaffold.lib, "toku init")
  check_scaffold_listing(tabs.start_web, "start_web",
    "Scaffold a web project", scaffold.web, "toku init --web")
  check_index_options(tabs, opts.lua_path)
  check_sw_options(tabs, opts.lua_path)
  check_manifest_options(tabs, opts.lua_path)
  check_nginx_context(tabs)
  check_socket_surface(tabs, opts.lua_path)
end

local test = require("santoku.test")
local fs = require("santoku.fs")
local env = require("santoku.env")
local str = require("santoku.string")
local arr = require("santoku.array")
local lua = require("santoku.lua")
local project = require("santoku.make.project")

local function fail (what, lines)
  local out = { "docs claim check failed: " .. what }
  for i = 1, #lines do
    out[#out + 1] = "  " .. lines[i]
  end
  error(arr.concat(out, "\n"), 0)
end

local function sorted (set)
  local out = {}
  for k in pairs(set) do
    out[#out + 1] = k
  end
  arr.sort(out)
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
    lines[#lines + 1] = doc_label .. " names " .. arr.concat(invented, ", ")
      .. ", absent from " .. real_label
  end
  if #undocumented > 0 then
    lines[#lines + 1] = real_label .. " has " .. arr.concat(undocumented, ", ")
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
    sub_label .. " uses " .. arr.concat(extra, ", ") .. "; " .. why,
    fix,
  })
end

local function names (src, pat)
  local out = {}
  for name in str.gmatch(src, pat) do
    out[name] = true
  end
  return out
end

local function brace_table (src, opener, where)
  local s = str.find(src, opener, 1, true)
  if not s then
    fail("snippet parse", { where .. ": no " .. opener .. " found" })
  end
  local i = s + #opener - 1
  local depth, j = 0, i
  while true do
    local c = str.sub(src, j, j)
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
  return str.sub(src, i + 1, j - 2)
end

local function table_keys (body, where)
  local src = str.gsub(body, "%.%.%.", "_")
  local stub = {}
  setmetatable(stub, {
    __index = function () return stub end,
    __call = function () return stub end,
  })
  local sandbox = setmetatable({}, { __index = function () return stub end })
  local ok, chunk = pcall(lua.loadstring, "return {" .. src .. "\n}", sandbox)
  if not ok then
    fail("snippet parse", { where .. ": " .. tostring(chunk) })
  end
  local t
  ok, t = pcall(chunk)
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

local function module_source (mod)
  local fp = env.searchpath(mod, package.path)
  if not fp then
    fail("source lookup", {
      "cannot resolve " .. mod,
      "searched " .. package.path,
      "these checks read installed rocks declared as server test dependencies",
    })
  end
  return fs.readfile(fp)
end

local function split_template (src, where)
  local tpl = str.match(src, "mustache%(%[%[(.*)%]%]%)")
  if not tpl then
    fail("source parse", { where .. ": no mustache([[ ... ]]) template" })
  end
  return tpl, (str.gsub(src, "mustache%(%[%[.*%]%]%)", "", 1))
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
    "tabs/" .. tab_name .. ".lua has no example titled " .. str.format("%q", title),
    "these checks key off titles; rename them here when you rename a section",
  })
end

local scaffold_meta = fs.runfile("res/docs/scaffold_specs.lua")

local scaffold = scaffold_meta.build(project.snapshot, function (key)
  return "docs-claims-scaffold-" .. key
end)

local req = fs.runfile("res/docs/load.lua")({
  readfile = fs.readfile,
  root_dir = ".",
  preload = {
    ["docs.scaffold"] = scaffold,
    ["docs.setup_script"] = { lang = "bash", code = fs.readfile("res/setup-toku.sh") },
  },
})

local content = req("docs.content")
local tabs = {
  start_lib = req("docs.tabs.start_lib"),
  start_web = req("docs.tabs.start_web"),
  start_server = req("docs.tabs.start_server"),
  web = req("docs.tabs.web"),
  socket = req("docs.tabs.socket"),
  sqlite_sync = req("docs.tabs.sqlite_sync"),
}

local function check_scaffold_listing (tab, tab_name, title, group, command)
  local code = example(tab, tab_name, title).code
  local esc = str.gsub(group.name, "(%W)", "%%%1")
  local doc = {}
  for line in str.gmatch(code, "[^\n]+") do
    if str.match(line, "^" .. esc .. "/") then
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

test("setup-toku.sh pins match the santoku-cli setup pins", function ()
  local src = fs.readfile("res/setup-toku.sh")
  local lua_v = str.match(src, "\nLUA_VERSION=(%S+)") or str.match(src, "^LUA_VERSION=(%S+)")
  local lr_v = str.match(src, "\nLUAROCKS_VERSION=(%S+)")
  local cli = require("santoku.cli.setup")
  if lua_v ~= cli.pins.lua.version or lr_v ~= cli.pins.luarocks.version then
    fail("setup-toku.sh pins", {
      "res/setup-toku.sh pins lua " .. tostring(lua_v) .. " and luarocks " .. tostring(lr_v),
      "the installed santoku-cli pins lua " .. cli.pins.lua.version
        .. " and luarocks " .. cli.pins.luarocks.version,
      "the served script must provision exactly what toku expects, so align the pins "
        .. "in res/setup-toku.sh and lib/santoku/cli/setup.lua and release both",
    })
  end
end)

test("scaffold listings match toku init output", function ()
  check_scaffold_listing(tabs.start_lib, "start_lib",
    "Scaffold a library project", scaffold.lib, "toku init")
  check_scaffold_listing(tabs.start_web, "start_web",
    "Scaffold a web project", scaffold.web, "toku init --web")
  check_scaffold_listing(tabs.start_server, "start_server",
    "Scaffold an API project", scaffold.api, "toku init --api")
end)

test("documented santoku.web.pwa.index options match the installed module", function ()
  local src = module_source("santoku.web.pwa.index")
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
end)

test("documented santoku.web.pwa.sw options match the installed module", function ()
  local src = module_source("santoku.web.pwa.sw")
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
end)

test("documented santoku.web.pwa.manifest options match the installed module", function ()
  local src = module_source("santoku.web.pwa.manifest")
  local tpl, rest = split_template(src, "santoku.web.pwa.manifest")
  local real = slots((str.gsub(tpl, "{{#icons}}.*{{/icons}}", "")))
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
end)

test("the production TLS snippet declares every nginx template variable it uses", function ()
  local code = example(tabs.start_web, "start_web", "Going to production: TLS").code
  local where = "tabs/start_web.lua nginx = {...}"
  local provided = table_keys(brace_table(code, "nginx = {", where), where)
  for k in pairs(names(code, "nginx_cfg%.([%a_][%w_]*)")) do
    provided[k] = true
  end
  local wsrc = module_source("santoku.make.project.web")
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
end)

test("the documented santoku-socket surface matches the santoku-http backend contract", function ()
  local real = names(module_source("santoku.http"),
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
end)

test("the documented santoku.sqlite.sync surface exists on the installed module", function ()
  local src = module_source("santoku.sqlite.sync")
  local positions = {}
  local pos = 1
  while true do
    local s = str.find(src, "return {", pos, true)
    if not s then
      break
    end
    positions[#positions + 1] = s
    pos = s + 1
  end
  if #positions < 2 then
    fail("source parse", { "santoku.sqlite.sync: expected handle and module return tables" })
  end
  local real = {}
  for _, p in ipairs({ positions[#positions - 1], positions[#positions] }) do
    local body = brace_table(str.sub(src, p), "return {", "santoku.sqlite.sync")
    for k in pairs(table_keys(body, "santoku.sqlite.sync")) do
      real[k] = true
    end
  end
  local doc = {}
  for _, ex in ipairs(tabs.sqlite_sync.examples) do
    for k in pairs(names(ex.code, "%f[%w]sync%.([%a_][%w_]*)%s*%(")) do
      doc[k] = true
    end
  end
  subset("the santoku.sqlite.sync surface",
    doc, "the sync calls in tabs/sqlite_sync.lua",
    real, "the installed santoku.sqlite.sync exposes no such function",
    "fix the call in the tab, or add the function to santoku-sqlite and release it")
end)

test("client.bundle_mods matches what runnable examples require", function ()
  local mods = {}
  for _, m in ipairs(fs.runfile("res/docs/bundle_mods.lua")) do
    mods[m] = true
  end
  local used = {}
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      for _, ex in ipairs(tab.content.examples) do
        if ex.runnable ~= false then
          for m in pairs(names(ex.code, "require%s*%(?%s*\"([^\"]+)\"")) do
            used[m] = true
          end
          for m in pairs(names(ex.code, "require%s*%(?%s*'([^']+)'")) do
            used[m] = true
          end
        end
      end
    end
  end
  same("client.bundle_mods",
    used, "the require calls in runnable examples",
    mods, "client.bundle_mods in make.common.lua",
    "the bundler only follows static require literals from the client entry, so every "
      .. "module a Run button pulls in at runtime must be listed explicitly, and "
      .. "anything listed beyond that ships dead weight in the wasm")
end)

test("example dependency constraints admit the installed rock versions", function ()
  local rocks_dir
  for entry in str.gmatch(package.path, "[^;]+") do
    local prefix = str.match(entry, "^(.*)/share/lua/5%.1/%?%.lua$")
    if prefix and fs.exists(fs.join(prefix, "lib/luarocks/rocks-5.1")) then
      rocks_dir = fs.join(prefix, "lib/luarocks/rocks-5.1")
      break
    end
  end
  if not rocks_dir then
    fail("rock tree lookup", { "no luarocks tree on package.path" })
  end
  local function installed_version (rock)
    local dir = fs.join(rocks_dir, rock)
    if not fs.exists(dir) then
      return nil
    end
    for name in fs.dir(dir) do
      local a, b, c = str.match(name, "^(%d+)%.(%d+)%.(%d+)%-%d+$")
      if a then
        return tonumber(a), tonumber(b), tonumber(c)
      end
    end
  end
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      for j = 1, #tab.content.examples do
        local code = tab.content.examples[j].code
        for rock, mi1, mi2, mi3, mx in str.gmatch(code,
          "\"(santoku[%w%-]*) >= (%d+)%.(%d+)%.(%d+), < (%d+)%.")
        do
          local a, b, c = installed_version(rock)
          if a then
            local minv = { tonumber(mi1), tonumber(mi2), tonumber(mi3) }
            local have = { a, b, c }
            local ge = true
            for k = 1, 3 do
              if have[k] > minv[k] then
                break
              elseif have[k] < minv[k] then
                ge = false
                break
              end
            end
            if not ge or a >= tonumber(mx) then
              fail("example dependency constraint", {
                tab.id .. " example " .. j .. " pins " .. rock .. " >= "
                  .. mi1 .. "." .. mi2 .. "." .. mi3 .. ", < " .. mx .. ".0.0",
                "but the installed " .. rock .. " is " .. a .. "." .. b .. "." .. c,
                "update the constraint in the example descriptor to the current major",
              })
            end
          end
        end
      end
    end
  end
end)

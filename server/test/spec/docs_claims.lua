local test = require("santoku.test")
local fs = require("santoku.fs")
local str = require("santoku.string")
local arr = require("santoku.array")
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

local function names (src, pat)
  local out = {}
  for name in str.gmatch(src, pat) do
    out[name] = true
  end
  return out
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
})

local content = req("docs.content")
local tabs = {
  start_lib = req("docs.tabs.start_lib"),
  start_web = req("docs.tabs.start_web"),
  start_server = req("docs.tabs.start_server"),
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

local langs = {
  lua = "lua", c = "c", h = "c", html = "markup", js = "javascript",
  css = "css", sql = "sql", conf = "nginx", json = "json",
}

local function lang (path)
  local ext = string.match(path, "%.([^.]+)$")
  return ext and langs[string.lower(ext)] or "text"
end

local specs = {
  {
    key = "lib",
    name = "my-lib",
    mod = "my_lib",
    files = {
      "make.lua",
      "lib/%m.tk.lua",
      "lib/%m/capi.c",
      "bin/%s.lua",
      "test/spec/%m.lua",
      "res/migrations/0.0.1.sql",
    },
  },
  {
    key = "web",
    name = "my-app",
    files = {
      "make.lua",
      "client/bin/bundle.lua",
      "client/lib/%s/main.lua",
      "client/lib/%s/db.tk.lua",
      "client/static/index.html",
      "client/res/pre.tk.js",
      "server/nginx.tk.conf",
      "server/lib/%s/web/init.lua",
      "server/lib/%s/web/sync.lua",
      "res/client/migrations/0.0.1.sql",
    },
  },
  {
    key = "api",
    name = "my-api",
    mod = "my_api",
    files = {
      "make.lua",
      "res/server/migrations/0.0.1.sql",
      "server/lib/%m/db.tk.lua",
      "server/lib/%m/web/init.lua",
      "server/lib/%m/web/init_worker.lua",
      "server/lib/%m/web/items.lua",
      "server/nginx.tk.conf",
      "server/test/spec/%m.lua",
    },
  },
}

local function build (snapshot, dir_for)
  local out = {}
  for _, spec in ipairs(specs) do
    local snap = snapshot(spec.key, {
      name = spec.name,
      dir = dir_for(spec.key),
    })
    local by_path = {}
    for i = 1, #snap.files do
      by_path[snap.files[i].path] = snap.files[i].code
    end
    local mod = spec.mod or spec.name
    local subs = { ["%s"] = spec.name, ["%m"] = mod }
    local files = {}
    for _, pattern in ipairs(spec.files) do
      local rel = string.gsub(pattern, "%%[sm]", subs)
      local code = by_path[rel]
      if not code then
        error("scaffold file missing from the " .. spec.key ..
          " boilerplate: " .. rel .. " (update res/docs/scaffold_specs.lua)")
      end
      files[#files + 1] = { path = rel, lang = lang(rel), code = code }
    end
    out[spec.key] = { name = spec.name, mod = mod, files = files, all = snap.all }
  end
  return out
end

return {
  specs = specs,
  lang = lang,
  build = build,
}

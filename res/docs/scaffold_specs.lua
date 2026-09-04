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
    create = "create_lib",
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
    create = "create_web",
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
    create = "create_api",
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

return {
  specs = specs,
  lang = lang,
}

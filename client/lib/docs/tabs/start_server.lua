return {

  intro = table.concat({
    "This page builds a JSON API with no frontend: an OpenResty server over a ",
    "server-side SQLite database in WAL mode, with one connection and one set of ",
    "prepared statements per nginx worker. It is the server half of the web page ",
    "beside this one, isolated, with the parts that page only mentions written ",
    "out: the init versus init_worker split, the pragma set, statement lifetime, ",
    "and testing the database module natively with no nginx involved. Everything ",
    "assumes toku is installed per the Install tab, plus openresty on PATH and ",
    "OPENRESTY_DIR set; a server-only project needs none of the client toolchain, ",
    "and toku doctor reports the project as server only and checks exactly that. ",
    "Every file below is complete and named, so it can be written verbatim. The ",
    "example project is called my-api.",
  }),

  examples = {

    {
      title = "No server-only scaffold yet: the subtractive recipe",
      desc = table.concat({
        "There is no server-only toku init today; --web is the only project flag. ",
        "So scaffold a web project and cut it down. Delete the client directory and ",
        "the client migrations, then replace the scaffolded server files with the ",
        "ones on this page: the descriptor loses its client table and its build ",
        "table, whose only entry is the santoku-web build dependency the deleted ",
        "client template needed, and the scaffold's own server files are replaced ",
        "because they open the database in init_by_lua, a shape that only survives ",
        "there because the scaffold pins worker_processes to 1. The next section ",
        "explains why that shape breaks with more workers.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku init --web --name my-api
$ cd my-api
$ rm -rf client res/client server/lib/my-api/web/sync.lua

# then write the files from this page:
#   make.lua                             replaces the scaffolded descriptor
#   server/nginx.tk.conf                 replaces the scaffolded config
#   server/lib/my-api/db.tk.lua          replaces the scaffolded db module
#   server/lib/my-api/web/init.lua       replaces the scaffolded init
#   server/lib/my-api/web/init_worker.lua  new
#   server/lib/my-api/web/items.lua      new
#   res/server/migrations/0.0.1.sql      replaces the scaffolded migration
#   server/test/spec/my-api.lua          replaces the scaffolded spec

$ find . -type f -not -path "./.git/*" | sort
./.gitignore
./LICENSE
./make.lua
./res/server/migrations/0.0.1.sql
./server/lib/my-api/db.tk.lua
./server/lib/my-api/web/init.lua
./server/lib/my-api/web/init_worker.lua
./server/lib/my-api/web/items.lua
./server/nginx.tk.conf
./server/test/spec/my-api.lua
]],
    },

    {
      title = "make.lua: the whole descriptor",
      desc = table.concat({
        "The server-only descriptor keeps the server and nginx blocks and nothing ",
        "else. server.dependencies resolve into the server's private rock tree as ",
        "native rocks built against OpenResty's luajit; luasocket under test is for the ",
        "spec's HTTP half. The nginx block is read by the config template, and ",
        "modules lists every Lua file nginx loads by name; a module missing from ",
        "this list has no path for the template to reference. cjson is not listed ",
        "because OpenResty bundles it. workers defaults to auto here, which is the ",
        "point: the files below are correct at any worker count.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- make.lua
local env = require("santoku.env")

return {
  env = {

    name = "my-api",
    version = "0.0.1-1",
    license = "MIT",

    dependencies = {
      "lua == 5.1",
    },

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 2.0.0, < 3.0.0",
        "santoku-sqlite >= 3.0.1, < 4.0.0",
        "santoku-sqlite-migrate >= 2.0.0, < 3.0.0",
      },
      test = {
        dependencies = {
          "luasocket >= 3.0",
        },
      },
    },

    nginx = {
      domain = env.var("DOMAIN", "localhost"),
      port = "8080",
      workers = env.var("WORKERS", "auto"),
      modules = {
        "my-api.web.init",
        "my-api.web.init_worker",
        "my-api.web.items",
      },
    },

  },
}
]],
    },

    {
      title = "res/server/migrations/0.0.1.sql: the schema",
      desc = table.concat({
        "Migrations are santoku-sqlite-migrate files named by version, applied in ",
        "version order, forward-only, each exactly once, in a single transaction. ",
        "They are embedded into the database module at BUILD time through the ",
        "template preamble in the next section, not read from disk at runtime. ",
        "That choice is what makes the module self-contained: nginx runs it with ",
        "the server work directory as cwd and the spec runs it from the test tree, ",
        "and neither needs a migrations path to exist. Add 0.0.2.sql beside this ",
        "one and it is embedded and applied on the next build.",
      }),
      runnable = false,
      lang = "sql",
      code = [[
create table items (
  id integer primary key,
  name text not null,
  created_at real not null default (unixepoch('now', 'subsec'))
);
]],
    },

    {
      title = "server/lib/my-api/db.tk.lua: connection, pragmas, statements",
      desc = table.concat({
        "One module owns the connection, the pragmas, and every prepared ",
        "statement. The pragma order is deliberate: busy_timeout first, so every ",
        "later statement, including the WAL switch itself, waits up to 30s on a ",
        "locked database instead of failing with SQLITE_BUSY. Without it, a write ",
        "transaction in this worker fails the moment a writer in another worker ",
        "holds the lock; with it, concurrent writers queue. journal_mode = WAL is ",
        "persistent, stored in the database file, but the pragma is idempotent so ",
        "it stays in the block every opener runs. busy_timeout, synchronous and ",
        "foreign_keys are per connection and must be reapplied on every open, ",
        "which is why they live here and nowhere else. foreign_keys defaults off ",
        "in SQLite; the shipped scaffolds do not set it, this page does. ",
        "db.getter, db.inserter, db.runner and db.all prepare their SQL once, when ",
        "called, and return closures over the statement, so a statement lives ",
        "exactly as long as the module instance that built it. Build them all ",
        "here, at module construction: a handler file runs per request, so a ",
        "prepare there is a prepare per request.",
      }),
      runnable = false,
      lang = "lua",
      code = [=[
<%
  local fs = require("santoku.fs")
  local serialize = require("santoku.serialize")
  local migrations = {}
  for fp in fs.files("res/server/migrations") do
    migrations[fs.basename(fp)] = readfile(fp)
  end
  t_migrations = serialize(migrations, true)
%>

local err = require("santoku.error")
local db_mod = require("santoku.sqlite.db")
local sqlite = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")

return function (db_file, opts)

  opts = opts or {}
  local M = {}
  local db = sqlite(err.assert(db_mod.open(db_file)))

  db.exec("pragma busy_timeout = 30000")
  db.exec("pragma journal_mode = WAL")
  db.exec("pragma synchronous = NORMAL")
  db.exec("pragma foreign_keys = on")

  if not opts.no_migrate then
    migrate(db, <% return t_migrations %>) -- luacheck: ignore
  end

  M.db = db

  local create_item = db.inserter([[
    insert into items (name) values (?1)
  ]])

  M.create_item = function (name)
    return create_item(name)
  end

  local list_items = db.getter([[
    select json_object('items', coalesce((
      select json_group_array(json_object(
        'id', id,
        'name', name,
        'created_at', created_at))
      from (select id, name, created_at from items order by id desc limit ?1)
    ), json_array()))
  ]])

  M.list_items = function (limit)
    return list_items(limit or 50)
  end

  return M

end
]=],
    },

    {
      title = "server/lib/my-api/web/init.lua: migrate in the master, then close",
      desc = table.concat({
        "init_by_lua_file runs once in the nginx MASTER, before workers fork. ",
        "init_worker_by_lua_file runs once in EACH worker, after the fork. The ",
        "split matters because a SQLite connection must never cross a fork: every ",
        "worker would inherit one shared handle, shared file descriptors, shared ",
        "lock state, and one shared seeded PRNG. ",
        "With the connection opened in init_by_lua, two workers can issue ",
        "the SAME random nonce from the shared PRNG state, surfacing as ",
        "UNIQUE-constraint 500s under concurrent load; the fix is moving the ",
        "connection, the migrations and every prepared statement post-fork. ",
        "So the master opens the database only to run migrations, and closes it ",
        "before the fork. It passes the path forward, never the handle.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local env = require("santoku.env")
local db_file = env.var("DB_FILE", "my-api.db")
local migrator = require("my-api.db")(db_file)
migrator.db.close()
package.loaded["my-api.config"] = { db_file = db_file }
]],
    },

    {
      title = "server/lib/my-api/web/init_worker.lua: one connection per worker",
      desc = table.concat({
        "This is a SEPARATE file from init.lua above; nginx.tk.conf names both. ",
        "Each worker opens its own connection with no_migrate, since the master ",
        "already migrated, and gets its own handle and its own prepared ",
        "statements. Handlers reach the worker's instance through package.loaded, ",
        "the standard OpenResty way to share an initialized resource across ",
        "requests without reopening it per request.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local config = require("my-api.config")
package.loaded["my-api.db.loaded"] =
  require("my-api.db")(config.db_file, { no_migrate = true })
]],
    },

    {
      title = "server/nginx.tk.conf: the whole config",
      desc = table.concat({
        "A real nginx configuration with template holes, rendered at build time. ",
        "The names inside <% %> are injected by the build: the descriptor's nginx ",
        "table as nginx.nginx, openresty_dir, lua_package_path and ",
        "lua_package_cpath pointing at the server's private rock tree, and modules ",
        "mapping each name from the descriptor's modules list to the file nginx ",
        "should load. Each endpoint is a location with limit_except for the ",
        "allowed methods and content_by_lua_file naming the handler. With ",
        "lua_code_cache on, the default, the handler chunk compiles once per ",
        "worker and executes per request.",
      }),
      runnable = false,
      lang = "text",
      code = [[
<% n = nginx.nginx %>
daemon <% return n.daemon %>;
pid <% return n.pid %>;
worker_processes <% return n.workers %>;
error_log <% return n.error_log %> info;

events {}

http {

  include <% return openresty_dir %>/nginx/conf/mime.types;

  access_log <% return n.access_log %>;

  client_max_body_size 1m;
  client_body_buffer_size 1m;

  lua_package_path "<% return lua_package_path %>";
  lua_package_cpath "<% return lua_package_cpath %>";

  init_by_lua_file <% return modules["my-api.web.init"] %>;
  init_worker_by_lua_file <% return modules["my-api.web.init_worker"] %>;

  server {

    listen <% return n.port %>;
    server_name <% return n.domain %>;

    location = /items {
      limit_except GET POST { deny all; }
      content_by_lua_file <% return modules["my-api.web.items"] %>;
    }

  }
}
]],
    },

    {
      title = "server/lib/my-api/web/items.lua: the handler",
      desc = table.concat({
        "The file /items routes to, run per request in whichever worker took the ",
        "connection. The query string arrives through ngx.req.get_uri_args(). The ",
        "body takes two calls: ngx.req.read_body() first, then ",
        "ngx.req.get_body_data(), which is nil if read_body was skipped or the ",
        "body spilled to a temp file above client_body_buffer_size, which is why ",
        "the config sets it equal to client_max_body_size. Headers, when you need ",
        "them, are ngx.req.get_headers() or ngx.var.http_x_foo for one header. ",
        "The list response is built as JSON inside SQLite rather than encoded ",
        "from a Lua table, because cjson encodes an empty Lua table as {} where ",
        "an empty list must be [], and json_group_array gets that right. cjson ",
        "still decodes the POST body, and its decode failure is caught with pcall ",
        "and turned into a 400.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local db = require("my-api.db.loaded")
local json = require("cjson")

local method = ngx.req.get_method()

if method ~= "POST" then
  local args = ngx.req.get_uri_args()
  ngx.header.content_type = "application/json"
  ngx.say(db.list_items(tonumber(args.limit)))
  return
end

ngx.req.read_body()
local body = ngx.req.get_body_data()
local ok, req = pcall(json.decode, body or "")
if not ok or type(req) ~= "table"
  or type(req.name) ~= "string" or #req.name == 0 or #req.name > 200 then
  ngx.status = 400
  ngx.header.content_type = "application/json"
  ngx.say(json.encode({ error = "bad_body" }))
  return ngx.exit(400)
end

ngx.header.content_type = "application/json"
ngx.say(json.encode({ id = db.create_item(req.name) }))
]],
    },

    {
      title = "server/test/spec/my-api.lua: specs with and without the server",
      desc = table.concat({
        "Server specs do not run inside nginx. toku test runs them under a ",
        "standalone interpreter, OpenResty's own luajit when OPENRESTY_DIR has ",
        "one and the system lua otherwise, with the module path pointed at the ",
        "rendered, installed server tree. By then db.tk.lua is plain Lua with the ",
        "migrations embedded and no ngx anywhere, so the first test constructs ",
        "the real database module against :memory: and exercises schema, ",
        "migrations and statements directly, no server running, no files on ",
        "disk. This is the fast loop for everything below the HTTP surface. The ",
        "second test covers the surface itself: toku test starts a real test ",
        "server before the specs run and stops it after, so plain luasocket ",
        "requests against localhost hit actual nginx, actual routing, and the ",
        "actual per-worker database. ",
        "The port has one source: the descriptor's nginx block. nginx.tk.conf ",
        "renders it at build time, and toku test hands the same value to server ",
        "specs as the PORT environment variable, so the spec reads env.var(...) ",
        "with no default and cannot drift from what nginx bound. To change the ",
        "port, edit make.lua; the descriptor is a tracked dependency, so the ",
        "next build re-renders everything that uses it.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local test = require("santoku.test")
local err = require("santoku.error")

test("db module, no server", function ()
  local db = require("my-api.db")(":memory:")
  local id = db.create_item("first")
  err.assert(id == 1, "expected rowid 1, got " .. tostring(id))
  local out = db.list_items(10)
  err.assert(string.find(out, "\"first\"", 1, true), "created row listed")
end)

test("items endpoint", function ()
  local http = require("socket.http")
  local ltn12 = require("ltn12")
  local env = require("santoku.env")
  local port = env.var("PORT")
  local url = "http://localhost:" .. port .. "/items"
  local body = "{\"name\":\"from the spec\"}"
  local chunks = {}
  local ok, code = http.request({
    url = url,
    method = "POST",
    headers = {
      ["content-type"] = "application/json",
      ["content-length"] = tostring(#body),
    },
    source = ltn12.source.string(body),
    sink = ltn12.sink.table(chunks),
  })
  err.assert(ok, "no response on port " .. port .. " (" .. tostring(code) .. ")")
  err.assert(code == 200, "expected 200, got " .. tostring(code))
  err.assert(string.find(table.concat(chunks), "\"id\""), "response carries id")
  chunks = {}
  ok, code = http.request({ url = url, sink = ltn12.sink.table(chunks) })
  err.assert(ok and code == 200, "list failed: " .. tostring(code))
  err.assert(string.find(table.concat(chunks), "from the spec", 1, true),
    "posted row listed")
end)
]],
    },

    {
      title = "How you know it worked",
      desc = table.concat({
        "Run these against the finished project and compare output. The build ",
        "renders the templates and installs the server tree; start runs OpenResty ",
        "against it. The first curl creates a row and returns its id; the second ",
        "lists it back, with created_at carrying whatever timestamp SQLite ",
        "assigned; the third proves validation rejects a bad body with a 400. ",
        "toku test builds, starts the test server, runs both specs above, and ",
        "stops it; --server skips the client and root suites, which for this ",
        "project do not exist anyway. If any step differs, the nginx error log ",
        "under the build tree is where the failure is written.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku build --test
$ toku start --test

$ curl -s -X POST http://localhost:8080/items \
    -H 'content-type: application/json' -d '{"name":"first"}'
{"id":1}

$ curl -s http://localhost:8080/items
{"items":[{"id":1,"name":"first","created_at":1756772183.412}]}

$ curl -si -X POST http://localhost:8080/items -d 'not json' | head -1
HTTP/1.1 400 Bad Request

$ toku stop
$ toku test --server

# to change the port, edit the descriptor's nginx block in make.lua and
# rebuild; nginx.conf re-renders because the descriptor is a tracked
# dependency, and the spec receives the same value automatically via PORT
]],
    },

  },

}

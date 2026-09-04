local file = require("docs.scaffold_file")

local function scaffolded (kind, path, title, desc)
  local f = file(kind, path)
  return {
    title = title,
    desc = desc,
    runnable = false,
    lang = f.lang,
    code = f.code,
  }
end

return {

  intro = table.concat({
    "This page builds a JSON API with no frontend: an OpenResty server over a ",
    "server-side SQLite database in WAL mode, with one connection and one set of ",
    "prepared statements per nginx worker. It is the server half of the web page ",
    "beside this one, isolated, with the parts that page only mentions written ",
    "out: the init versus init_worker split, the pragma set, statement lifetime, ",
    "and testing the database module natively with no nginx involved. Everything ",
    "assumes toku is installed per the Install tab, plus openresty on PATH and ",
    "OPENRESTY_DIR set (install it from openresty.org/en/installation.html; on ",
    "Debian and Ubuntu their apt repo, on Alpine the community package, then ",
    "export OPENRESTY_DIR=/usr/local/openresty), and git, which toku init runs. ",
    "A server-only project needs none of the client toolchain, ",
    "and toku doctor reports the project as server only and checks exactly that. ",
    "toku init --api scaffolds the whole project, and every file shown below is ",
    "reproduced straight from the boilerplate the CLI ships, so what you read is ",
    "exactly what you get. The example project is called my-api.",
  }),

  examples = {

    {
      title = "Scaffold an API project",
      desc = table.concat({
        "toku init --api creates a complete, already-working JSON API: the ",
        "descriptor, the nginx config, the database module, the init and ",
        "init_worker pair, one handler, one migration, and a spec that runs with ",
        "and without the server. It runs git init unless you pass git = false ",
        "through the API. The name must be lowercase letters, digits and hyphens, ",
        "starting with a letter. A hyphenated name splits in two, exactly as it ",
        "does for libraries: the rock keeps the hyphen while module directories ",
        "and requires use underscores, so my-api publishes as the rock my-api and ",
        "its modules load as my_api.db and my_api.web.init. Use --here to ",
        "scaffold into the current directory using its name.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku init --api --name my-api
Created API project: my-api

Next steps:
  cd my-api
  toku build --test  # Build for testing
  toku start --test  # Start development server

$ find my-api -type f -not -path "*/.git/*" | sort
my-api/.gitignore
my-api/LICENSE
my-api/make.lua
my-api/res/server/migrations/0.0.1.sql
my-api/server/lib/my_api/db.tk.lua
my-api/server/lib/my_api/web/init.lua
my-api/server/lib/my_api/web/init_worker.lua
my-api/server/lib/my_api/web/items.lua
my-api/server/nginx.tk.conf
my-api/server/test/spec/my_api.lua
]],
    },

    scaffolded("api", "make.lua",
      "make.lua: the whole descriptor",
      table.concat({
        "The server-only descriptor keeps the server and nginx blocks and nothing ",
        "else: no client table, no build table. server.dependencies resolve into ",
        "the server's private rock tree as native rocks built against OpenResty's ",
        "luajit; luasocket under test is for the spec's HTTP half. The nginx block ",
        "is read by the config template, and modules lists every Lua file nginx ",
        "loads by name; a module missing from this list has no path for the ",
        "template to reference. cjson is not listed because OpenResty bundles it. ",
        "The port is a literal: nginx.tk.conf renders it at build time and toku ",
        "test hands the same value to the spec, so one edit here moves both. ",
        "workers defaults to auto, which is the point: the files below are ",
        "correct at any worker count.",
      })),

    scaffolded("api", "res/server/migrations/0.0.1.sql",
      "res/server/migrations/0.0.1.sql: the schema",
      table.concat({
        "Migrations are santoku-sqlite-migrate files named by version, applied in ",
        "version order, forward-only, each exactly once, in a single transaction. ",
        "They are embedded into the database module at BUILD time through the ",
        "template preamble in the next section, not read from disk at runtime. ",
        "That choice is what makes the module self-contained: nginx runs it with ",
        "the server work directory as cwd and the spec runs it from the test tree, ",
        "and neither needs a migrations path to exist. Add 0.0.2.sql beside this ",
        "one and it is embedded and applied on the next build.",
      })),

    scaffolded("api", "server/lib/%m/db.tk.lua",
      "server/lib/my_api/db.tk.lua: connection, pragmas, statements",
      table.concat({
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
        "in SQLite; the web scaffold does not set it, this one turns it on ",
        "deliberately. ",
        "db.getter, db.inserter, db.runner and db.all prepare their SQL once, when ",
        "called, and return closures over the statement, so a statement lives ",
        "exactly as long as the module instance that built it. Build them all ",
        "here, at module construction: a handler file runs per request, so a ",
        "prepare there is a prepare per request.",
      })),

    scaffolded("api", "server/lib/%m/web/init.lua",
      "server/lib/my_api/web/init.lua: migrate in the master, then close",
      table.concat({
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
      })),

    scaffolded("api", "server/lib/%m/web/init_worker.lua",
      "server/lib/my_api/web/init_worker.lua: one connection per worker",
      table.concat({
        "This is a SEPARATE file from init.lua above; nginx.tk.conf names both. ",
        "Each worker opens its own connection with no_migrate, since the master ",
        "already migrated, and gets its own handle and its own prepared ",
        "statements. Handlers reach the worker's instance through package.loaded, ",
        "the standard OpenResty way to share an initialized resource across ",
        "requests without reopening it per request.",
      })),

    scaffolded("api", "server/nginx.tk.conf",
      "server/nginx.tk.conf: the whole config",
      table.concat({
        "A real nginx configuration with template holes, rendered at build time. ",
        "The names inside <% %> are injected by the build: the descriptor's nginx ",
        "table as nginx.nginx, openresty_dir, lua_package_path and ",
        "lua_package_cpath pointing at the server's private rock tree, and modules ",
        "mapping each name from the descriptor's modules list to the file nginx ",
        "should load. Each endpoint is a location with limit_except for the ",
        "allowed methods and content_by_lua_file naming the handler. With ",
        "lua_code_cache on, the default, the handler chunk compiles once per ",
        "worker and executes per request.",
      })),

    scaffolded("api", "server/lib/%m/web/items.lua",
      "server/lib/my_api/web/items.lua: the handler",
      table.concat({
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
      })),

    scaffolded("api", "server/test/spec/%m.lua",
      "server/test/spec/my_api.lua: specs with and without the server",
      table.concat({
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
      })),

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

$ curl -s -X POST http://127.0.0.1:8080/items \
    -H 'content-type: application/json' -d '{"name":"first"}'
{"id":1}

$ curl -s http://127.0.0.1:8080/items
{"items":[{"id":1,"name":"first","created_at":1756772183.412}]}

$ curl -si -X POST http://127.0.0.1:8080/items -d 'not json' | head -1
HTTP/1.1 400 Bad Request

$ toku stop

$ toku test --server
# runs the specs against a fresh test server it starts and stops itself.
# success looks like a luacheck summary with 0 errors after both spec
# halves have printed nothing: silence plus exit 0 is the pass state,
# and the access log under build/default/test/dist/logs shows the
# spec's POST and GET if you want proof the HTTP half really ran

# to change the port, edit the descriptor's nginx block in make.lua and
# rebuild; nginx.conf re-renders because the descriptor is a tracked
# dependency, and the spec receives the same value automatically via PORT
]],
    },

  },

}

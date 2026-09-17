return {

  intro = table.concat({
    "This page builds a JSON API with no frontend: an OpenResty server over a ",
    "server-side SQLite database in WAL mode, with one connection and one set of ",
    "prepared statements per nginx worker. It is the server half of the web page ",
    "beside this one, isolated. Everything ",
    "assumes toku is installed per the Install tab, plus openresty on PATH and ",
    "OPENRESTY_DIR set (install it from openresty.org/en/installation.html; on ",
    "Debian and Ubuntu their apt repo, on Alpine the community package, then ",
    "export OPENRESTY_DIR=/usr/local/openresty), and git, which toku init runs. ",
    "A server-only project needs none of the client toolchain, ",
    "and toku doctor reports the project as server only and checks exactly that. ",
    "toku init --api scaffolds the whole project. ",
    "The example project is called my-api.",
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

    {
      title = "The init and init_worker split",
      desc = table.concat({
        "init_by_lua runs once in the master process before nginx forks its ",
        "workers; init_worker_by_lua runs once inside each worker afterwards. The ",
        "scaffold uses that order deliberately. The master opens the database, ",
        "applies migrations, and closes immediately, because a SQLite connection ",
        "must not be carried across a fork. Each worker then opens its own ",
        "connection with no_migrate, since the schema is already current, and ",
        "prepares its own statements. Values cross between the three phases ",
        "through package.loaded: init publishes the resolved config, init_worker ",
        "publishes the open handle, and handlers require that handle rather than ",
        "constructing one. Requiring the db module directly from a handler instead ",
        "would open a fresh connection per handler module, which is the failure ",
        "this layout exists to prevent, and nothing reports it. The pragmas each ",
        "connection sets are covered on the santoku-sqlite-migrate page.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- server/lib/my_api/web/init.lua        (init_by_lua, master, once)
local env = require("santoku.env")
local db_file = env.var("DB_FILE", "my-api.db")
local migrator = require("my_api.db")(db_file)
migrator.db.close()
package.loaded["my_api.config"] = { db_file = db_file }

-- server/lib/my_api/web/init_worker.lua (init_worker_by_lua, per worker)
local config = require("my_api.config")
package.loaded["my_api.db.loaded"] =
  require("my_api.db")(config.db_file, { no_migrate = true })

-- server/lib/my_api/web/items.lua       (per request)
local db = require("my_api.db.loaded")
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

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
    "A santoku web project is one repository holding three programs: a client ",
    "compiled to WebAssembly and run in the browser, a server running under ",
    "OpenResty, and shared migrations both use. Everything here assumes toku is ",
    "installed and its mandatory one-time toku setup has run, which is the Install ",
    "tab: setup-toku.sh does both, and toku doctor confirms it. Beyond toku, decide ",
    "how you get the rest of the toolchain: install it on your machine, or run toku ",
    "from the container image santoku-make ships, with your code mounted in. Both ",
    "are covered first below, and ",
    "everything after that is identical either way. Then scaffold, build and start the ",
    "project before changing anything, and read it file by file. Every file shown is ",
    "the real output of toku init --web, reproduced straight from the boilerplate the ",
    "CLI ships, so it is exactly what you get. The example project is called my-app. ",
    "What it scaffolds is a working todo app with a client-side SQLite database, tag ",
    "parsing, JSON export and a real sync endpoint, in eighteen files.",
  }),

  examples = {

    {
      title = "Option one: install the toolchain",
      desc = table.concat({
        "A web project compiles Lua to WebAssembly and serves it from OpenResty, so ",
        "the toolchain is larger than for a library. The first line is the mandatory ",
        "one-time step; setup-toku.sh from the Install tab already ran it. The rest ",
        "must be on PATH before toku init --web is useful, except OPENRESTY_DIR, ",
        "which is an environment variable toku reads directly. Missing tools fail at ",
        "the first one the build cannot find, with the error coming from that tool ",
        "rather than from toku; a missing OPENRESTY_DIR fails from toku itself.",
      }),
      runnable = false,
      lang = "text",
      code = [[
toku setup        # mandatory, once; done by setup-toku.sh (the Install tab), or run
                  # toku setup --use-system to drive your own lua 5.1 toolchain
emcc, emmake      # Emscripten, compiles the client to WebAssembly. Install emsdk:
                  #   git clone https://github.com/emscripten-core/emsdk.git
                  #   cd emsdk && ./emsdk install latest && ./emsdk activate latest
                  #   source ./emsdk_env.sh
                  # emsdk needs python3 and xz-utils, and the first download is
                  # around 300MB
openresty         # the server runtime, from https://openresty.org/en/installation.html
                  # Alpine has it in community; Debian and Ubuntu use openresty.org's
                  # apt repo. You need it BOTH on PATH and named by OPENRESTY_DIR:
                  # toku start execs `openresty` from PATH, while the build reads
                  # OPENRESTY_DIR for luajit's headers and libraries.
OPENRESTY_DIR     # the install prefix, NOT the binary, and it is never inferred from
                  # PATH. Required unless you pass --openresty-dir or set
                  # openresty_dir in the descriptor. A distro package installs to
                  # /usr/local/openresty, so:
                  #   export OPENRESTY_DIR=/usr/local/openresty
node              # runs the bundler's post-processing; emsdk ships one, so
                  # sourcing emsdk_env.sh above usually satisfies this too
clang or gcc      # builds C rocks for the host during dependency install
curl or wget      # the build vendors pinned assets over the network
tailwindcss       # v4 specifically: the build passes --cwd, which v3 rejects.
                  # The standalone binary from the tailwindcss releases page works
rsvg-convert      # rasterises icons. Debian and Ubuntu: librsvg2-bin,
                  # Alpine: librsvg
luarocks          # invoked by toku; the managed toolchain ships its own, so it is
                  # only yours to install in --use-system mode
git               # toku init runs git init unless told not to
inotifywait       # toku test --iterate needs it and errors without it

# a first build is slow: expect ten minutes or more of emscripten
# compilation on modest hardware. Later builds are incremental.
]],
    },

    {
      title = "Option two: run toku from the container image",
      desc = table.concat({
        "santoku-make ships an image carrying that whole toolchain, so the ",
        "alternative to the list above is installing nothing but a container runtime. ",
        "Your code stays on your machine and is mounted at /app; only the tooling ",
        "lives in the container, so the build tree lands in your working directory ",
        "exactly as it would locally. Build the image once from a lua-santoku-make ",
        "checkout, then use the wrapper anywhere you would type toku. Everything ",
        "after the double dash goes to toku, and anything before it goes to the ",
        "container runtime, which is how you publish a port. Podman keeps file ",
        "ownership yours automatically; docker does not, so pass -u if root-owned ",
        "build output would bother you. toku-web is the image for anything with a ",
        "client directory; a library project wants the smaller toku-lib, covered in ",
        "the library tab. The image sets TOKU_FG=1, which makes start stay in the ",
        "foreground. Backgrounding OpenResty and exiting would let toku, as PID 1 ",
        "under --rm, stop the container along with the server, and nothing would ",
        "report an error while the published port never answers. In a container you ",
        "build yourself, set TOKU_FG or pass --fg.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ docker build -t toku-web -f toku-web.dockerfile .

$ ./toku-web.sh -- build --test
$ ./toku-web.sh -- test
$ ./toku-web.sh -p 8080:8080 -p 8443:8443 -- start --test

# before the --, the wrapper's own flags first, then runtime flags
#   -c docker | -c podman   force a runtime, otherwise docker then podman
#   -n                      print the command it would run, and exit
#   -u "$(id -u):$(id -g)"  passed through; docker only, keeps output yours
#   -i <image>              override the image name (or set TOKU_IMAGE)
]],
    },

    {
      title = "Scaffold a web project",
      desc = table.concat({
        "The result builds and runs unmodified. The client keeps its data in an ",
        "OPFS-backed SQLite database running in a dedicated worker, the main thread ",
        "talks to it through a proxy, and the server exposes one /sync endpoint over ",
        "its own SQLite database. It runs git init unless you pass git = false ",
        "through the API. Use --here to scaffold into the current directory.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku init --web --name my-app
Created web project: my-app

Next steps:
  cd my-app
  toku build --test  # Build for testing
  toku start --test  # Start development server

$ find my-app -type f -not -path "*/.git/*" | sort
my-app/.gitignore
my-app/LICENSE
my-app/client/bin/bundle.lua
my-app/client/lib/my-app/db.tk.lua
my-app/client/lib/my-app/main.lua
my-app/client/res/pre.tk.js
my-app/client/static/index.html
my-app/client/test/spec/my-app.lua
my-app/make.lua
my-app/res/client/migrations/0.0.1.sql
my-app/res/client/migrations/0.0.2.sql
my-app/res/client/migrations/0.0.3.sql
my-app/res/server/migrations/0.0.1.sql
my-app/server/lib/my-app/db.tk.lua
my-app/server/lib/my-app/web/init.lua
my-app/server/lib/my-app/web/sync.lua
my-app/server/nginx.tk.conf
my-app/server/test/spec/my-app.lua
]],
    },

    {
      title = "Build it and start it",
      desc = table.concat({
        "toku test --iterate --show-logs is the expected day-to-day loop for a web ",
        "project, and the one the framework is developed with. It builds, starts a ",
        "test server, runs the suites, tails the server's access and error logs ",
        "alongside the run, then waits for changes and repeats, printing a line ",
        "telling you it is waiting. Leave it running in one pane and edit in another. ",
        "The individual commands below are what it composes; run them against the ",
        "fresh scaffold before you change anything. Two things that will otherwise ",
        "cost you time: do not pipe toku start, because it backgrounds OpenResty and ",
        "the pipe never closes, and stop takes no --test even though start does, ",
        "since it stops both environments.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku test --iterate --show-logs      # the expected dev loop: leave this running

# what it composes, for when you need one directly:
$ toku build --test            # render client wasm + server tree, test environment
$ toku start --test            # run OpenResty against it (PORT, default 8080)
$ toku test                    # client and server suites
$ toku test --client           # one suite at a time: --root, --client, --server
$ toku stop                    # stops both environments' servers
$ toku start --fg              # foreground, error log on stderr
]],
    },

    scaffolded("web", "make.lua",
      "make.lua: the whole descriptor",
      table.concat({
        "One file configures all three programs. Each of client and server declares ",
        "its own dependency list, because they resolve into separate private rock ",
        "trees: the client's are compiled to WebAssembly, the server's are native. ",
        "build.dependencies are the rocks needed by the build itself rather than by ",
        "the shipped app. The nginx block is read directly by the config template, ",
        "and modules lists the server modules nginx will load. client.files = false ",
        "means the client ships no res files of its own. The one entry worth ",
        "understanding before you change anything is the rules block, covered next.",
      })),

    {
      title = "--pre-js and wrap_events, required by the sqlite worker",
      desc = table.concat({
        "The client's sqlite worker talks to the main thread through handlers named ",
        "Module.start and Module.on_message. Those are defined by ",
        "santoku.web.pwa.wrap_events, which has to be injected into the emscripten ",
        "bundle at link time with --pre-js. It is one rule in the descriptor pointing ",
        "at one rendered file, and without it the worker loads and then does nothing, ",
        "with no error that names the cause. The pattern key matches the bundle ",
        "target name, so it applies to the client entry point only. The file it ",
        "points at, client/res/pre.tk.js, is a one-line template whose entire content ",
        "is the wrap_events JavaScript; you do not edit it, you only have to know it ",
        "must be wired up.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- in make.lua, under client:
rules = {
  ["bundle$"] = {
    ldflags = { "--pre-js", "res/pre.js" },
  },
},
]],
    },

    scaffolded("web", "client/res/pre.tk.js",
      "client/res/pre.tk.js: the whole file",
      table.concat({
        "This is the file --pre-js points at, in its entirety. The .tk means it is ",
        "rendered at build time into res/pre.js, which is the name the ldflags entry ",
        "refers to.",
      })),

    scaffolded("web", "client/bin/bundle.lua",
      "client/bin/bundle.lua: one entry point, two contexts",
      table.concat({
        "Everything in client/bin becomes a page bundle compiled to WebAssembly. ",
        "This single entry point is loaded twice, once on the main thread and once in ",
        "the database worker, and dispatches on whether a document exists. That is ",
        "why one bundle serves as both page and database worker. The bundler finds ",
        "the modules it requires by scanning the source textually, so literal ",
        "requires like these need no extra configuration; only requires computed at ",
        "runtime need listing in client.bundle_mods.",
      })),

    scaffolded("web", "client/lib/%s/main.lua",
      "The client entry module, and the DOM command buffer",
      table.concat({
        "Ordinary Lua running in the browser. Two things here are worth copying as ",
        "patterns. First, the DOM is driven through a command buffer: dom.html, ",
        "dom.text and dom.prop queue mutations and nothing is applied until ",
        "dom.flush(), while dom.read runs immediately and does NOT flush queued ",
        "writes, which is why add_current reads the input value before queueing the ",
        "write that clears it. Second, every handler runs inside async(...), because ",
        "calls into the database worker are asynchronous underneath even though they ",
        "read like ordinary function calls. Note also that ready:await() is destructured ",
        "as a single ok value here; await returns two values, so if you want the ",
        "result as well you must bind both.",
      })),

    scaffolded("web", "client/lib/%s/db.tk.lua",
      "The client database, and how migrations get into the browser",
      table.concat({
        "This module runs in the dedicated worker and owns the SQLite database. The ",
        "template header at the top is the important part: it reads every file in ",
        "res/client/migrations at BUILD time and serializes them into the module, ",
        "because a browser has no filesystem to read them from at runtime. Add a ",
        "migration file and it is embedded on the next build. Everything below the ",
        "header is ordinary santoku-sqlite: statements are prepared once into closures ",
        "(db.getter, db.runner, db.all, db.iter) and multi-statement operations are ",
        "wrapped in db.transaction. The table returned from the callback is exactly ",
        "the API the main thread sees through the proxy.",
      })),

    scaffolded("web", "client/static/index.html",
      "client/static/index.html: the page shell",
      table.concat({
        "Files under client/static are served as-is. This one is plain HTML with no ",
        "template, and the only line that matters structurally is the bundle-js meta ",
        "tag: main.lua reads it to learn its own bundle URL so it can spawn the ",
        "database worker from the same file. Everything else is markup and CSS you ",
        "will replace.",
      })),

    scaffolded("web", "server/nginx.tk.conf",
      "server/nginx.tk.conf: the config and its template environment",
      table.concat({
        "A real nginx configuration with template holes, not a config assembled in ",
        "Lua. The names available inside <% %> are what the engine injects: the nginx ",
        "table from your descriptor (as nginx.nginx, hence the n alias on line one), ",
        "openresty_dir, lua_package_path and lua_package_cpath which point at this ",
        "environment's private rock tree, modules which maps a module name to the file ",
        "nginx should load, and hashed which maps a logical asset name to its ",
        "content-hashed filename. That last one is how cache busting stays correct ",
        "without you tracking hashes by hand, and it pairs with the immutable ",
        "Cache-Control rule at the bottom of the file.",
      })),

    scaffolded("web", "server/lib/%s/web/init.lua",
      "The server side: init",
      table.concat({
        "Loaded once per worker by init_by_lua_file. It opens the server database and ",
        "stashes the handle in package.loaded under a name the request handlers can ",
        "require, which is the standard OpenResty way to share an initialized resource ",
        "across requests without reopening it each time. Server code is ordinary Lua ",
        "inside OpenResty, so the resty ecosystem is available alongside santoku.",
      })),

    scaffolded("web", "server/lib/%s/web/sync.lua",
      "The server side: the sync endpoint",
      table.concat({
        "The whole of the endpoint nginx routes /sync to. It reads the client's ",
        "changes from the request body and a since watermark from the query string, ",
        "hands both to the server database module, and writes back JSON. The ",
        "reconciliation itself lives in server/lib/my-app/db.tk.lua. Note that server ",
        "specs run under the OpenResty interpreter when OPENRESTY_DIR resolves, not ",
        "under a separate system Lua, so a rock that loads in nginx also loads in your ",
        "tests.",
      })),

    scaffolded("web", "res/client/migrations/0.0.1.sql",
      "Migrations, on both sides",
      table.concat({
        "A web project has two migration sets, res/client for the browser's database ",
        "and res/server for the server's. Both use santoku-sqlite-migrate: applied in ",
        "version order, forward-only, each exactly once, in a single transaction. The ",
        "scaffold ships three client migrations, and this first one is not the ",
        "effective schema; 0.0.2 and 0.0.3 evolve it, which is itself the pattern ",
        "being demonstrated. Add 0.0.4.sql beside them and it applies on next run.",
      })),

    {
      title = "Going to production: TLS",
      desc = table.concat({
        "The scaffold serves plain HTTP on one port, which is all you need in ",
        "development because browsers treat localhost as a secure context, so OPFS ",
        "and workers behave normally without a certificate. Production needs real ",
        "TLS, and the shape below is what the framework expects: the descriptor ",
        "carries ssl_cert and ssl_key, and your configure hook decides where they ",
        "come from. Take them from the environment when they are set, which is the ",
        "production path, and otherwise generate a self-signed pair into the server ",
        "work directory for local HTTPS testing. Generate it once and reuse it, or ",
        "every build hands the browser a new certificate. A real certificate usually ",
        "needs its intermediate chain too, which is what ssl_ca_bundle is for.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- make.lua
nginx = {
  domain = env.var("DOMAIN", "localhost"),
  port = env.var("PORT", "8080"),
  ssl_port = env.var("SSL_PORT", "8443"),
  ssl_redirect_port = env.var("SSL_REDIRECT_PORT", ":8443"),
  ssl_self_signed = true,
  ...
},

configure = function (submake, envs)
  local server_env = envs.server
  local nginx_cfg = envs.root.nginx
  if not server_env then return end
  -- configure runs once per environment and all environments share one
  -- nginx table, so an unguarded assignment is overwritten by the last
  -- call. Key anything environment-specific off this:
  local is_test = server_env.environment == "test"
  local cert = env.var("MY_APP_SSL_CERT", nil)
  local key = env.var("MY_APP_SSL_KEY", nil)
  local ca = env.var("MY_APP_SSL_CA_BUNDLE", nil)
  if ca then nginx_cfg.ssl_ca_bundle = ca end
  if cert and key then
    nginx_cfg.ssl_cert, nginx_cfg.ssl_key = cert, key
  elseif nginx_cfg.ssl_self_signed then
    local dir = fs.join(server_env.work_dir, "ssl")
    local c, k = fs.join(dir, "localhost.crt"), fs.join(dir, "localhost.key")
    if not (fs.exists(c) and fs.exists(k)) then
      fs.mkdirp(dir)
      sys.execute({ "openssl", "req", "-x509", "-nodes", "-days", "365",
        "-newkey", "rsa:2048", "-keyout", k, "-out", c,
        "-subj", "/CN=localhost/O=DEV ONLY - NOT FOR PRODUCTION",
        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1" })
    end
    nginx_cfg.ssl_cert, nginx_cfg.ssl_key = c, k
  end
end,

-- then in server/nginx.tk.conf, a second server block:
--   listen <% return n.ssl_port %> ssl;
--   listen [::]:<% return n.ssl_port %> ssl;
--   ssl_certificate <% return n.ssl_cert %>;
--   ssl_certificate_key <% return n.ssl_key %>;
--   add_header Strict-Transport-Security
--     "max-age=31536000; includeSubDomains" always;
--
-- and a redirect from the plain port. Include the port, or local
-- HTTPS testing bounces you to 443 and appears broken; set it empty
-- in production where the site is on the default port:
--   return 301 https://$host<% return n.ssl_redirect_port %>$request_uri;
--
-- Do NOT emit that redirect in the test environment: the scaffold's own
-- server spec posts to http://localhost:$PORT/sync and a 301 fails it.
]],
    },

    {
      title = "Going to production: the service worker",
      desc = table.concat({
        "Offline support is not in the scaffold, and adding it is mostly a matter of ",
        "putting the generated JavaScript somewhere the browser can fetch. This is ",
        "the single most important thing to get right: santoku.web.pwa.sw is a ",
        "BUILD-TIME generator that returns JavaScript as a string. It is not a runtime ",
        "module. Put it in client/static as a .tk.js template so the rendered output ",
        "is a served file, and register it with sw in your document. Putting it under ",
        "client/lib instead produces a Lua module nobody fetches, and the result is an ",
        "app that builds cleanly and never goes offline. Derive the nonce from the ",
        "content rather than the clock, so an unchanged build does not invalidate ",
        "every client's cache.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
-- client/static/serviceworker.tk.js, rendered to /serviceworker.js
<%
  local str = require("santoku.string")
  local sw = require("santoku.web.pwa.sw")

  -- everything the app needs to boot with no network
  -- the scaffold's CSS is inline, so there is no /index.css to list, and
  -- the wasm is required or the app cannot boot offline. A precache entry
  -- that 404s makes install throw and the worker never activates.
  local precache = { "/bundle.js", "/bundle.wasm" }

  -- content-derived, so an identical build keeps the same cache
  local nonce = str.to_base64(str.sha256(table.concat(precache, "\n")
    .. "\n" .. str.sha256(app_html))):sub(1, 22)

  return sw({
    nonce = nonce,
    precache = precache,
    index_html = app_html,          -- answers navigations while offline
    no_cache = { "^/sync$" },       -- never serve these from cache
  })
%>
]],
    },

    {
      title = "Going to production: the document and manifest",
      desc = table.concat({
        "santoku.web.pwa.index renders the document that the service worker will serve ",
        "for navigations, so the two are built together: generate the HTML, hand it to ",
        "sw as index_html, and point the document at the worker with sw. Both renders ",
        "need the same app_html, so build it once where both can reach it: put the ",
        "index(...) call in a helper under res/ and runfile it from the serviceworker ",
        "template. initial = true is required, since only that branch emits the script ",
        "that registers the worker. Set csp = true ",
        "and the policy is built from the hashes of the inline scripts actually present ",
        "in the output, which is why it must run after any transforms. manifest points ",
        "at a rendered manifest.json, and any file you add to the public directory here ",
        "must also be tied to client_env.static_files_ok so hashing does not race it.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local index = require("santoku.web.pwa.index")

local app_html = index({
  title = "my-app",
  description = "...",
  theme_color = "#1e293b",
  manifest = "/manifest.json",
  sw = "/serviceworker.js",
  initial = true,
  head = [=[<meta name="bundle-js" content="/bundle.js">
            <script src="/bundle.js"></script>]=],
})

-- Point sw at a STABLE url, not at the hashed worker file. pwa.index
-- hashes the inline registration script for the CSP; if that url is
-- itself a hashed asset, the asset-hash pass rewrites it afterwards,
-- the declared hash no longer matches, and the browser silently blocks
-- the page's own scripts. Serve the worker from a fixed location:
--
--   location = /sw.js { try_files /<% return hashed("serviceworker.js") %> =404; }
--
-- A service worker needs a stable url anyway: its scope and update
-- checks are keyed off it, so a hashed worker url breaks updates.
]],
    },

  },

}

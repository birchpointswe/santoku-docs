return {

  intro = table.concat({
    "santoku-cli ships toku, the command-line front end of the framework: every santoku ",
    "rock, and this documentation site itself, is built, tested, and released with it. ",
    "The commands fall into two groups. The project lifecycle (init, test, install, pack, ",
    "release, exec, clean, plus build, start, and stop for web projects) is driven by ",
    "santoku-make from a plain-Lua make.lua descriptor: sources are rendered into a build ",
    "tree, dependencies are installed with luarocks into a private lua_modules, specs run ",
    "against that tree, and the same tree feeds install and the luarocks release flow. ",
    "The standalone utilities (template, bundle, lua) expose santoku-template, ",
    "santoku-bundle, and an instrumented interpreter directly. This tab is a guided tour ",
    "of the whole surface, basics to advanced. toku runs processes and touches the real ",
    "filesystem, so the shell examples are display only; the make.lua descriptor example ",
    "is plain Lua and runs in the page.",
  }),

  examples = {

    {
      title = "The command surface",
      desc = table.concat({
        "Thirteen subcommands, listed here with their descriptions verbatim from the ",
        "argparse declarations in bin/toku.tk.lua. Every invocation also accepts ",
        "--verbosity N (default 1): 0 silences the [make] line printed per rebuilt ",
        "target, 2 and up adds [ok], [src], and [phony] trace lines. build, start, and ",
        "stop apply to web projects; the rest of the lifecycle works on both project ",
        "types.",
      }),
      runnable = false,
      code = [[
toku init       Initialize a new project
toku test       Run tests
toku install    Install the project
toku pack       Build rockspec and tarball without releasing
toku release    Release the project
toku exec       Execute a command in the build environment
toku clean      Clean build artifacts
toku build      Build the project
toku start      Start the server
toku stop       Stop the server
toku template   Process templates
toku bundle     Create standalone executables
toku lua        Run the lua interpreter on a file
]],
    },

    {
      title = "toku init: scaffold a library",
      desc = table.concat({
        "Extracts a boilerplate, renames every tokuboilerplate occurrence to your name ",
        "(which must match ^[a-z][a-z0-9-]*$), and runs git init. --here uses the ",
        "current directory and its name; --dir picks the destination. The scaffold is a ",
        "working rock, not a stub: a sqlite-backed library with a migration, a C ",
        "extension (capi.c), a bin/ entry point, and a passing spec suite.",
      }),
      runnable = false,
      code = [[
$ toku init --name my-lib
Created library project: my-lib

Next steps:
  cd my-lib
  toku test        # Run tests
  toku install     # Install locally

$ find my-lib -type f -not -path "*/.git/*" | sort
my-lib/.gitignore
my-lib/LICENSE
my-lib/bin/my-lib.lua
my-lib/lib/my_lib.tk.lua
my-lib/lib/my_lib/capi.c
my-lib/make.lua
my-lib/res/migrations/0.0.1.sql
my-lib/test/spec/my_lib.lua
]],
    },

    {
      title = "make.lua: the project descriptor",
      desc = table.concat({
        "Everything toku knows about a project comes from make.lua, a plain Lua file ",
        "returning { env = ... }. This is santoku-cli's own descriptor verbatim: name and ",
        "version become the rockspec, dependencies are luarocks constraints, public = ",
        "true is what makes toku release available, and computed fields are plain Lua ",
        "expressions (env.download becomes the rockspec source url).",
      }),
      code = [[
local env = {
  name = "santoku-cli",
  version = "2.4.4-1",
  variable_prefix = "TK_CLI",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 2.0.0, < 3.0.0",
    "santoku-fs >= 2.0.0, < 3.0.0",
    "santoku-template >= 2.0.0, < 3.0.0",
    "santoku-bundle >= 2.0.0, < 3.0.0",
    "santoku-system >= 2.0.0, < 3.0.0",
    "santoku-test-runner >= 2.0.0, < 3.0.0",
    "santoku-make >= 5.0.0, < 6.0.0",
    "argparse >= 0.7.1-1",
  },
}
env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/"
  .. env.version .. "/" .. env.tarball
print(env.name, env.version)
print(env.download)
return { env = env }
]],
    },

    {
      title = "Environments and the build tree",
      desc = table.concat({
        "Work happens under build/<env>/: --env prod reads make.prod.lua instead of ",
        "make.lua and builds under build/prod/. Files ending .tk are rendered through ",
        "santoku-template against the descriptor env with the extension stripped, so ",
        "lib/my_lib.tk.lua lands as lib/my_lib.lua; a .d sidecar next to each rendered ",
        "file records what the template read, so touching an included file restales the ",
        "output. The *.flag files persist CLI options like --single and --skip-check so ",
        "that changing them restales the generated run and check scripts.",
      }),
      runnable = false,
      code = [[
$ toku test
$ ls build/default
lua.flag             single.flag     test
lua_cpath_extra.flag skip_check.flag
lua_path_extra.flag
$ ls build/default/test
Makefile   check.sh  lua_modules     luacheck.lua  res     test
bin        lib       lua_modules.ok  luarocks.lua  run.sh
my-lib-0.0.1-1.rockspec
$ toku test --env prod
$ ls build
default  prod
]],
    },

    {
      title = "toku test: the full pipeline",
      desc = table.concat({
        "One command does the whole loop: render sources into build/default/test, ",
        "luarocks make the test rockspec into a private lua_modules there, run sh ",
        "run.sh (which invokes the standalone runner as toku test -i \"$LUA\" ",
        "--match \"^.*%.lua$\" test/spec), then sh check.sh (luacheck over lib, bin, ",
        "and test/spec unless --skip-check). The runner prints one Test: line per spec ",
        "file and is silent on pass; a failing assertion prints the nested test tag ",
        "chain, the error, and a traceback. Every spec runs by default, so one command ",
        "reports every failure; pass -s to stop at the first one.",
      }),
      runnable = false,
      code = [[
$ toku test
[make]  build/default/test/lib/my_lib.lua
[make]  build/default/test/my-lib-0.0.1-1.rockspec
[make]  build/default/test/run.sh

Test:   test/spec/my_lib.lua

Total: 0 warnings / 0 errors in 3 files
]],
    },

    {
      title = "Selecting and instrumenting tests",
      desc = table.concat({
        "In project mode --single runs one spec file, --skip-check drops luacheck, ",
        "--lua swaps the interpreter, -s stops at the first failure instead of running ",
        "the whole suite, and --profile / --trace preload santoku.profile ",
        "and santoku.trace into the test interpreter for a performance profile or ",
        "source trace. Passing file or directory arguments switches to the standalone ",
        "runner, bypassing the project build entirely: -m filters files by Lua ",
        "pattern and -i runs each file under an arbitrary interpreter command instead ",
        "of dofile. -i only applies in that standalone mode; in project mode the ",
        "interpreter comes from --lua.",
      }),
      runnable = false,
      code = [[
$ toku test --single test/spec/my_lib.lua
$ toku test --skip-check
$ toku test --profile
$ toku test --lua luajit
$ toku test -s
$ toku test -m core -i luajit test/spec
Test:   test/spec/core.lua
]],
    },

    {
      title = "toku test --iterate: the watch loop",
      desc = table.concat({
        "Runs test plus check, then blocks on inotifywait watching lib, bin, test, ",
        "res, and every directory referenced by the .d sidecars, and reruns on any ",
        "write. It requires inotifywait on PATH (errors with \"inotify not found\" ",
        "otherwise), asks for a restart when make.lua itself changes, and bails out ",
        "after two consecutive failures with no file changes in between. This is the ",
        "standing dev loop: develop with toku test --iterate --show-logs.",
      }),
      runnable = false,
      code = [[
$ toku test --iterate

Test:   test/spec/my_lib.lua

[iterate] make.lua changed - please restart iterate
]],
    },

    {
      title = "toku test --wasm",
      desc = table.concat({
        "Builds a parallel tree under build/default-wasm/ with the C toolchain swapped ",
        "for emscripten: dependencies compile with emcc, each spec is bundled to a .js ",
        "file, and run.sh drives them with toku test -i \"node --expose-gc\" so the ",
        "same suite runs against the WebAssembly build. --single maps the .lua spec to ",
        "its .js twin.",
      }),
      runnable = false,
      code = [[
$ toku test --wasm
Test:   test/spec/my_lib.js
$ toku test --wasm --single test/spec/my_lib.lua
]],
    },

    {
      title = "toku install",
      desc = table.concat({
        "Runs test and check, renders the shippable tree under build/default/build, ",
        "and luarocks-makes the rockspec there into the active rocks tree. ",
        "--skip-tests goes straight to the build. --luarocks-config points luarocks at ",
        "another config, which is how to pull a locally edited santoku rock ",
        "into a project's build trees: run toku install from the library repo against each ",
        "luarocks.lua found under the app's build/ directory.",
      }),
      runnable = false,
      code = [[
$ toku install
$ toku install --skip-tests
$ find ~/git/myapp/build -name luarocks.lua \
    -exec toku install --luarocks-config {} --skip-tests \;
]],
    },

    {
      title = "toku install --bundled: standalone executables",
      desc = table.concat({
        "Instead of installing the rock, bundle every bin/*.lua through santoku-bundle ",
        "into a native executable and copy it to <prefix>/bin (prefix defaults to ",
        "$PREFIX, then $HOME/.local, so on Termux $PREFIX wins). Lua modules are ",
        "embedded and C extensions are linked statically from the .o and vendored ",
        "archives each rock installs alongside its .so, so the binary keeps working ",
        "after the build tree is gone. It still needs the shared Lua library and any ",
        "system libraries your dependencies link, so readelf -d will show liblua plus ",
        "entries like libopenblas; what it does not need is Lua modules on disk or a ",
        "LUA_PATH. A dependency built before santoku-make ",
        "5.0.3 ships no such objects, and the bundler falls back to dynamic linking ",
        "for it with a warning naming the module. --bundle-mods preloads modules the ",
        "static require scan cannot see (comma separated), --bundle-ignores skips ",
        "names (debug is always ignored), --bundle-cc picks the compiler, and ",
        "--bundle-flags replaces the auto-derived compile flags rather than adding to ",
        "them, so supply your own -I, -L and -l when you pass it. Any value starting ",
        "with a dash needs the equals form, since the option parser would otherwise ",
        "read it as a flag. With --wasm the compiler defaults to emcc and each entry ",
        "point lands as a .js file plus a node wrapper script. That path needs emcc, ",
        "emmake and node on PATH, and it rebuilds the whole dependency tree under emcc ",
        "into build/<env>-wasm, so the first run is slow even for a small project.",
      }),
      runnable = false,
      code = [[
$ toku install --bundled --prefix "$HOME/.local"
$ ls ~/.local/bin
my-lib
$ toku install --bundled --bundle-mods my-lib.plugins \
    --bundle-ignores ssl --bundle-flags="-O2 -I/usr/include -lm"
]],
    },

    {
      title = "toku pack: the release tarball",
      desc = table.concat({
        "Builds build/default/build and tars it up as <name>-<version>.tar.gz without ",
        "touching git or luarocks.org: sources with .tk stripped, the generated ",
        "Makefile (plus lib/Makefile and bin/Makefile when those trees exist), and ",
        "LICENSE, all under a <name>-<version>/ prefix. The rockspec sits alongside ",
        "the tarball, and its source url is the env.download computed in make.lua.",
      }),
      runnable = false,
      code = [[
$ toku pack
$ ls build/default/build
Makefile  bin  santoku-cli-2.2.2-1.rockspec  santoku-cli-2.2.2-1.tar.gz
$ tar -tzf build/default/build/santoku-cli-2.2.2-1.tar.gz
santoku-cli-2.2.2-1/bin/toku.lua
santoku-cli-2.2.2-1/bin/Makefile
santoku-cli-2.2.2-1/Makefile
santoku-cli-2.2.2-1/LICENSE
]],
    },

    {
      title = "toku release: luarocks end to end",
      desc = table.concat({
        "Only exists when make.lua sets public = true; otherwise toku prints the first ",
        "line below and stops. release depends on pack, which depends on test and ",
        "check unless --skip-tests, and then executes exactly the command sequence ",
        "shown, inside build/default/build: refuse a dirty tree (git diff --quiet ",
        "fails with \"Commit your changes first\"), tag the rock version, push, create ",
        "a GitHub release via gh carrying the tarball and rockspec (which is where the ",
        "rockspec's download url points), and upload the rockspec to luarocks.org. The ",
        "api key comes from the LUAROCKS_API_KEY environment variable.",
      }),
      runnable = false,
      code = [[
$ toku release
Release not available (public != true in make.lua)

$ export LUAROCKS_API_KEY=xxxxxxxxxxxxxxxx
$ toku release

git diff --quiet
git tag 2.2.2-1
git push --tags
git push
gh release create --generate-notes 2.2.2-1 \
  santoku-cli-2.2.2-1.tar.gz santoku-cli-2.2.2-1.rockspec
luarocks upload --skip-pack --api-key $LUAROCKS_API_KEY \
  santoku-cli-2.2.2-1.rockspec
]],
    },

    {
      title = "toku init --web: scaffold a web app",
      desc = table.concat({
        "The web boilerplate is a working todo app: client/ holds the Lua that ",
        "compiles to WebAssembly (an entry point and a sqlite-backed db module that ",
        "runs in a worker), server/ the OpenResty side with its nginx.tk.conf and a ",
        "sync endpoint, and res/ the migrations for both databases. One descriptor, ",
        "make.lua. It is deliberately not a PWA; see Getting started for adding a ",
        "service worker and TLS.",
      }),
      runnable = false,
      code = [[
$ toku init --web --name my-app
Created web project: my-app

Next steps:
  cd my-app
  toku build --test  # Build for testing
  toku start --test  # Start development server

$ find my-app -type d -not -path "*/.git*" | sort
my-app
my-app/client
my-app/client/bin
my-app/client/lib
my-app/client/lib/my-app
my-app/client/res
my-app/client/static
my-app/client/test
my-app/client/test/spec
my-app/res
my-app/res/client
my-app/res/client/migrations
my-app/res/server
my-app/res/server/migrations
my-app/server
my-app/server/lib
my-app/server/lib/my-app
my-app/server/lib/my-app/web
my-app/server/test
my-app/server/test/spec
]],
    },

    {
      title = "The web loop: build, start, test, stop",
      desc = table.concat({
        "build renders the client to WASM and the server tree; --test targets the test ",
        "environment, without it the main one. start launches OpenResty against the ",
        "built dist directory via its run.sh (openresty -p <dist> -c nginx.conf), ",
        "backgrounded by default; --fg execs it in the foreground with the error log ",
        "on stderr. stop shuts down both environments' servers. Environment variables ",
        "prefix as usual: a dev server runs as DB_FILE=tmp.db toku start ",
        "--test. toku test on a web project needs no manual start: when server specs ",
        "exist it stops any old server, starts a fresh test one, waits for its pid ",
        "file, and fails fast if the process dies (check the nginx error log).",
      }),
      runnable = false,
      code = [[
$ toku build --test
$ DB_FILE=tmp.db toku start --test
$ toku test
$ toku stop
$ toku start --fg
]],
    },

    {
      title = "Web tests: root, client, server, logs",
      desc = table.concat({
        "A web project has three suites: test/spec at the root (shared lib code), ",
        "client/test/spec (compiled to WASM, run under node), and server/test/spec ",
        "(run against the live test server). --root, --client, and --server select ",
        "them; --single infers the suite from the path prefix. --show-logs tails the ",
        "test server's access.log and error.log alongside the run, and toku stop ",
        "cleans up the tail process with the server. Server specs run under the same ",
        "interpreter the server itself uses: OpenResty's LuaJIT when --openresty-dir ",
        "(or OPENRESTY_DIR) resolves, so a rock that loads in nginx also loads in the ",
        "specs. Root specs run under the plain interpreter. --lua overrides both.",
      }),
      runnable = false,
      code = [[
$ toku test --root
$ toku test --client
$ toku test --server --show-logs
$ toku test --single client/test/spec/my-app.lua
$ toku test --single server/test/spec/my-app.lua
]],
    },

    {
      title = "toku exec: a shell inside the test env",
      desc = table.concat({
        "Installs the test dependencies if needed, then runs an arbitrary command in ",
        "build/default/test with LUA_PATH and LUA_CPATH pointing at that tree's ",
        "lua_modules, so ad-hoc scripts see exactly what the specs see: the rendered ",
        "sources and the pinned rocks.",
      }),
      runnable = false,
      code = [[
$ toku exec lua test/spec/my_lib.lua
Test:   test/spec/my_lib.lua
$ toku exec luarocks list
$ toku exec sqlite3 tmp.db
]],
    },

    {
      title = "toku clean",
      desc = table.concat({
        "Default: remove generated files inside build/<env>/ (rendered .lua sources, ",
        ".d sidecars, stamp files, generated luarocks.lua and luacheck.lua) while ",
        "keeping the expensive lua_modules trees. --deps removes exactly those trees ",
        "instead, --all removes the whole build directory, --dry-run prints without ",
        "removing, and web projects add --wasm, --client, and --server to scope the ",
        "sweep. Paths outside the project directory are refused outright.",
      }),
      runnable = false,
      code = [[
$ toku clean --dry-run
Would remove:
  build/default/test/lib/my_lib.lua
  build/default/test/bin/my-lib.lua
  build/default/test/luarocks.lua
  build/default/test/luacheck.lua
$ toku clean --deps
Removed:
  build/default/test/lua_modules
  build/default/test/lua_modules.ok
$ toku clean --all
Removed:
  build
$ toku clean
Removed:
  (nothing to clean)
]],
    },

    {
      title = "toku lua: an instrumented interpreter",
      desc = table.concat({
        "Runs a string or file under the configured interpreter (--lua overrides), ",
        "assembling -l preloads for the requested instruments: --profile loads ",
        "santoku.profiler for a performance profile at exit, --trace loads ",
        "santoku.tracer for line tracing, and --serialize loads santoku.autoserialize, ",
        "which wraps the global print so tables come out as readable Lua literals ",
        "instead of table: 0x... addresses.",
      }),
      runnable = false,
      code = [[
$ toku lua --string 'print(1 + 2)'
3
$ toku lua --serialize --string 'print({ a = 1, b = { 2, 3 } })'
$ toku lua --file scripts/report.lua --profile
$ toku lua --file scripts/step-through.lua --trace
]],
    },

    {
      title = "toku template: standalone rendering",
      desc = table.concat({
        "The same engine that expands .tk files in the build, exposed directly. -f ",
        "renders one file (- is stdin or stdout), -d renders a directory tree with -t ",
        "trimming a prefix from output paths, and -c loads a Lua config whose env ",
        "table becomes the render environment. -M writes a make-style .d file next to ",
        "each output listing every file the template read through readfile, which is ",
        "how the build harness gets transitive template dependencies.",
      }),
      runnable = false,
      code = [[
$ echo '<% return "hello" %>' | toku template -f - -o -
hello
$ toku template -d res/tmpl -t res/tmpl -o build/out -c cfg.lua
$ toku template -f res/index.tk.html -o build/index.html -M
$ cat build/index.html.d
res/index.tk.html: res/header.html
build/index.html: res/index.tk.html
]],
    },

    {
      title = "toku bundle: one file in, one executable out",
      desc = table.concat({
        "The CLI face of santoku-bundle (see its tab for the library). It scans the ",
        "entry for string-literal require calls, resolves them against --path and ",
        "--cpath, merges every Lua module into one file via package.preload, embeds ",
        "the (optionally luac-stripped) bytecode in a generated C program that also ",
        "preloads the C extensions' luaopen_ symbols, and compiles it, printing the ",
        "compile command. Four options are required: --input, --output-directory, ",
        "--path and --cpath. Unlike toku install --bundled, this command derives no ",
        "compile flags for you, so --flags is the complete list and must carry the -I ",
        "that finds lua.h and the -l that supplies liblua, or the compile fails before ",
        "it starts. Dynamic requires need --mod; names to leave to the runtime take ",
        "--ignore; --env NAME VALUE bakes in a setenv at startup; --deps writes a make ",
        ".d file covering every bundled module. Where a C extension ships a .link ",
        "sidecar it is linked statically, and where it does not the .so is linked ",
        "directly and a warning names it.",
      }),
      runnable = false,
      code = [[
$ toku bundle --input bin/tool.lua --output-directory out \
    --path "lua_modules/share/lua/5.1/?.lua" \
    --cpath "lua_modules/lib/lua/5.1/?.so" \
    --luac-default \
    --flags="-O2 -I$(luarocks config variables.LUA_INCDIR) \
             -L$(luarocks config variables.LUA_LIBDIR) -llua5.1 -lm" \
    --env TOOL_HOME /opt/tool \
    --mod tool.plugins --ignore debug
cc out/tool.c -O2 -I... -L... -llua5.1 -lm \
    lua_modules/lib/lua/5.1/tool/capi.o -o out/tool
$ ls out
tool  tool.c  tool.lua  tool.luac
]],
    },

  },

}

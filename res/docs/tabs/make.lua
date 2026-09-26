return {

  intro = table.concat({
    "santoku-make is the build system behind the toku CLI. It has two layers: ",
    "santoku.make, a small dependency-graph engine that resolves file targets by ",
    "modification time, and santoku.make.project, which turns a make.lua descriptor ",
    "into a built, tested, and installable luarocks package, as a library, an ",
    "executable, or a WASM-client web app served by OpenResty. This tab is a guided ",
    "tour: the engine first, then a library project end to end (init, descriptor, ",
    "test, install, release), then the web project pipeline (client pages, asset ",
    "hashing, nginx, dev server). Builds touch the real filesystem and toolchain, so ",
    "most examples are shown for reading; the descriptor, env-merge, and template ",
    "examples are plain Lua and run in the page. The best way to learn the layer is ",
    "reading real descriptors: the base library's minimal ",
    "https://github.com/birchpointswe/lua-santoku/blob/master/make.lua is the ",
    "canonical lib project, and this documentation site is itself a web project whose ",
    "repo will be public at launch.",
  }),

  examples = {

    {
      title = "The engine: a target graph",
      desc = table.concat({
        "make() returns a submake; target(targets, deps, fn) registers nodes and ",
        "build(targets, verbosity) resolves the DAG. fn = true marks a phony aggregate ",
        "that is always stale; a registered file with no fn is a source leaf. At ",
        "verbosity 2 and up every node is traced as [make], [ok], [src], or [phony].",
      }),
      runnable = false,
      code = [[
local make = require("santoku.make")
local fs = require("santoku.fs")
local arr = require("santoku.array")
local m = make()
m.target({ "out/header.txt" }, {}, function (ts)
  fs.mkdirp(fs.dirname(ts[1]))
  fs.writefile(ts[1], "Header\n")
end)
m.target({ "out/body.txt" }, {}, function (ts)
  fs.writefile(ts[1], "Body\n")
end)
m.target(
  { "out/main.txt" },
  { "out/header.txt", "out/body.txt" },
  function (ts, ds)
    local parts = {}
    for i = 1, #ds do
      parts[i] = fs.readfile(ds[i])
    end
    fs.writefile(ts[1], arr.concat(parts))
  end)
m.target({ "all" }, { "out/main.txt" }, true)
m.build({ "all" }, 3)
print("[make] header, body, main were logged, then [phony] all")
return fs.readfile("out/main.txt")
]],
    },

    {
      title = "Staleness by modification time",
      desc = table.concat({
        "A target with a build fn reruns only when a dependency is newer than it. ",
        "A second build is a no-op, and rewriting a dependency restales only its ",
        "consumers. A missing target with no registered fn is an error.",
      }),
      runnable = false,
      code = [[
local make = require("santoku.make")
local fs = require("santoku.fs")
local str = require("santoku.string")
local m = make()
m.target({ "out/upper.txt" }, { "out/lower.txt" }, function (ts, ds)
  fs.writefile(ts[1], str.upper(fs.readfile(ds[1])))
end)
fs.mkdirp("out")
fs.writefile("out/lower.txt", "hello\n")
m.build({ "out/upper.txt" }, 2)
print("first run: [src] out/lower.txt, [make] out/upper.txt")
m.build({ "out/upper.txt" }, 2)
print("second run: [ok] out/upper.txt, nothing rebuilt")
fs.writefile("out/lower.txt", "changed\n")
m.build({ "out/upper.txt" }, 2)
print("third run: [make] out/upper.txt again")
return fs.readfile("out/upper.txt")
]],
    },

    {
      title = "Sidecar .d files: transitive dependencies",
      desc = table.concat({
        "For any target t the engine also reads t .. \".d\", a make-style dependency ",
        "file, and folds the newest listed file into staleness. The project layer ",
        "writes one next to every rendered template. The render env's readfile records ",
        "each file the template reads, depend records a file or directory tree without ",
        "reading it, and serialize_deps saves the set as one line. Editing a recorded ",
        "file then restales the output even though it is not a direct dep.",
      }),
      runnable = false,
      code = [[
local make = require("santoku.make")
local fs = require("santoku.fs")
local tmpl = require("santoku.template")
local m = make()
m.target({ "out/page.html" }, { "res/page.tk.html" }, function (ts, ds)
  local deps = {}
  local env = {
    title = "Docs",
    readfile = function (fp)
      deps[fp] = true
      return fs.readfile(fp)
    end,
    depend = function (fp)
      deps[fp] = true
      return fp
    end,
  }
  fs.mkdirp(fs.dirname(ts[1]))
  fs.writefile(ts[1], tmpl.renderfile(ds[1], env))
  fs.writefile(ts[1] .. ".d", tmpl.serialize_deps(ds[1], ts[1], deps))
end)
m.build({ "out/page.html" }, 2)
print("if the template read res/header.html, touching it restales out/page.html")
return true
]],
    },

    {
      title = "depend: track files a template never reads",
      desc = table.concat({
        "Every project template render gets depend(path, prune) beside readfile. depend ",
        "records a file in the .d sidecar without reading it, and returns path, so it ",
        "wraps anything a block reaches through fs.runfile, require, or a directory walk. ",
        "On a directory it also records every entry under it, so adding or removing a ",
        "file restales the output. prune(path, mode) returns true for an entry or subtree ",
        "to leave out.",
      }),
      runnable = false,
      lang = "text",
      code = [[
<%
  local fs = require("santoku.fs")
  local helper = fs.runfile(depend("res/app_html.lua"))
  depend("res/icons", function (fp)
    return fs.basename(fp) == "drafts"
  end)
  return helper.render()
%>
]],
    },

    {
      title = "toku init: scaffold a library project",
      desc = table.concat({
        "The project layer ships a boilerplate; toku init extracts it, renames every ",
        "tokuboilerplate occurrence to your project name, and runs git init. The result ",
        "is a complete lib project: a descriptor, a templated Lua module, a C extension ",
        "stub, a bin entry point, and a spec.",
      }),
      runnable = false,
      code = [[
$ toku init --name my-lib
Created library project: my-lib

Next steps:
  cd my-lib
  toku test        # Run tests
  toku install     # Install locally

$ find my-lib -type f -not -path "*/.git/*"
my-lib/.gitignore
my-lib/LICENSE
my-lib/make.lua
my-lib/bin/my-lib.lua
my-lib/lib/my_lib.tk.lua
my-lib/lib/my_lib/capi.c
my-lib/res/migrations/0.0.1.sql
my-lib/test/spec/my_lib.lua
]],
    },

    {
      title = "What make.lua contains",
      desc = table.concat({
        "A project is a make.lua returning a table with an env field: plain data, no ",
        "framework calls. name and version are required; dependencies are luarocks ",
        "constraints; test.dependencies stay out of the runtime rockspec; public = true ",
        "is required by pack and release. The rockspec filename is derived from name and ",
        "version exactly as shown. A real one to read: ",
        "https://github.com/birchpointswe/lua-santoku/blob/master/make.lua",
      }),
      code = [[
local descriptor = {
  type = "lib",
  env = {
    name = "my-lib",
    version = "0.0.1-1",
    license = "MIT",
    public = true,
    dependencies = {
      "lua == 5.1",
      "santoku >= 2.0.0, < 3.0.0",
    },
    test = {
      dependencies = { "luacov >= 0.15.0-1" },
    },
  },
}
local env = descriptor.env
print("rockspec:", env.name .. "-" .. env.version .. ".rockspec")
print("runtime deps:", #env.dependencies)
print("test-only deps:", #env.test.dependencies)
return env.name
]],
    },

    {
      title = "One env, two build environments",
      desc = table.concat({
        "The project layer builds a test env and a build env from your descriptor with ",
        "santoku.table merge, which fills only missing keys and merges tables deeply, ",
        "so phase-specific fields win and everything else inherits. This snippet mirrors ",
        "the real merge chain, including the variable_prefix default derived from the ",
        "project name.",
      }),
      code = [[
local tbl = require("santoku.table")
local str = require("santoku.string")
local config_env = {
  name = "my-lib",
  version = "0.0.1-1",
  cflags = { "-O2" },
}
local base_env = { root_dir = "/src/my-lib", is_wasm = false }
local test_env = tbl.merge(
  { environment = "test", build_dir = "build/default/test" },
  config_env, base_env)
local build_env = tbl.merge(
  { environment = "build", build_dir = "build/default/build" },
  config_env, base_env)
print(test_env.environment, test_env.name, test_env.cflags[1])
print(build_env.environment, build_env.build_dir)
local prefix = config_env.variable_prefix
  or str.upper(str.gsub(config_env.name, "%W+", "_"))
print("variable_prefix:", prefix)
return test_env.root_dir
]],
    },

    {
      title = "The descriptor's environment is part of the staleness key",
      desc = table.concat({
        "A descriptor that reads env.var parameterises the build by the ",
        "environment, and mtimes alone would miss that: make.lua is the tracked ",
        "file, not the variables it read. So santoku-make writes the resolved ",
        "descriptor to build/<env>/config.stamp (build/<env>-wasm/config.stamp for ",
        "a wasm build) and tracks that stamp alongside the descriptor. ",
        "WORKERS=4 toku build re-renders everything the value feeds without ",
        "touching make.lua, and running again with the environment unchanged is ",
        "still a no-op. One limitation to know: env.var called inside the configure ",
        "hook is not captured, because the hook runs after the stamp is written and ",
        "those values never land in the config table. Read such values in the ",
        "descriptor and pass them through env if you want them tracked.",
      }),
      runnable = false,
      lang = "text",
      code = [[
-- make.lua
local env = require("santoku.env")
return { env = { nginx = { workers = env.var("WORKERS", "auto") } } }

$ toku build --test        # worker_processes auto
$ WORKERS=4 toku build --test
$ WORKERS=4 toku build --test   # no-op, the stamp matches

$ cat build/default/config.stamp   # the key: the whole resolved descriptor
]],
    },

    {
      title = ".tk files: templates rendered with the project env",
      desc = table.concat({
        "Any file named *.tk or *.tk.* is rendered through santoku.template against ",
        "the merged env, with .tk stripped from the output name; everything else is ",
        "copied verbatim. The framework's own Makefiles and rockspec are the same kind ",
        "of template. So lib/version.tk.lua becomes lib/version.lua with the blocks ",
        "already evaluated.",
      }),
      code = [[
local template = require("santoku.template")
local env = { name = "my-lib", version = "0.0.2-1" }
local src = "return { name = \"<% return name %>\", " ..
  "version = \"<% return version %>\" }"
local out = template.render(src, env)
print(out)
return out
]],
    },

    {
      title = "Conditionals in a .tk file need push and pop",
      desc = table.concat({
        "Each <% %> block is compiled as its own chunk, so a Lua if cannot span two ",
        "of them. Writing one is the common first mistake in a .tk file and the ",
        "error does not lead anywhere useful: the chunk name is the block's own ",
        "text, so you get 'end' expected near '<eof>' with no file name and no ",
        "mention of the mechanism. Emit conditionally with push(cond) and pop() ",
        "instead, which the template engine injects for exactly this: text between ",
        "them is emitted only when the condition held, and pairs nest. The ",
        "santoku-template tab has the full treatment, including showing().",
      }),
      runnable = false,
      lang = "text",
      code = [[
# server/nginx.tk.conf, the form that fails to compile
<% if access_log_on then %>
  access_log <% return n.access_log %>;
<% else %>
  access_log off;
<% end %>

toku: [string " if access_log_on then "]:1: 'end' expected near '<eof>'

# the form that works
<% push(access_log_on) %>
  access_log <% return n.access_log %>;
<% pop() %>
<% push(not access_log_on) %>
  access_log off;
<% pop() %>
]],
    },

    {
      title = "toku test: build the test env, run the suite",
      desc = table.concat({
        "toku test renders everything into build/<env>/test, runs luarocks make there ",
        "so the rock plus its test deps land in a local lua_modules, then runs the spec ",
        "suite via the santoku test runner followed by luacheck. --iterate watches ",
        "sources (and everything recorded in .d files) with inotifywait and reruns on ",
        "change. --wasm compiles each spec to a .js bundle with emcc and runs it under ",
        "node --expose-gc.",
      }),
      runnable = false,
      code = [[
$ toku test
$ toku test --iterate
$ toku test --single test/spec/my_lib.lua
$ toku test --skip-check
$ toku test --wasm
$ toku test --env prod
]],
    },

    {
      title = "toku build, install, pack, release",
      desc = table.concat({
        "build renders and compiles under build/<env>/build; install runs luarocks ",
        "make on the built rock, or with --bundled compiles every bin/*.lua to a ",
        "standalone executable via santoku-bundle and copies it into <prefix>/bin ",
        "(default $PREFIX, falling back to ~/.local). pack tars lib, bin, deps, ",
        "LICENSE, and the Makefiles into name-version.tar.gz. release requires ",
        "public = true and a clean git tree: it ",
        "tags the version, pushes, creates a GitHub release with the tarball and ",
        "rockspec, and uploads the rockspec to luarocks with LUAROCKS_API_KEY.",
      }),
      runnable = false,
      code = [[
$ toku build
$ toku install
$ toku install --bundled --prefix "$HOME/.local"
$ toku pack
$ LUAROCKS_API_KEY=... toku release
]],
    },

    {
      title = "Driving the lifecycle from Lua",
      desc = table.concat({
        "toku is a thin front end: project.init reads the descriptor and returns the ",
        "lifecycle table. test builds and runs the suite, install runs luarocks make, ",
        "lua_env(tree) builds a lua tree and returns its interpreter with absolute ",
        "lua_path and lua_cpath, which toku lua --tree and toku env --tree use, and ",
        "clean returns the list of paths it removed (or would remove with dry_run).",
      }),
      runnable = false,
      code = [[
local project = require("santoku.make.project")
local sys = require("santoku.system")
local m = project.init({ env = "default" })
m.test({ skip_check = true })
m.install()
local t = m.lua_env("test")
sys.execute({ t.lua, "-e", "print('runs against the test tree')",
  env = { LUA_PATH = t.lua_path, LUA_CPATH = t.lua_cpath } })
local removed = m.clean({ deps = true, dry_run = true })
print("clean --deps would remove", #removed, "paths")
return m.config.env.name
]],
    },

    {
      title = "C extensions: cflags, ldflags, and deps/ Makefiles",
      desc = table.concat({
        "A lib project compiles every lib/**/*.c to a shared object. To link an ",
        "upstream C library, add a deps/<name>/Makefile that builds it and writes ",
        "results.mk; the generated build discovers each deps directory, runs its ",
        "Makefile, and includes the result. The idiom is to compile upstream sources ",
        "directly with $(CC) $(CFLAGS) and archive them, never running the upstream's ",
        "own configure, as santoku-sqlite does. The results.mk rule must list Makefile ",
        "as a prerequisite, or editing the Makefile would rebuild nothing, so the build ",
        "stops with an error when it doesn't. Objects compile with -MMD -MP, so editing ",
        "a header recompiles every object that includes it.",
      }),
      runnable = false,
      code = [[
cflags = {
  "-I$(PWD)/deps/sqlite3/",
},
ldflags = {
  "$(PWD)/deps/sqlite3/sqlite-amalgamation-3490200/libsqlite3.a",
  "-lm",
},

results.mk: Makefile
	[ -f sqlite-amalgamation-$(V).zip ] || exit 1
	unzip sqlite-amalgamation-$(V).zip
	cd $(DIR) && $(CC) -c $(SQLITE_CFLAGS) $(CFLAGS) -o sqlite3.o sqlite3.c
	cd $(DIR) && $(AR) rcs libsqlite3.a sqlite3.o
	touch results.mk
]],
    },

    {
      title = "Headers from another rock: santoku.make.rock",
      desc = table.concat({
        "A C extension that includes another rock's headers lists that rock in ",
        "dependencies and adds rock.include(name) to cflags. include returns -I plus ",
        "incdir(name), a Makefile expression that resolves to the include directory of ",
        "the rock installed in the tree being built. The build stops with an error ",
        "naming the rock when it isn't installed there.",
      }),
      runnable = false,
      code = [[
local rock = require("santoku.make.rock")
return {
  type = "lib",
  env = {
    name = "my-lib",
    version = "0.0.1-1",
    cflags = { rock.include("santoku-monocypher") },
    dependencies = {
      "lua == 5.1",
      "santoku-monocypher >= 2.0.1, < 3.0.0",
    },
  },
}
]],
    },

    {
      title = "Vendoring with sha256 pins",
      desc = table.concat({
        "A deps Makefile never downloads. The archive path is declared data in ",
        "rules.include, so it flows through the build, test, and release-tarball file ",
        "lists like a tracked file, and a configure hook registers the producer. ",
        "vendor.fetch downloads to dest .. \".part\", renames on success, and verifies ",
        "the digest, discarding an existing file that fails. Omit sha256 on a new entry ",
        "and the fetch prints the computed digest to paste in, then exits non-zero. ",
        "Consumers never fetch: the archive ships inside the release tarball. The real ",
        "descriptors this distills: ",
        "https://github.com/birchpointswe/lua-santoku-sqlite/blob/master/make.lua and ",
        "https://github.com/birchpointswe/lua-santoku-mustache/blob/master/make.lua",
      }),
      runnable = false,
      code = [[
local fs = require("santoku.fs")
local vendor = require("santoku.make.vendor")
local spec = {
  file = "deps/sqlite3/sqlite-amalgamation-3490200.zip",
  url = "https://www.sqlite.org/2025/sqlite-amalgamation-3490200.zip",
  sha256 = "921fc725517a694df7df38a2a3dfede6684024b5788d9de464187c612afb5918",
}
return {
  env = {
    name = "santoku-sqlite",
    version = "2.2.0-1",
    dependencies = { "lua == 5.1" },
    rules = { include = { spec.file } },
    configure = function (submake, envs)
      local dest = fs.join(envs.root.build_dir, spec.file)
      submake.target({ dest }, { "make.lua" }, function ()
        vendor.fetch(spec, dest)
      end)
    end,
  },
}
]],
    },

    {
      title = "local_deps: sibling source rocks",
      desc = table.concat({
        "local_deps lists paths (typically git submodules) to lib projects that are ",
        "installed from source into every luarocks tree the build manages, before the ",
        "consuming rock. Reinstall is triggered by mtime changes under the dep's lib, ",
        "bin, deps, and res directories and its make files. A local dep must be a lib ",
        "project and must not declare local_deps of its own; do not also list it in ",
        "dependencies. A shared library is commonly a submodule of both an app ",
        "repository and its CLI repository.",
      }),
      runnable = false,
      code = [[
return {
  env = {
    name = "my-app",
    version = "0.0.1-1",
    dependencies = {
      "lua == 5.1",
      "santoku >= 2.0.0, < 3.0.0",
    },
    local_deps = {
      "submodules/my-shared-lib",
    },
  },
}
]],
    },

    {
      title = "build.dependencies: rocks for template time",
      desc = table.concat({
        "build.dependencies are installed once per env into a separate build-deps tree, ",
        "and that tree's paths are spliced into package.path around every template ",
        "render. A .tk file can then require them at generation time even though they ",
        "are not runtime deps. Declare santoku-web here so a ",
        "client/res/pre.tk.js can inline santoku.web.pwa.wrap_events at render time.",
      }),
      runnable = false,
      code = [[
return {
  env = {
    name = "my-app",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
    build = {
      dependencies = {
        "santoku-web >= 2.2.3, < 3.0.0",
      },
    },
  },
}
]],
    },

    {
      title = "Native and WASM variant flags",
      desc = table.concat({
        "One source tree, two toolchains. Top-level cflags and ldflags apply ",
        "everywhere; native and wasm blocks scope by variant, build and test scope by ",
        "phase, and the combined forms (build.wasm.ldflags, test.native.cflags, ...) ",
        "scope by both. WASM builds are selected with --wasm, land in ",
        "build/<env>-wasm, and the Makefile templates branch on the compiler being ",
        "emcc. santoku-web's Emscripten export flags are set in exactly these fields, and ",
        "https://github.com/birchpointswe/lua-santoku-learn/blob/master/make.common.lua ",
        "is a full real example: OpenMP and BLAS confined to native, wasm ldflags per ",
        "phase.",
      }),
      runnable = false,
      code = [[
return {
  env = {
    name = "my-native-lib",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
    cflags = { "-O2" },
    native = {
      cflags = { "-fopenmp" },
      ldflags = { "-fopenmp" },
    },
    build = { wasm = { ldflags = { "-sWASM_BIGINT" } } },
    test = { wasm = { ldflags = { "-sWASM_BIGINT" } } },
  },
}
]],
    },

    {
      title = "Choosing a wasm mechanism",
      desc = table.concat({
        "Four mechanisms make code behave differently, or not exist, under wasm, and ",
        "which one applies follows from what is actually different about the build. A ",
        "capability compiled out of a C extension is absent, so a nil check settles it. ",
        "A capability that exists and raises when called needs one invocation probe, ",
        "because presence reads as available. A module with its own wasm implementation ",
        "is a filename variant, selected while building rather than branched on at ",
        "runtime. Text that should not appear in a generated file at all is a template ",
        "gate, covered on the santoku-template tab under conditional sections with push ",
        "and pop.",
      }),
      runnable = false,
      lang = "text",
      code = [[
absent under wasm          gate on presence    if fs.hardlink then ... end
exists but always raises   probe once          local ok = pcall(io.popen, "true")
separate implementation    filename variant    lib/santoku/web/js.wasm.lua
must not be emitted        template gate       <% push(is_wasm) %> ... <% pop() %>
]],
    },

    {
      title = "Compiling a capability out of a C extension",
      desc = table.concat({
        "emcc defines __EMSCRIPTEN__, so a C extension can drop a function the platform ",
        "cannot support. Guard the body and the luaL_Reg entry together: an entry ",
        "without a body fails to link, a body without an entry is dead code. santoku-fs ",
        "does this for hardlink and symlink in lib/santoku/fs/posix.c, which is why ",
        "fs.hardlink is nil in this site's own wasm bundle and the fs tab feature-detects ",
        "before calling it. When a module must keep the function and change what it does, ",
        "guard inside the body, and let Lua see which build it got: santoku.sqlite.db ",
        "exposes a wasm field set from the same ifdef.",
      }),
      runnable = false,
      lang = "c",
      code = [[
#ifndef __EMSCRIPTEN__
int tk_fs_posix_hardlink (lua_State *L)
{
  lua_settop(L, 2);
  const char *oldpath = luaL_checkstring(L, 1);
  const char *newpath = luaL_checkstring(L, 2);
  if (link(oldpath, newpath) == -1)
    return tk_fs_posix_err(L, errno);
  return 0;
}
#endif

luaL_Reg tk_fs_posix_fns[] =
{
  { "mode", tk_fs_posix_mode },
#ifndef __EMSCRIPTEN__
  { "hardlink", tk_fs_posix_hardlink },
  { "symlink", tk_fs_posix_symlink },
#endif
  { "touch", tk_fs_posix_touch },
  { NULL, NULL }
};
]],
    },

    {
      title = "Gating a spec on the capability it needs",
      desc = table.concat({
        "One spec file runs under both toolchains, registering only the tests its target ",
        "supports. Gate on the capability rather than on the platform: with fs.hardlink ",
        "nil the suite is shorter under wasm and the spec never names emscripten. ",
        "santoku-fs gates its hardlink and symlink tests this way, which is what keeps ",
        "toku test and toku test --wasm both green on the same tree.",
      }),
      runnable = false,
      code = [[
local test = require("santoku.test")
local fs = require("santoku.fs")

if fs.hardlink then
  test("hardlink", function ()
    fs.writefile("test/res/hl_src.txt", "hello")
    fs.hardlink("test/res/hl_src.txt", "test/res/hl_dst.txt")
    assert(fs.readfile("test/res/hl_dst.txt") == "hello")
    fs.rm("test/res/hl_src.txt")
    fs.rm("test/res/hl_dst.txt")
  end)
end
]],
    },

    {
      title = "When the presence check lies: io.popen",
      desc = table.concat({
        "A presence check only answers for capabilities that are genuinely absent, and ",
        "io.popen is not one of them. toku builds its vendored Lua 5.1.5 for wasm with ",
        "make all under emmake and MYCFLAGS that do not define LUA_USE_POSIX, so ",
        "LUA_USE_POPEN is undefined and luaconf.h expands lua_popen to a luaL_error ",
        "reading 'popen' not supported; liolib.c registers popen regardless. io.popen is ",
        "therefore a function under emscripten that raises only when called, and a nil ",
        "check reports it as available. Probe it once at file scope and gate on the ",
        "result, not inside each test. The same shape covers anything whose failure is ",
        "deferred to the call: os.execute, host paths, spawning an interpreter.",
      }),
      runnable = false,
      code = [[
local test = require("santoku.test")

local spawn_ok, spawn_probe = pcall(io.popen, "true")
local can_spawn = spawn_ok and spawn_probe ~= nil
if can_spawn then
  spawn_probe:close()
end

if can_spawn then
  test("generators are seeded per process", function ()
    local f = io.popen("lua5.1 -e \"print(require('santoku.random').fast_random())\"")
    local out = f:read("*a")
    f:close()
    assert(out ~= "" and out ~= nil)
  end)
end
]],
    },

    {
      title = "Filename variants: .wasm. sources and specs",
      desc = table.concat({
        "A file named <name>.wasm.<ext> is chosen by the build, not by the running ",
        "program. The generated lib Makefile sets _WASM when CC contains emcc: native ",
        "builds filter %.wasm.lua, %.wasm.c and %.wasm.cpp out of the file list, wasm ",
        "builds keep them and strip the .wasm. infix when naming objects and install ",
        "targets, so lib/santoku/web/js.wasm.lua installs as santoku/web/js.lua and is ",
        "required as santoku.web.js. Specs follow the same rule in the project layer: ",
        "test/spec/**/*.wasm.lua is dropped from a native run, and under --wasm each one ",
        "is bundled to the stripped .js name. This is variant selection, not capability ",
        "gating. It says nothing about a file both targets share, and a variant with no ",
        "native counterpart is missing rather than stubbed when you build native. That is ",
        "how santoku-web ships: its browser runtime modules exist only as .wasm. files, ",
        "while the build-time pwa helpers, which templates require natively, are plain ",
        "sources alongside them.",
      }),
      runnable = false,
      lang = "text",
      code = [[
lib/santoku/web/js.wasm.lua          installs as santoku/web/js.lua, wasm builds only
test/spec/santoku/web/dom.wasm.lua   runs under toku test --wasm, skipped natively

ifneq (,$(findstring emcc,$(CC)))
_WASM = 1
endif

ifdef _WASM
LIB_LUA = $(shell find * -name '*.lua')
else
LIB_LUA = $(filter-out %.wasm.lua, $(shell find * -name '*.lua'))
endif

INST_LUA = $(patsubst %.wasm.lua,%.lua,$(addprefix $(INST_LUADIR)/, $(LIB_LUA)))
]],
    },

    {
      title = "Per-file rules",
      desc = table.concat({
        "rules.exclude, rules.copy, and rules.template are Lua patterns that drop ",
        "files, force a copy, or force templating. rules.include is literal paths ",
        "declared into the file set even when absent from the tree (they must gain a ",
        "producer target or the build fails). Pattern keys map matched files to extra ",
        "compiler flags, injected as dedicated Makefile rules for just those objects.",
      }),
      runnable = false,
      code = [[
return {
  env = {
    name = "my-lib",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
    rules = {
      exclude = { "%.draft%.lua$" },
      copy = { "^res/raw/" },
      template = { "^res/index%.css$" },
      include = { "deps/upstream/upstream-1.0.tar.gz" },
      ["capi%.c$"] = { cflags = { "-DFAST_PATH" } },
    },
  },
}
]],
    },

    {
      title = "Environment profiles: make.common.lua",
      desc = table.concat({
        "Real projects keep shared config in make.common.lua and override per profile: ",
        "make.prod.lua merges its overrides over the common table, and because merge ",
        "never overwrites existing keys, the profile's values win. toku --env prod ",
        "selects make.prod.lua and builds under build/prod; make.common.lua is tracked ",
        "as a config dependency, so editing it restales every rendered target. In a ",
        "profile file the common table comes from fs.runfile(\"make.common.lua\").",
      }),
      code = [[
local tbl = require("santoku.table")
local common = {
  env = {
    name = "my-app",
    version = "0.0.1-1",
    client = { files = true, verbose = true },
    nginx = { domain = "localhost", port = "8080" },
  },
}
local prod = tbl.merge({
  env = {
    client = { files = false },
    nginx = { port = "443" },
  },
}, common)
print("client.files:", prod.env.client.files)
print("client.verbose:", prod.env.client.verbose)
print("nginx:", prod.env.nginx.domain, prod.env.nginx.port)
return prod.env.name
]],
    },

    {
      title = "toku init --web: the web scaffold",
      desc = table.concat({
        "A web project pairs a client tree (compiled to WebAssembly) with a server ",
        "tree (OpenResty Lua) plus shared root lib and res. client/bin holds the page ",
        "entry points, client/static the templated HTML, server/nginx.tk.conf the ",
        "server config template, and res/ the assets both sides render. The layout ",
        "below is abridged to the files that matter.",
      }),
      runnable = false,
      code = [[
$ toku init --web --name my-app

my-app/client/bin/bundle.lua
my-app/client/lib/my-app/db.tk.lua
my-app/client/lib/my-app/main.lua
my-app/client/res/pre.tk.js
my-app/client/static/index.html
my-app/client/test/spec/my-app.lua
my-app/make.lua
my-app/res/client/migrations/0.0.1.sql
my-app/res/server/migrations/0.0.1.sql
my-app/server/lib/my-app/db.tk.lua
my-app/server/lib/my-app/web/init.lua
my-app/server/lib/my-app/web/sync.lua
my-app/server/nginx.tk.conf
my-app/server/test/spec/my-app.lua
]],
    },

    {
      title = "The web descriptor: server, client, nginx",
      desc = table.concat({
        "server and client carry separate dependency sets because the client is ",
        "compiled to WASM under emcc while the server runs native under OpenResty. ",
        "nginx is free-form context handed to your own server/nginx.tk.conf template, ",
        "except modules, which the engine resolves to installed lua_modules paths. The ",
        "whole project builds a lib project per component.",
      }),
      runnable = false,
      code = [[
return {
  env = {
    name = "my-app",
    version = "0.0.1-1",
    server = {
      dependencies = {
        "lua == 5.1",
        "santoku-resty >= 2.0.0, < 3.0.0",
        "santoku-sqlite >= 4.0.6, < 5.0.0",
      },
    },
    client = {
      dependencies = {
        "lua == 5.1",
        "santoku-web >= 2.2.3, < 3.0.0",
      },
    },
    nginx = {
      ssl_self_signed = true,
      domain = "localhost",
      port = "8443",
      workers = "auto",
      modules = {
        "my-app.web.init",
        "my-app.web.sync",
      },
    },
  },
}
]],
    },

    {
      title = "Client pages: client/bin to WASM",
      desc = table.concat({
        "Every client/bin/*.lua is one page: it is bundled with santoku-bundle under ",
        "emcc into page.js plus page.wasm in the public dist. bundle_mods preloads ",
        "modules the bundler cannot see statically. client.files = true keeps modules ",
        "as loose files for fast dev rebuilds; false, for production, strips them ",
        "with luac and embeds the bytecode in the binary. Pattern keys under ",
        "client.rules add per-page link flags, here a pre-js and a CSP-friendly flag ",
        "for the bundle page.",
      }),
      runnable = false,
      code = [[
client = {
  files = false,
  public = { "roboto.woff2", "index.css", "favicon.svg" },
  bundle_mods = { "santoku.mtx" },
  dependencies = {
    "lua == 5.1",
    "santoku >= 2.0.0, < 3.0.0",
    "santoku-web >= 2.2.3, < 3.0.0",
  },
  rules = {
    ["bundle$"] = {
      ldflags = {
        "--pre-js", "res/pre.js",
        "-sDYNAMIC_EXECUTION=0",
      },
    },
  },
},
]],
    },

    {
      title = "client.public and the configure hook",
      desc = table.concat({
        "File sets are declared data; configure only wires up producers. client.public ",
        "declares the public filenames your hook generates (fonts, compiled CSS, ",
        "icons), and they join the hashed-asset manifest exactly like walked static ",
        "files. The hook runs once per environment (main and test) with the merged ",
        "envs; on web projects envs has root, server, and client. Attach each product ",
        "to client.target so the build waits for it.",
      }),
      runnable = false,
      code = [[
local fs = require("santoku.fs")
local sys = require("santoku.system")
return {
  env = {
    name = "my-app",
    version = "0.0.1-1",
    client = {
      public = { "index.css", "favicon.svg" },
      dependencies = { "lua == 5.1", "santoku-web >= 2.2.3, < 3.0.0" },
    },
    server = {
      dependencies = { "lua == 5.1", "santoku-resty >= 2.0.0, < 3.0.0" },
    },
    configure = function (submake, envs)
      local client = envs.client
      if not client then
        return
      end
      local css_out = fs.join(client.public_dir, "index.css")
      local css_in = fs.join(client.build_dir, "res/index.css")
      submake.target({ client.target }, { css_out })
      submake.target({ css_out }, { css_in }, function ()
        sys.execute({ "tailwindcss", "-i", css_in, "-o", css_out, "--minify" })
      end)
      local icon_out = fs.join(client.public_dir, "favicon.svg")
      local icon_src = fs.join(client.root_dir, "res/favicon.svg")
      submake.target({ client.target }, { icon_out })
      submake.target({ icon_out }, { icon_src }, function (ts, ds)
        fs.writefile(ts[1], fs.readfile(ds[1]))
      end)
    end,
  },
}
]],
    },

    {
      title = "Asset hashing and the PWA pipeline",
      desc = table.concat({
        "Static files and declared public files are staged, content-hashed into names ",
        "like index.a1b2c3d4e5f6.html, and copied into the public dist with every ",
        "textual cross-reference rewritten (the manifest iterates until it converges). ",
        "The mapping is saved as hash-manifest.lua and exposed to templates as hashed(), ",
        "which emits a placeholder resolved from the converged manifest, so every shipped ",
        "file's name is the hash of the bytes it ships. A pwa block, if you add one, is ",
        "free-form data that ",
        "santoku-make does not interpret: nothing in the engine reads it, and the same ",
        "is true of any ssl_ keys. It is useful as one place to keep the values your ",
        "own configure hook and templates pass to the santoku.web.pwa helpers, the ",
        "minification transforms among them. server.preserve_public protects paths like ",
        ".well-known from the dist rebuild.",
      }),
      runnable = false,
      code = [[
server = {
  preserve_public = { "%.well%-known" },
},
client = {
  pwa = {
    title = "My App",
    name = "My App",
    description = "...",
    theme_color = "#262626",
    background_color = "#262626",
    transforms = {
      js = build.minify_js,
      css = build.minify_css,
      html = lp.minify_html,
    },
  },
},
]],
    },

    {
      title = "server/nginx.tk.conf: rendering the server config",
      desc = table.concat({
        "The engine renders your server/nginx.tk.conf into nginx.conf and a foreground ",
        "variant, with a context holding your nginx block merged with daemon, pid, and ",
        "log settings, the resolved module paths, lua_package_path and cpath for the ",
        "installed lua_modules, and the hashed() lookup. One technique, shown below: ",
        "keep the actual nginx directives in a separate mustache file under res and ",
        "render them with that context, so hashed entry points land directly in the ",
        "config.",
      }),
      runnable = false,
      code = [[
<%
  local ctx = nginx
  ctx.index_hashed = hashed("index.html")
  ctx.sw_hashed = hashed("bundle.js")
  return require("santoku.mustache")(readfile("res/nginx.conf"))(ctx)
%>
]],
    },

    {
      title = "The web loop: build, start, test, stop",
      desc = table.concat({
        "toku build --test assembles the test environment (server rock installed, ",
        "pages bundled, assets hashed); toku start runs the generated run.sh in the ",
        "dist dir, backgrounded with a server.pid, or in the foreground with --fg. ",
        "toku test runs root specs as a lib project, then stops any running server, ",
        "starts the test server, and runs the server suite against it; --root, ",
        "--client, and --server select components. toku stop signals the pid files. ",
        "clean scopes by component and can preview with --dry-run.",
      }),
      runnable = false,
      code = [[
$ toku build --test
$ toku start --test
$ toku test
$ toku test --server --show-logs
$ toku stop
$ toku build --env prod
$ toku start --env prod --fg
$ toku clean --client --wasm
$ toku clean --all --dry-run
]],
    },

  },

}

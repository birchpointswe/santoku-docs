return {

  intro = table.concat({
    "santoku-bundle turns a Lua entry script and everything it requires into a single ",
    "generated C program, then hands that to a C compiler: cc for native executables, ",
    "emcc for WebAssembly (the wasm running this page is its output). It is the last ",
    "stage of the toku build flow: santoku-make calls it to ship native binaries, ",
    "bundled test suites, and web clients. The library exports exactly one function, ",
    "bundle(infile, outdir, opts). Dependencies are found by scanning source text for ",
    "string-literal require calls, so dynamic requires need opts.mods and unresolvable ",
    "names need opts.ignores. This tab is a guided tour of the whole anatomy: the merge, ",
    "the scanner and its blind spots, module resolution, C modules, bytecode and ",
    "embedding, the build-integration options, and the exact calls that produce native ",
    "toku binaries and this site. Bundling needs the real filesystem and a C toolchain, ",
    "so most examples are shown for reading; a few in-page demos exercise the plain-Lua ",
    "mechanisms bundle is built on.",
  }),

  examples = {

    {
      title = "One call, three artifacts",
      desc = table.concat({
        "bundle(infile, outdir, opts) scans, merges, generates C, and compiles. The ",
        "output prefix defaults to the entry basename with extensions stripped, and the ",
        "full compile command is printed before it runs. This is the anchor test from ",
        "the repo, linking against the host Lua found via luarocks config.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local sys = require("santoku.system")
local str = require("santoku.string")
local fs = require("santoku.fs")
local incdir = sys.sh({ "luarocks", "config", "variables.LUA_INCDIR" })()
local libdir = sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR" })()
local libfile = sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR_FILE" })()
local libname = str.stripprefix(fs.stripextension(libfile), "lib")
bundle("test/res/bundle/test.lua", "test/res/bundle/test", {
  flags = { "-I", incdir, "-L", libdir, "-l", libname, "-l", "m" }
})
print("compile command echoed by bundle, then three artifacts:")
print("test.lua", fs.exists("test/res/bundle/test/test.lua"))
print("test.c", fs.exists("test/res/bundle/test/test.c"))
print("test", fs.exists("test/res/bundle/test/test"))
return "merged lua, generated c, linked executable"
]],
    },

    {
      title = "The mechanism: package.preload",
      desc = table.concat({
        "The merged Lua file has a fixed shape: one package.preload assignment per ",
        "discovered module, a require line for each opts.mods entry, then the entry ",
        "source appended raw. preload is stock Lua 5.1: nothing here touches the ",
        "filesystem, the entire trick is table assignment.",
      }),
      runnable = false,
      code = [[
package.preload["demo.words"] = function ()
  return { pick = function () return "bundled" end }
end
package.preload["demo.app"] = function ()
  local words = require("demo.words")
  return "hello from a " .. words.pick() .. " module"
end
print(require("demo.app"))
print("bundle writes exactly this shape into <outdir>/<prefix>.lua:")
print("preload entries first, opts.mods requires next, entry source last")
return require("demo.app")
]],
    },

    {
      title = "The require scanner, in miniature",
      desc = table.concat({
        "The real scanner is an lpeg grammar over raw source text: the require keyword ",
        "guarded against identifier characters, optional parentheses, and a string ",
        "literal, while comments and string bodies are skipped. The naive pattern below ",
        "shows the literal-only idea, and its false positives show why the grammar ",
        "bothers skipping comments and strings.",
      }),
      code = [[
local src = table.concat({
  "local arr = require(\"santoku.array\")",
  "local str = require \"santoku.string\"",
  "local required_elsewhere = 1",
  "-- require(\"santoku.commented\")",
  "local doc = \"call require(\\\"santoku.quoted\\\") yourself\"",
  "local dyn = require(\"santoku.\" .. \"joined\")",
}, "\n")
local naive = {}
for mod in src:gmatch("require%s*%(?%s*[\"']([%w%.]+)[\"']") do
  naive[#naive + 1] = mod
end
print("naive pattern finds: " .. table.concat(naive, ", "))
print("the real grammar finds only: santoku.array, santoku.string")
print("it skips the comment and the string body, and required_elsewhere")
print("never matches because the keyword must end at a non-identifier")
print("the concatenation never reaches one literal, so it is invisible to both")
return naive
]],
    },

    {
      title = "Blind spots, and mods to fill them",
      desc = table.concat({
        "The scan is textual, not semantic: a require in dead code is still bundled, ",
        "and a require built from variables or concatenation is invisible. opts.mods ",
        "forces modules in: each entry is resolved, preloaded, and required ahead of ",
        "the entry. In make.lua descriptors this surfaces as client.bundle_mods: ",
        "this docs site lists 28 modules so in-page snippets can require them at ",
        "runtime.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")
fs.mkdirp("bin")
fs.writefile("bin/main.lua", table.concat({
  "local name = \"myapp.backend.\" .. (os.getenv(\"BACKEND\") or \"memory\")",
  "local backend = require(name)",
  "if false then require(\"myapp.debugview\") end",
  "backend.start()",
}, "\n"))
bundle("bin/main.lua", "build", {
  mods = { "myapp.backend.memory", "myapp.backend.sqlite" },
})
print("require(name) has no string literal, so the scan cannot see it")
print("require(\"myapp.debugview\") sits in dead code but is bundled anyway")
print("both backends ride in via mods and name resolves at runtime")
return fs.exists("build/main")
]],
    },

    {
      title = "ignores: skipping unresolvable names",
      desc = table.concat({
        "Any scanned name that resolves through neither path nor cpath is an error. ",
        "ignores exempts a name: it is neither bundled nor recursed into. The classic ",
        "case is debug, a Lua built-in with no file on LUA_PATH; every toku bundling ",
        "flow passes ignores = { \"debug\" } by default.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")
fs.mkdirp("bin")
fs.writefile("bin/tool.lua", table.concat({
  "local dbg = require(\"debug\")",
  "print(dbg.traceback())",
}, "\n"))
bundle("bin/tool.lua", "build", {
  ignores = { "debug" },
})
print("debug is provided by luaL_openlibs in the generated C, so the")
print("require succeeds at runtime without a file ever being bundled")
return fs.exists("build/tool")
]],
    },

    {
      title = "Resolution: path, cpath, Lua vs C",
      desc = table.concat({
        "Each scanned name goes through env.searchpath twice: opts.path (default ",
        "LUA_PATH) classifies it as a Lua module, then opts.cpath (default LUA_CPATH) ",
        "as a C module. Lua modules are read and recursively scanned; C modules are ",
        "not. A name resolving nowhere raises the searchpath error.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("bin/main.lua", "build", {
  path = "build/lua_modules/share/lua/5.1/?.lua;build/lua_modules/share/lua/5.1/?/init.lua",
  cpath = "build/lua_modules/lib/lua/5.1/?.so",
})
print("santoku.fs found via path: read, merged, scanned recursively")
print("santoku.fs.posix found via cpath: linked, never scanned")
print("toku builds pass the project's own lua_modules tree here, so a")
print("bundle is hermetic: only what the build tree installed can ride in")
return "every module classified as lua or c"
]],
    },

    {
      title = "C modules become linked symbols",
      desc = table.concat({
        "A C module cannot be merged as source. Instead bundle derives its luaopen ",
        "symbol (dots swapped for underscores), declares it in the generated C, ",
        "registers it in package.preload before the entry runs, and appends the ",
        "resolved shared object to the compile command.",
      }),
      code = [[
local mods = { "santoku.fs.posix", "santoku.string.base", "santoku.web.val" }
for i = 1, #mods do
  local sym = "luaopen_" .. string.gsub(mods[i], "%.", "_")
  print(mods[i] .. "  ->  " .. sym)
end
print("generated C declares each: int luaopen_santoku_fs_posix(lua_State *L);")
print("then registers it in package.preload before the bytecode runs")
return "luaopen_" .. string.gsub(mods[1], "%.", "_")
]],
    },

    {
      title = "luac: precompiling the merge",
      desc = table.concat({
        "opts.luac precompiles the merged Lua to bytecode before embedding. true uses ",
        "\"luac -s -o %output %input\"; a string is a template with %input and %output ",
        "substituted, then split on whitespace and executed, so keep spaces out of the ",
        "paths. The stripped bytecode is what ships, shrinking the binary and skipping ",
        "the parse at startup.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")
bundle("bin/main.lua", "build", {
  luac = true,
  binary = true,
})
print("main.lua", fs.exists("build/main.lua"))
print("main.luac", fs.exists("build/main.luac"))
print("main.c", fs.exists("build/main.c"))
print("main", fs.exists("build/main"))
print("four artifacts now: merge, bytecode, generated C, executable")
return fs.exists("build/main")
]],
    },

    {
      title = "The luac template, run in the page",
      desc = table.concat({
        "The string form of opts.luac is a santoku.string interp template. The same ",
        "substitution bundle performs, runnable here.",
      }),
      code = [[
local str = require("santoku.string")
local cmd = str.interp("build/lua-5.1.5/bin/luac -s -o %output %input", {
  input = "build/main.lua",
  output = "build/main.luac",
})
print(cmd)
return cmd
]],
    },

    {
      title = "base64 vs binary embedding",
      desc = table.concat({
        "By default the bytecode is embedded as a base64 C string and decoded by ",
        "generated C at program start. binary = true writes a raw byte array instead, ",
        "16 bytes per generated line, loaded directly with luaL_loadbuffer. The same ",
        "transformations, in page, with santoku.string.",
      }),
      code = [[
local str = require("santoku.string")
local chunk = "print('hello from inside the executable')"
local b64 = str.to_base64(chunk)
print(b64)
print("roundtrip ok: " .. tostring(str.from_base64(b64) == chunk))
local bytes = {}
for i = 1, 12 do
  bytes[#bytes + 1] = string.format("0x%02x", string.byte(chunk, i))
end
print(table.concat(bytes, ",") .. ", ...")
print("binary = true writes that array shape into the generated C")
return b64
]],
    },

    {
      title = "env: baked-in environment variables",
      desc = table.concat({
        "opts.env is a list of {name, value} pairs that become setenv calls at the very ",
        "top of the generated main, before the Lua state exists. The wasm test flow ",
        "bakes the project's WASM flag into every bundled spec this way.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("bin/main.lua", "build", {
  env = {
    { "LOG_LEVEL", "info" },
    { "TK_MYAPP_WASM", "1" },
  },
})
print("generated main begins:")
print("  setenv(\"LOG_LEVEL\", \"info\", 1);")
print("  setenv(\"TK_MYAPP_WASM\", \"1\", 1);")
print("values are compiled into the binary: build-variant flags, not secrets")
return "environment fixed at compile time"
]],
    },

    {
      title = "close: three state lifecycles",
      desc = table.concat({
        "Omitted, opts.close registers an atexit handler that closes the lua_State. ",
        "true closes it explicitly at the end of main. false never closes it, which ",
        "the wasm builds pair with -sNO_EXIT_RUNTIME so the state outlives main and ",
        "keeps handling browser events: how this page is still running.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("bin/main.lua", "build", {})
print("close omitted: atexit(__tk_bundle_atexit) closes the state")
bundle("bin/main.lua", "build", { close = true })
print("close true: lua_close(L) at the end of main")
bundle("bin/main.lua", "build", { close = false })
print("close false: never closed; main returns and the state lives on")
return "pick the lifecycle to match the runtime"
]],
    },

    {
      title = "deps: .d sidecars for the build graph",
      desc = table.concat({
        "opts.deps writes a make-style dependency file next to the output: the target ",
        "followed by every resolved Lua and C source, then a second rule making the .d ",
        "file itself depend on the entry. depstarget overrides the target name. The ",
        "santoku-make engine folds target .. \".d\" sidecars into staleness, so editing ",
        "any bundled module restales the executable on the next toku build.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")
bundle("bin/main.lua", "build", {
  deps = true,
})
print(fs.readfile("build/main.d"))
print("line one: build/main: every resolved source file")
print("line two: build/main.d: bin/main.lua")
return fs.exists("build/main.d")
]],
    },

    {
      title = "cc and flags: the compile command",
      desc = table.concat({
        "opts.cc defaults to the CC environment variable, then plain cc. The command ",
        "is assembled as: cc, the generated .c file, opts.flags in order, every ",
        "resolved C module file, then -o and the output path, and it is printed in ",
        "full before it runs, so failed builds are reproducible by hand.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("bin/main.lua", "build", {
  cc = "musl-gcc",
  flags = { "-static", "-O2", "-I", "/usr/include/lua5.1", "-llua5.1", "-lm" },
})
print("echoed before execution:")
print("musl-gcc build/main.c -static -O2 -I /usr/include/lua5.1 -llua5.1 -lm")
print("  <each resolved .so> -o build/main")
return "one self-contained binary"
]],
    },

    {
      title = "WASM via emcc: how this page is built",
      desc = table.concat({
        "The web project layer of santoku-make bundles each client page with this call ",
        "shape. This site's entry, client/bin/bundle.tk.lua, is one line: return ",
        "require(\"docs.main\"). The scanner follows that literal into docs.content and ",
        "every tab module, including the one you are reading. emcc emits the page JS ",
        "plus a .wasm beside it, and the --pre-js flags splice in the vendored ",
        "highlighter and editor.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local wasm_build = "build/client/build/default-wasm/build"
local client_bundle_mods = {
  "santoku.array", "santoku.string", "santoku.table", "santoku.web.val",
  "santoku.sqlite", "santoku.learn.tokenizer",
}
bundle(wasm_build .. "/bin/bundle.lua", "build/client/bundler-post", {
  cc = "emcc",
  luac = wasm_build .. "/lua-5.1.5/bin/luac -s -o %output %input",
  binary = true,
  mods = client_bundle_mods,
  ignores = { "debug" },
  path = wasm_build .. "/lua_modules/share/lua/5.1/?.lua",
  cpath = wasm_build .. "/lua_modules/lib/lua/5.1/?.so",
  flags = {
    "-Oz", "-sASSERTIONS=0", "--closure", "0", "-sMALLOC=emmalloc",
    "-sTEXTDECODER=2", "-sNO_EXIT_RUNTIME", "-sEVAL_CTORS",
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. wasm_build .. "/lua-5.1.5/include",
    "-L" .. wasm_build .. "/lua-5.1.5/lib",
    "-llua", "-lm",
    "--pre-js", "vendor/prism-core.min.js",
    "--pre-js", "vendor/prism-lua.min.js",
    "--pre-js", "vendor/codejar-global.js",
  },
})
print("this site's real mods list has 28 entries in make.common.lua, the")
print("modules the runnable examples on these pages may require")
print("outprefix defaults to bundle, so emcc emits bundle and bundle.wasm")
return "the program rendering this sentence"
]],
    },

    {
      title = "The matched luac: Lua 5.1.5 under emscripten",
      desc = table.concat({
        "Bytecode must come from a luac matching the runtime it will run in, so ",
        "santoku.make.wasm builds Lua 5.1.5 itself: it fetches the lua.org tarball with ",
        "a pinned sha256 and compiles it under emmake. bin/lua and bin/luac come out as ",
        "wasm programs wrapped in sh scripts that exec node, so the luac feeding the ",
        "bundle is bit-for-bit the same Lua build as the page runtime.",
      }),
      runnable = false,
      code = [[
local wasm = require("santoku.make.wasm")
local make = require("santoku.make")
local m = make()
local lua_dir, lua_ok = wasm.setup_lua(m.target, "build/client/build/default-wasm/build")
m.build({ lua_ok }, 1)
print("built with MYCFLAGS -w -flto -Oz and MYLDFLAGS including")
print("-sSINGLE_FILE -lnodefs.js -lnoderawfs.js")
print(table.concat(wasm.get_bundle_flags(lua_dir, "build", {}, {}), " "))
print("get_bundle_flags is the standard emcc flag set the project layers")
print("hand to bundle, sized -Oz for shipping")
return lua_dir
]],
    },

    {
      title = "files mode: an embedded VFS instead of a merge",
      desc = table.concat({
        "With opts.files there is no merge and no luac: every resolved module ships as ",
        "its own file via emcc --embed-file flags, with the longest shared path prefix ",
        "stripped so VFS paths stay short. The generated main points package.path at ",
        "the embedded /lua_modules tree and runs the entry with luaL_dofile from its ",
        "VFS path. Tracebacks keep real filenames, so the web layer switches to this ",
        "mode via client.files when debuggability beats size.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("client/init.lua", "build/client", {
  cc = "emcc",
  files = true,
  mods = { "docs.main" },
  ignores = { "debug" },
  flags = { "-sALLOW_MEMORY_GROWTH", "-llua", "-lm" },
})
print("each module becomes: --embed-file /abs/path/mod.lua@/vfs/path/mod.lua")
print("errors now say client/init.lua:12 instead of bundle:48213")
return "a virtual filesystem instead of one merged chunk"
]],
    },

    {
      title = "Shipping native tools: toku install --bundled",
      desc = table.concat({
        "The library project layer bundles every script in bin/ into a standalone ",
        "executable. CLI options --bundle-cc, --bundle-flags, --bundle-mods, and ",
        "--bundle-ignores feed straight into opts (mods and ignores comma-separated, ",
        "debug always ignored). Each executable is copied to bin/ under --prefix, ",
        "else $PREFIX, else $HOME/.local, and chmod +x: no Lua modules on disk and no ",
        "LUA_PATH, though the binary still links the shared Lua library and whatever ",
        "system libraries your dependencies pull in.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")
local str = require("santoku.string")
for fp in fs.files("bin") do
  if str.match(fp, "%.lua$") then
    bundle(fp, "build/bundled", {
      ignores = { "debug" },
      path = "build/lua_modules/share/lua/5.1/?.lua",
      cpath = "build/lua_modules/lib/lua/5.1/?.so",
      outprefix = fs.stripextensions(fs.basename(fp)),
    })
  end
end
print("this loop is what toku install --bundled runs after install-deps")
print("with --wasm it emits <name>.js plus a sh wrapper that execs node")
return "standalone tools from bin/ scripts"
]],
    },

    {
      title = "Bundled test suites under node",
      desc = table.concat({
        "When a project builds for wasm, toku test bundles every spec with emcc and ",
        "runs the result under node. The test flag set trades size for diagnostics: ",
        "-sASSERTIONS on, -sSINGLE_FILE inlines the wasm into one runnable .js, and ",
        "nodefs plus noderawfs mount the real filesystem inside the VM so specs read ",
        "fixtures normally. close = false leaves the state open, and the baked env ",
        "pair lets specs branch on the wasm build.",
      }),
      runnable = false,
      code = [[
local bundle = require("santoku.bundle")
bundle("test/bundler-pre/test/spec/santoku/bundle.lua", "test/bundler-post/test/spec/santoku", {
  cc = "emcc",
  outprefix = "bundle.js",
  close = false,
  ignores = { "debug" },
  env = { { "TK_BUNDLE_WASM", "1" } },
  flags = {
    "-sASSERTIONS", "-sALLOW_MEMORY_GROWTH",
    "-sSINGLE_FILE", "-lnodefs.js", "-lnoderawfs.js",
    "-Ibuild/lua-5.1.5/include", "-Lbuild/lua-5.1.5/lib",
    "-llua", "-lm",
  },
})
print("node test/bundler-post/test/spec/santoku/bundle.js runs the suite:")
print("the same specs, compiled to wasm, testing the target for real")
return "toku test, but the suite itself is a wasm program"
]],
    },

  },

}

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
    "This is the shortest path from nothing to a published Lua rock. Everything ",
    "here assumes toku is installed and its mandatory one-time toku setup has run, ",
    "which is the Install tab: setup-toku.sh does both, and toku doctor confirms ",
    "it. Beyond toku, decide how you get the rest of the toolchain: install it on ",
    "your machine, or run toku from the container image santoku-make ships, with ",
    "your code mounted in. Both are covered first, and everything after that is ",
    "identical either way. Every ",
    "file shown below is the real output of toku init, reproduced here straight from ",
    "the boilerplate the CLI ships, so what you read is exactly what you get. The ",
    "example project is called my-lib; toku init substitutes your own name ",
    "everywhere, including inside file contents and directory names. Work through ",
    "it in order: toolchain, scaffold, the development loop, then the descriptor, ",
    "the code, the tests, and publishing.",
  }),

  examples = {

    {
      title = "Option one: install the toolchain",
      desc = table.concat({
        "A library project needs far less than a web one: no Emscripten, no ",
        "OpenResty, no node. The first line is the mandatory one-time step; ",
        "setup-toku.sh from the Install tab already ran it. The rest must be on ",
        "PATH, and the build fails at the first one it cannot find, with the error ",
        "coming from that tool rather than from toku.",
      }),
      runnable = false,
      lang = "text",
      code = [[
toku setup        # mandatory, once; done by setup-toku.sh (the Install tab)
luarocks          # invoked by toku; the managed toolchain ships its own
cc and make       # compile the C sources in the rock and in its dependencies
git               # toku init runs git init; toku release tags and pushes
gh                # only for toku release: it creates the GitHub release that
                  # hosts the tarball the rockspec points at. Authenticate it
                  # first with gh auth login
luacheck          # optional: toku test runs it when it is on PATH
inotifywait       # optional: toku test --iterate needs it and errors without it
]],
    },

    {
      title = "Option two: run toku from the container image",
      desc = table.concat({
        "santoku-make ships an image carrying that toolchain, so the alternative to ",
        "the list above is installing nothing but a container runtime. Your code ",
        "stays on your machine and is mounted at /app; only the tooling lives in the ",
        "container, so the build tree lands in your working directory exactly as it ",
        "would locally. Build the image once from a lua-santoku-make checkout, then ",
        "use the wrapper anywhere you would type toku. Everything after the double ",
        "dash goes to toku, and anything before it goes to the container runtime. ",
        "Podman keeps file ownership yours automatically; docker does not, so pass ",
        "-u if root-owned build output would bother you. toku-lib is the image for ",
        "library projects; a project with a client directory wants toku-web instead, ",
        "which is the same wrapper over a much larger image. Both toku-lib.sh and ",
        "toku-web.sh are one-line shims over a shared toku-container.sh that sits ",
        "beside them, so copy all three out of the checkout, not just the one you ",
        "invoke. Note that plain install has nothing to install into: the container is ",
        "--rm, and under podman you run as your own uid against a root-owned rocks ",
        "tree, so it fails on permissions. Bundle to the mounted directory instead.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ docker build -t toku-lib -f toku-lib.dockerfile .

$ ./toku-lib.sh -- test
$ ./toku-lib.sh -- install --bundled --prefix /app/out
$ ./toku-lib.sh -- pack

# before the --, the wrapper's own flags first, then runtime flags
#   -c docker | -c podman   force a runtime, otherwise docker then podman
#   -n                      print the command it would run, and exit
#   -u "$(id -u):$(id -g)"  passed through; docker only, keeps output yours
#   -i <image>              override the image name (or set TOKU_IMAGE)
]],
    },

    {
      title = "Scaffold a library project",
      desc = table.concat({
        "toku init creates a complete, already-working rock: a Lua module, a C ",
        "extension, an executable, a spec, and SQL migrations. It runs git init ",
        "unless you pass git = false through the API. The name must be lowercase ",
        "letters, digits and hyphens, starting with a letter. A hyphenated name splits ",
        "in two: the rock and the executable keep the hyphen, while the Lua module and ",
        "the C entry point use underscores, because luaopen_my-lib_capi is not a valid ",
        "C identifier. So my-lib publishes as the rock my-lib and is required as ",
        "my_lib. Use --here to scaffold into the current directory using its name.",
      }),
      runnable = false,
      lang = "text",
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
      title = "Build it and test it",
      desc = table.concat({
        "toku test --iterate is the expected day-to-day loop for a library, and the ",
        "one the framework is developed with. Run it against the fresh scaffold ",
        "before you change anything, then leave it running in one pane and edit in ",
        "another. (--show-logs is the web-project equivalent addition and does not ",
        "apply to libraries; passing it here is an error rather than a silent no-op.) ",
        "Underneath, toku test renders sources into build/default/test, ",
        "luarocks-makes them into a private lua_modules there, runs the specs, then ",
        "runs luacheck if it is on PATH. Because the test tree is a real installed ",
        "rock, specs see exactly what users will. toku install builds the shippable ",
        "tree and installs it into your active rocks tree. toku exec runs any command ",
        "inside the test environment with LUA_PATH and LUA_CPATH already pointed at ",
        "it.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku test --iterate                # the expected dev loop: leave this running

$ toku test                          # render, install deps, run specs, luacheck
$ toku test --single test/spec/my_lib.lua
$ toku test -m core -s               # filter by pattern, stop at first failure
$ toku test --lua luajit             # run the specs under a different interpreter
$ toku install                       # install into the active rocks tree
$ toku exec -- lua -e 'print(require("my_lib"))'   # note the --, toku parses -e otherwise
]],
    },

    scaffolded("lib", "make.lua",
      "make.lua: the whole descriptor",
      table.concat({
        "The descriptor is plain Lua returning a table with one env field, and it is ",
        "the only configuration a library needs. name and version feed the generated ",
        "rockspec. dependencies passes through to luarocks verbatim, and ",
        "test.dependencies adds rocks the test tree needs but the shipped rock does ",
        "not. cflags reaches the C compiler for any C sources; note that it locates ",
        "santoku's headers by asking luarocks where the rock lives rather than ",
        "hardcoding a path. This is everything toku init gives you, and it is enough to ",
        "build, test and install locally. Publishing takes two small edits to fields ",
        "that are already there: see the publishing example below.",
      })),

    scaffolded("lib", "lib/%m.tk.lua",
      "The library module, and what .tk means",
      table.concat({
        "Any file with .tk in its name is a build-time template: it is rendered by ",
        "santoku-template before it is installed, with the descriptor's env available ",
        "as globals, and the .tk is stripped from the output name. So this file ships ",
        "as lib/my_lib.lua. That is how build-time constants reach runtime code ",
        "without a config file. A file without .tk is copied verbatim, so use ",
        "templates only where you need them.",
      })),

    {
      title = "Editor support for .tk templates",
      desc = table.concat({
        "A .tk file is two languages at once: the outer layer is toku template syntax, ",
        "and the inner layer is whatever the remaining extension names, so main.tk.lua ",
        "is Lua inside toku and index.tk.html is HTML inside toku. ",
        "https://github.com/birchpointswe/tree-sitter-toku is a tree-sitter grammar ",
        "that models exactly that, and the injection below is what makes the inner ",
        "language highlight correctly: it derives the inner filetype by stripping .tk ",
        "from the filename and matching what is left. This is a working Neovim setup; ",
        "grammars for other editors are welcome contributions, since the tree-sitter ",
        "grammar itself is editor-agnostic.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
require("nvim-treesitter.parsers").toku = {
  install_info = {
    url = "https://github.com/birchpointswe/tree-sitter-toku",
    files = { "src/parser.c" },
    generate_requires_npm = false,
    requires_generate_from_grammar = false,
  },
}
vim.treesitter.language.register("toku", "toku")

-- strip .tk, then ask nvim what the remaining name would be
local function inner_ft (path)
  local name = vim.fn.fnamemodify(path, ":t"):gsub("%.tk", "")
  local ext = name:match("([^%.]*)$")
  return vim.filetype.match({ filename = name }) or ext
end

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.tk", "*.tk.*" },
  callback = function ()
    local ft = inner_ft(vim.fn.expand("%"))
    vim.opt_local.filetype = "toku"
    if ft then
      vim.opt_local.commentstring = vim.filetype.get_option(ft, "commentstring")
    end
  end,
})

vim.treesitter.query.add_directive("toku-inject!", function (_, _, source, _, metadata)
  local info = vim.fn.getbufinfo(source)
  if info and info[1] and info[1].name then
    metadata["injection.language"] = inner_ft(info[1].name)
  end
end, { all = true })
]],
    },

    scaffolded("lib", "lib/%m/capi.c",
      "A C extension in the same rock",
      table.concat({
        "C sources under lib are compiled and linked as Lua modules by the generated ",
        "Makefile, with no extra configuration: dropping a .c file beside your Lua ",
        "sources is the whole workflow. The module name follows the path, so this ",
        "builds my-lib.capi. santoku's own C libraries use this exact layout.",
      })),

    scaffolded("lib", "bin/%s.lua",
      "An executable entry point",
      table.concat({
        "Files in bin become executables installed by luarocks. They are ordinary Lua ",
        "scripts. toku install --bundled goes further and compiles each one, together ",
        "with every module it requires, into a single native binary via santoku-bundle ",
        "and your C compiler, installed into PREFIX/bin. That is how the toku command ",
        "itself is built.",
      })),

    scaffolded("lib", "test/spec/%m.lua",
      "The spec, and how the runner finds it",
      table.concat({
        "toku test discovers test/spec recursively; there is no registration step and ",
        "no config. Each file runs in its own interpreter process, so one spec cannot ",
        "leak state into another. santoku.test takes a tag and a function and nests ",
        "arbitrarily; a failing assertion prints the tag chain, the error and a ",
        "traceback. Every spec runs by default. Pass -s to stop at the first failure, ",
        "--single to run one file, or -m to filter by Lua pattern.",
      })),

    scaffolded("lib", "res/migrations/0.0.1.sql",
      "Versioned SQL migrations",
      table.concat({
        "Files under res are installed with the rock and reachable at runtime. The ",
        "boilerplate uses that for santoku-sqlite-migrate: migrations are named by ",
        "version, applied in version order, forward-only, each exactly once, inside a ",
        "single transaction. Add 0.0.2.sql beside this one and it applies on next run.",
      })),

    {
      title = "Publishing: what you must add, and what toku release does",
      desc = table.concat({
        "toku init scaffolds all four fields below, so publishing is two edits rather ",
        "than four additions. Flip public to true, which is what registers the release ",
        "target at all; without it toku release errors out. Then replace ",
        "YOUR-GITHUB-USER in homepage with your account. Those two carry the rest: ",
        "tarball names the release asset, and download is derived from homepage and is ",
        "the URL the generated rockspec tells luarocks to fetch, which is exactly where ",
        "toku release uploads it. Leave the placeholder in and you will pack a ",
        "rockspec nobody can install from. After that, release depends on pack, refuses ",
        "to continue on a dirty working tree, tags, pushes, creates the GitHub release, ",
        "and uploads. Two credentials are required and neither is a flag: gh must ",
        "already be authenticated, and LUAROCKS_API_KEY must be set. The API key is ",
        "read first, so a missing key stops you before any tag or push happens.",
      }),
      runnable = false,
      lang = "text",
      code = [[
-- scaffolded into make.lua; edit the first two before you publish:
env.public = true
env.homepage = "https://github.com/YOU/my-lib"
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

$ toku pack        # build the tarball only, publish nothing (safe dry run)
$ toku release     # everything below, in this order

# LUAROCKS_API_KEY is read here; missing means it stops now, before touching git
git diff --quiet                     # refuses if you have uncommitted changes
git tag 0.0.1-1                      # the version from make.lua
git push --tags
git push
gh release create --generate-notes 0.0.1-1 my-lib-0.0.1-1.tar.gz my-lib-0.0.1-1.rockspec
luarocks upload --skip-pack --api-key "$LUAROCKS_API_KEY" my-lib-0.0.1-1.rockspec
]],
    },

    {
      title = "Environment variables the harness reads",
      desc = table.concat({
        "The build harness reads exactly five environment variables, and this is the ",
        "complete list. LUAROCKS_API_KEY is required by release and has no command ",
        "line equivalent. OPENRESTY_DIR locates OpenResty for web projects and also ",
        "selects the interpreter their server specs run under. CC overrides the C ",
        "compiler for native builds and bundling. PREFIX and HOME supply the default ",
        "install prefix for toku install --bundled: --prefix wins if given, otherwise ",
        "$PREFIX, otherwise $HOME/.local. On Termux PREFIX is always set, so it is the ",
        "one that takes effect.",
      }),
      runnable = false,
      lang = "text",
      code = [[
LUAROCKS_API_KEY   # required by toku release; no CLI flag exists for it
OPENRESTY_DIR      # web projects: OpenResty location, and the server spec interpreter
CC                 # C compiler for native builds and bundling (default: cc)
PREFIX             # install prefix for toku install --bundled, unless --prefix
HOME               # fallback prefix root ($HOME/.local) when PREFIX is unset
]],
    },

  },

}

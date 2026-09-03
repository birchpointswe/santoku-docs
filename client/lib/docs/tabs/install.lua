local script = require("docs.setup_script")

return {

  intro = table.concat({
    "Everything on this site is driven by toku, the santoku command line, and toku ",
    "requires a one-time setup before it will build anything. The sanctioned install is ",
    "setup-toku.sh, the script this page both renders in full and serves for download at ",
    "https://santoku.dev/setup-toku.sh: both come from the same file, so what you read ",
    "here is exactly what you run. The script builds lua 5.1.5 and luarocks 3.13.0 from ",
    "sha256-verified sources into ~/.local/share/toku (honouring XDG_DATA_HOME), installs ",
    "santoku-cli there, and stores a copy of itself in that tree for later repairs and ",
    "upgrades. It writes nothing else: no symlinks, no shell rc edits, nothing outside ",
    "that one directory, and toku setup --uninstall removes it entirely. It builds its ",
    "own lua because santoku rocks pin lua == 5.1, which a system luarocks targeting a ",
    "newer lua cannot install. Prerequisites: cc, make, tar, unzip, curl or wget, and a ",
    "sha256 tool (sha256sum, shasum, or openssl).",
  }),

  examples = {

    {
      title = "Download, read, then run",
      desc = table.concat({
        "Three steps, in this order: download the script, read it, run it. Do not pipe ",
        "it from the network into a shell; the point of a short auditable script is that ",
        "you look at it first, and its full text is reproduced below. When it finishes ",
        "it prints where everything landed and the optional PATH line. Wiring PATH is ",
        "your call and yours to do; the script never edits shell configuration. Finish ",
        "by running toku doctor, which reports the mode, the resolved lua and luarocks, ",
        "and PATH wiring, and exits nonzero if anything is wrong.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ curl -fSLO https://santoku.dev/setup-toku.sh
$ less setup-toku.sh
$ sh setup-toku.sh
[setup]	fetching https://www.lua.org/ftp/lua-5.1.5.tar.gz
[setup]	building lua 5.1.5 (Linux)
[setup]	fetching https://luarocks.github.io/luarocks/releases/luarocks-3.13.0.tar.gz
[setup]	building luarocks 3.13.0
[setup]	installing santoku-cli into /home/you/.local/share/toku/rocks
[setup]	managed toolchain ready at /home/you/.local/share/toku
[setup]	managed toku: /home/you/.local/share/toku/rocks/bin/toku
[setup]	optional PATH wiring:
[setup]	  export PATH="/home/you/.local/share/toku/rocks/bin:...:$PATH"
[setup]	verify with: toku doctor

$ export PATH="$("$HOME/.local/share/toku/rocks/bin/toku" setup --path):$PATH"
$ toku doctor
toku doctor
  mode: managed
  ...
no problems found
]],
    },

    {
      title = "setup-toku.sh, in full",
      desc = table.concat({
        "The complete script, embedded at build time from the same file the download ",
        "serves, so this text and the downloaded file cannot drift. The build also ",
        "fails if the versions pinned here stop matching the ones the installed ",
        "santoku-cli expects. Beyond the build itself, the script applies three small ",
        "portability patches (a TMPDIR-aware lua tmpnam for systems without a writable ",
        "/tmp, and two luarocks fixes for Android), and every download is verified ",
        "against a pinned sha256 before anything is built.",
      }),
      runnable = false,
      lang = script.lang,
      code = script.code,
    },

    {
      title = "Using a lua 5.1 toolchain you already have",
      desc = table.concat({
        "toku records which lua and luarocks it drives in a manifest at ",
        "~/.local/share/toku, in one of two modes. The script above sets up managed ",
        "mode, a private pair that shadows nothing on your system. If you would rather ",
        "toku drive your own toolchain, run toku setup --use-system afterwards: it ",
        "verifies that the interpreter reports Lua 5.1 (a 5.1-compatible luajit is ",
        "accepted) and that luarocks targets lua 5.1, records their absolute paths, ",
        "and refuses with a precise diagnostic otherwise. A lua 5.1 luac is recorded ",
        "too when one exists; luajit systems often have none, in which case the ",
        "bytecode commands error with instructions instead of silently using a ",
        "mismatched luac.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku setup --use-system
[setup]	using system toolchain
[setup]	lua: /usr/bin/luajit (Lua 5.1, LuaJIT 2.1.1748459687)
[setup]	luarocks: /usr/bin/luarocks (3.12.2, targets lua 5.1)
[setup]	luac: /usr/bin/luac5.1 (5.1.5)
[setup]	recorded in /home/you/.local/share/toku/manifest.lua
$ toku doctor
]],
    },

    {
      title = "Maintenance: doctor, repair, upgrade, uninstall",
      desc = table.concat({
        "The provisioning script stores a copy of itself at ",
        "~/.local/share/toku/setup-toku.sh, so the managed tree always carries the ",
        "script that built it. toku setup --repair and --upgrade re-run that stored ",
        "copy with --rebuild: lua and luarocks are rebuilt at the pinned versions and ",
        "santoku-cli is reinstalled, while the installed rocks tree is kept. If the ",
        "stored copy is missing, or it pins different versions than the installed ",
        "santoku-cli, both commands error and point you back to this page for the ",
        "current script. toku doctor is the health check to reach for first; it names ",
        "the exact command that fixes each problem it finds.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku doctor              # mode, versions, drift, PATH wiring; exits nonzero on problems
$ toku setup               # re-run the stored script to complete a partial tree
$ toku setup --repair      # rebuild a broken managed tree, keeping installed rocks
$ toku setup --upgrade     # rebuild at the pinned versions after upgrading santoku-cli
$ toku setup --path        # print the managed bin directories for PATH wiring
$ toku setup --uninstall   # remove ~/.local/share/toku entirely
]],
    },

  },

}

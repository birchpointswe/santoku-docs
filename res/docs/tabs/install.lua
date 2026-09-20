
return {

  intro = table.concat({
    "Everything on this site is driven by toku, the santoku command line, and toku ",
    "requires a one-time setup before it will build anything. The sanctioned install is ",
    "setup-toku.sh, served at https://santoku.dev/setup-toku.sh. ",
    "The script builds lua 5.1.5 and luarocks 3.13.0 from ",
    "sha256-verified sources into ~/.local/share/toku (honouring XDG_DATA_HOME), installs ",
    "santoku-cli there, and stores a copy of itself in that tree for later repairs and ",
    "upgrades. It writes nothing else: no symlinks, no shell rc edits, nothing outside ",
    "that one directory, and toku setup --uninstall removes it entirely. It builds its ",
    "own lua because santoku rocks pin lua == 5.1, which a system luarocks targeting a ",
    "newer lua cannot install. Prerequisites: cc, make, tar, unzip, curl or wget, and a ",
    "sha256 tool (sha256sum, shasum, or openssl). ",
    "This is the only supported install. A toku that arrives on PATH some other way ",
    "is a shell shim that execs a lua5.1 it does not own, which on a distribution ",
    "with no lua5.1 package fails with exec: /usr/bin/lua5.1: not found. Run ",
    "setup-toku.sh and use the toku it installs.",
  }),

  examples = {

    {
      title = "Download and run",
      desc = table.concat({
        "Download the script, run it, and finish with toku doctor. When setup ",
        "completes it prints where everything landed and the optional PATH line. ",
        "Wiring PATH is yours to do; the script never edits shell configuration. ",
        "toku doctor reports the mode, the resolved lua and luarocks, and PATH ",
        "wiring, and exits nonzero if anything is wrong.",
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
      title = "What the managed toolchain is, and how toku uses it",
      desc = table.concat({
        "Until setup has run, every command that needs lua or luarocks (toku lua, ",
        "toku luarocks, and the whole project lifecycle) errors and names the step ",
        "to run. Afterwards toku prepends the managed bin directories to PATH inside ",
        "its own process, so every lua and luarocks invocation a toku-driven build ",
        "makes uses the managed pair. Nothing outside that process changes. To reach ",
        "the same pair from your shell, wire PATH yourself as the transcript above ",
        "does, or symlink the binaries you want out of the directories toku setup ",
        "--path prints. The passthrough commands run the managed tools directly: ",
        "toku lua is the managed interpreter with the managed rocks tree on its ",
        "package path, and toku bundle --luac-default compiles bytecode with the ",
        "managed luac, so a system luac built for a newer Lua cannot corrupt a ",
        "bundle.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ toku lua scripts/load.lua      # managed lua, managed rocks tree on the package path
$ toku luarocks list             # passthrough to the managed luarocks
$ toku luac -o out.luac in.lua   # passthrough to the managed luac
$ toku setup --path              # the managed bin directories, colon-joined
]],
    },

    {
      title = "Maintenance: doctor, repair, upgrade, uninstall",
      desc = table.concat({
        "The provisioning script stores a copy of itself at ",
        "~/.local/share/toku/setup-toku.sh, so the managed tree always carries the ",
        "script that built it. toku setup with no flag re-runs that copy to complete ",
        "a partial tree and is safe to repeat. toku setup --repair and --upgrade ",
        "re-run it with --rebuild: lua and luarocks are rebuilt at the pinned ",
        "versions and santoku-cli is reinstalled, while the installed rocks tree is ",
        "kept. If the stored copy is missing, or it pins different versions than the ",
        "installed santoku-cli, both commands error and point you back to this page ",
        "for the current script. toku doctor is the health check to reach for first: ",
        "it reports the mode, the lua and luarocks actually in effect, tree health, ",
        "version drift against the pins, your shell PATH wiring and the build ",
        "prerequisites, exits nonzero when it finds a problem, and names the command ",
        "that fixes each one.",
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

    {
      title = "Upgrading santoku-cli itself",
      desc = table.concat({
        "toku setup --upgrade rebuilds lua and luarocks at the versions the ",
        "installed santoku-cli pins; it does not fetch a newer santoku-cli. Upgrading ",
        "the CLI is a luarocks install into the managed rocks tree, and toku setup ",
        "--upgrade afterwards realigns lua and luarocks with whatever the new version ",
        "pins. Upgrade santoku-make in the same way when a page names a minimum for ",
        "it: luarocks resolves an already-satisfied constraint by installing nothing, ",
        "so a santoku-cli that is newer than the santoku-make beside it can fail ",
        "inside toku with a nil-call traceback rather than a version message. ",
        "toku doctor reports both versions.",
      }),
      runnable = false,
      lang = "text",
      code = [[
$ luarocks --tree="$HOME/.local/share/toku/rocks" install santoku-cli
$ luarocks --tree="$HOME/.local/share/toku/rocks" install santoku-make
$ toku setup --upgrade
$ toku doctor
]],
    },

  },

}

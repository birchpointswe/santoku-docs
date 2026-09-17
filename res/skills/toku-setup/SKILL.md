---
name: toku-setup
description: Install, verify or repair the toku toolchain for a santoku or Lua project. Use when the toku command is missing, setup-toku.sh fails, lua or luarocks are the wrong version, emcc or openresty are missing, luarocks refuses a rock that pins lua 5.1, or a build fails before it compiles anything. Also covers running toku from the container image santoku-make ships when the native install keeps failing.
---

# Getting toku running

toku is the build, test and release harness for every santoku project. Do not substitute
`make`, a shell build script, `luarocks install`, or a direct `lua` run over a spec file.

## Install

1. `curl -fSLO https://santoku.dev/setup-toku.sh`
2. Read the script.
3. `sh setup-toku.sh`
4. `export PATH="$("$HOME/.local/share/toku/rocks/bin/toku" setup --path):$PATH"`
5. `toku doctor`

The script builds lua 5.1.5 and luarocks 3.13.0 from sha256-verified sources into
`~/.local/share/toku` (honouring `XDG_DATA_HOME`) and installs santoku-cli there. It writes
nothing outside that directory and edits no shell configuration. Prerequisites: `cc`, `make`,
`tar`, `unzip`, `curl` or `wget`, and one of `sha256sum`, `shasum`, `openssl`.

Walkthrough: https://santoku.dev/install#install--download-and-run

## Diagnose

Run `toku doctor` first on any failure. It reports the mode, the resolved lua, luac and
luarocks, drift against the pinned versions, PATH wiring, and, inside a web project, whether
emcc, node and openresty are present. It names the command that fixes each problem it finds
and exits nonzero when anything is wrong.

| Command | Use |
| --- | --- |
| `toku setup` | finish a partially built tree |
| `toku setup --repair` | rebuild a broken tree, keeping installed rocks |
| `toku setup --upgrade` | rebuild at the pinned versions after upgrading santoku-cli |
| `toku setup --path` | print the managed bin directories for PATH wiring |
| `toku setup --uninstall` | remove `~/.local/share/toku` entirely |

Details: https://santoku.dev/install#install--maintenance-doctor-repair-upgrade-uninstall

## Escape hatch: run toku in a container

A web project also needs Emscripten, OpenResty, node, tailwindcss and esbuild. If the native
install fails twice, switch to the images santoku-make ships rather than continuing to debug
the host toolchain. `toku-lib.dockerfile`, `toku-web.dockerfile` and the wrapper scripts sit
at the root of the lua-santoku-make checkout. Your code is mounted at `/app`, so the build
tree lands in your working directory as usual.

```sh
git clone https://github.com/birchpointswe/lua-santoku-make
cd lua-santoku-make && docker build -t toku-web -f toku-web.dockerfile .
cd /path/to/your/project
/path/to/lua-santoku-make/toku-web.sh -- build --test
/path/to/lua-santoku-make/toku-web.sh -p 8080:8080 -- start --test
```

Everything after `--` is passed to toku, everything before it goes to the container runtime.
`toku-lib.sh` and `toku-web.sh` are one-line shims over a shared `toku-container.sh`.
Use `toku-lib` for library projects and `toku-web` for anything with a `client/`.

Library projects: https://santoku.dev/start-lib#start-lib--option-two-run-toku-from-the-container-image

Web projects: https://santoku.dev/start-web#start-web--option-two-run-toku-from-the-container-image

## Failures with a known cause

- `luarocks` refusing a santoku rock: santoku rocks pin `lua == 5.1`, and a system luarocks
  targeting a newer lua cannot install them. Use the managed pair, through `toku luarocks`.
- A spec that fails when run directly with `lua`: specs run against the build tree `toku test`
  produces, including the installed rock tree under `build/<env>/`. Run `toku test`.
- A web build failing one missing tool at a time: `toku doctor` inside the project lists all
  of them at once.

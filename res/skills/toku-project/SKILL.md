---
name: toku-project
description: Navigate and build a santoku project driven by toku. Use when scaffolding a new Lua rock, web app or JSON API, when unsure where a new file belongs (lib, bin, res, test/spec, client, server, deps), when reading or editing make.lua, when a build lands somewhere unexpected under build/, or when choosing between toku test, build, start, install, pack and release. Covers the descriptor, directory conventions, environments and the toku test --iterate dev loop.
---

# Project layout and the build loop

Three project types, each scaffolded complete and already building: `toku init` for a library
rock, `toku init --web` for a WebAssembly client plus OpenResty server, `toku init --api` for
a JSON API with no frontend. Add `--here` to scaffold into the current directory using its
name.

## Where files go

| Path | Meaning |
| --- | --- |
| `make.lua` | the descriptor: name, version, license, dependencies, per-type blocks |
| `make.<env>.lua` | an environment variant, selected with `--env <name>` |
| `lib/` | Lua modules; `.c` files here compile as Lua modules with no extra configuration |
| `bin/` | executables; `toku install --bundled` compiles them to single native binaries |
| `res/` | resources installed with the rock and readable at runtime |
| `test/spec/` | specs, discovered recursively, each run in its own interpreter |
| `deps/<dep>/` | a vendored template (Makefile plus helpers) copied into the build tree |
| `client/` | web projects: `bin/`, `lib/`, `res/`, `static/`, `test/spec/` |
| `server/` | web projects: `lib/`, `test/spec/`, `nginx.tk.conf` |

A hyphenated project name splits: the rock and the executable keep the hyphen, the Lua module
and the C entry point use underscores, because `luaopen_my-lib_capi` is not a valid C
identifier. `my-lib` publishes as `my-lib` and is required as `my_lib`.

Any file with `.tk` in its name is a build-time template. See the tk-templates skill.

## The build tree

Output lands in `build/<env>[-suffix]/`. `--env` defaults to `default` and selects
`make.<env>.lua`.

- `toku test` builds `build/default/test/`
- `toku build` builds `build/default/build/`
- `toku test --wasm` builds `build/default-wasm/test/`

Inside a test environment: a generated Makefile and `.d` files, a private `lua_modules/`
install tree, copied `lib/` and `test/` trees, copied `deps/` templates, a generated
rockspec. Upstream dependency clones and their installs live in the sibling
`build/<env>/build-deps/`. `deps/<dep>/` in the source tree is a template, never a build
artifact, so never delete it. Prefer `toku clean` over manual removal.

Because the test tree is a real installed rock, specs run against the installed layout rather
than the source tree. Running a spec file directly with `lua` will not work.

## The dev loop

Leave one of these running in a pane and edit in another:

```sh
toku test --iterate                 # library
toku test --iterate --show-logs     # web project
```

What it composes:

```sh
toku test                            # render, install deps, run specs, then luacheck
toku test --single test/spec/foo.lua # one spec file
toku test -m core -s                 # filter by lua pattern, stop at first failure
toku test --skip-check               # skip luacheck
toku build --test                    # web: render client wasm and server tree
toku start --test                    # web: run OpenResty against it
toku stop                            # web: stops both environments
toku exec -- lua -e '...'            # a command inside the test environment
toku install                         # install into the active rocks tree
toku pack                            # rockspec and tarball, no release
```

Web notes: do not pipe `toku start`, because it backgrounds OpenResty and the pipe never
closes. `stop` takes no `--test` even though `start` does. Flags that belong to another
project type are rejected rather than ignored.

Sanitizers are an environment, so use `--env sanitize` with a `make.sanitize.lua` that bakes
in the toolchain and flags, paired with `--lua` to preload the runtime where ASan needs it.

## Releasing

`toku release` does not bump versions. Edit `version` in `make.lua` or `make.common.lua`,
commit, then release from a clean tree; it tags, pushes, creates the GitHub release and
uploads the rockspec. Release in dependency order, dependencies first.

santoku rocks are semver from 1.0.0. Dependency constraints carry an upper bound
(`"santoku >= 1.0.0, < 2.0.0"`); a bare `>=` admits the next major and breaks consumers at
install time.

## Reference

- https://santoku.dev/santoku-cli#santoku-cli--the-command-surface
- https://santoku.dev/santoku-cli#santoku-cli--environments-and-the-build-tree
- https://santoku.dev/start-lib
- https://santoku.dev/start-web
- https://santoku.dev/start-server

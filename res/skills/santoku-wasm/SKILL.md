---
name: santoku-wasm
description: Make Lua or C behave correctly in a WebAssembly build of a santoku or toku project, or fix a spec that passes under toku test and fails under toku test --wasm. Use when a function is missing under emscripten, when io.popen or another capability exists but raises when called, when a module needs a separate wasm implementation, or when code must not be emitted into a wasm build at all. Covers ifndef __EMSCRIPTEN__, presence gates, invocation probes, .wasm. filename variants and build-time template gates.
---

# Gating code for WebAssembly

Four mechanisms make code differ under wasm. Picking the wrong one is the usual failure, and
the choice follows from what is actually different about the build.

| What is different | Mechanism | Form |
| --- | --- | --- |
| The capability is absent | gate on presence | `if fs.hardlink then ... end` |
| It exists and always raises | probe once | `local ok = pcall(io.popen, "true")` |
| A separate implementation exists | filename variant | `lib/santoku/web/js.wasm.lua` |
| The text must not be emitted | template gate | `<% push(is_wasm) %> ... <% pop() %>` |

Full treatment, with the code for each:
https://santoku.dev/santoku-make#santoku-make--choosing-a-wasm-mechanism

## Compiling a capability out

emcc defines `__EMSCRIPTEN__`. Guard the function body and its `luaL_Reg` entry together: an
entry without a body fails to link, a body without an entry is dead code. lua-santoku-fs does
this for `hardlink` and `symlink` in `lib/santoku/fs/posix.c`. When a module must keep the
function and change what it does, guard inside the body and expose which build Lua got, the
way `santoku.sqlite.db` sets a `wasm` field from the same ifdef.

https://santoku.dev/santoku-make#santoku-make--compiling-a-capability-out-of-a-c-extension

## Gating a spec

Register the test only when the capability is there, rather than skipping it inside the test:

```lua
if fs.hardlink then
  test("hardlink", function () ... end)
end
```

https://santoku.dev/santoku-make#santoku-make--gating-a-spec-on-the-capability-it-needs

## When presence lies

A presence check settles it only when the capability is genuinely missing. Under emscripten
`io.popen` exists and raises `'popen' not supported` when called, so `if io.popen then` reads
as available and is wrong. Probe once, name the result, and gate on the name:

```lua
local can_spawn = pcall(io.popen, "true")
```

The same trap applies to anything whose absence is behavioural rather than structural: a
module compiled into a wasm bundle is not present on disk, so a `searchpath` lookup correctly
returns nil and a test asserting otherwise is the thing that is wrong.

https://santoku.dev/santoku-make#santoku-make--when-the-presence-check-lies-io-popen

## Filename variants

`<name>.wasm.<ext>` selects a wasm-specific source at build time, as in lua-santoku-web's
`val.wasm.c`, `async.wasm.tk.lua` and its `*.wasm.lua` specs. This is variant selection; it
does not help with a test that cannot run in this environment.

https://santoku.dev/santoku-make#santoku-make--filename-variants-wasm-sources-and-specs

## Build and test

- `toku test --wasm` builds into `build/<env>-wasm/test/` and runs the suite there.
- `toku install --wasm` bundles to `build/<env>-wasm/`.
- Native and wasm variant flags live in the descriptor, on the santoku-make tab.
- Green natively proves nothing about wasm. Run both.

---
name: santoku-reference
description: Look up a santoku or toku API before using it, instead of copying a pattern from a neighbouring file or recalling a name from memory. Use whenever the exact name, arguments or return values of a santoku function are not certain, when a santoku call fails with "attempt to call a nil value", when deciding whether a capability already exists somewhere in the ecosystem, or before writing docs or examples that name a santoku API. The full reference is santoku.dev/llms-full.txt.
---

# Consult the reference, do not pattern match

santoku spans many rocks, and a name that reads plausibly in a neighbouring file is often
from a different module or does not exist. Inferring an API from surrounding code is how
fabricated function names get written down as fact.

## Order of resort

1. https://santoku.dev/llms-full.txt carries every documented page in full, including every
   example with its code. Fetch it and search it.
2. https://santoku.dev/llms.txt is the index: title, summary, the Lua 5.1 position, and one
   line per page grouped under Getting started, Core, Web and servers, Data and machine
   learning, Build and test, System and crypto, Text and templates. Each entry links its
   page and its upstream repository.
3. The source itself. For a Lua module, its `return { ... }` table. For a C extension, the
   `luaL_Reg` table in the `.c` file. This is the only acceptable way to confirm a name that
   the reference does not cover.

Documentation lives in exactly one place. Do not mirror santoku docs into a consumer repo, a
README, or a per-project notes file.

## Facts that hold across the ecosystem

- Lua 5.1 only. No portability shims, no version branches, no "may break in 5.2" caveats.
- Build, test, install and release go through `toku`, driven by `make.lua`. Never `make`,
  never `luarocks install` directly, never `lua` on a spec file.
- Standard library namespaces do not appear in application code; the owning santoku module
  does. See the santoku-primitives skill.
- No fallbacks and no compat shims. One implementation that works everywhere, or a loud
  failure.
- When santoku cannot do something, that is a gap to fill in the owning module so every
  consumer inherits it, rather than a local workaround or a switch to another language.

## Related skills

`toku-setup` for installing the toolchain, `toku-project` for layout and the build loop,
`tk-templates` for `.tk` files, `santoku-primitives` for module choice, `santoku-wasm` for
WebAssembly builds.

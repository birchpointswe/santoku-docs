---
name: santoku-primitives
description: Pick the right santoku module instead of the Lua standard library when writing Lua in a santoku or toku project. Use before calling string.*, table.*, os.*, io.*, math.* or package.*, before writing a helper that santoku probably already owns, and before assuming a santoku function name from surrounding code. Covers str, arr, tbl, fs, sys, env, err, utc, num, random, lua, serialize, validate, verifying names against source, and why fallbacks and compat shims are banned.
---

# santoku primitives over the standard library

Stdlib namespaces do not appear in application or library code. The owning santoku module
carries the platform handling and the edge cases, and extending it means every consumer
inherits the fix. Raw stdlib is legitimate only inside the primitive that wraps it, which is
what `santoku.env.var` does over `os.getenv`.

## The mapping

| Instead of | Use | Rock |
| --- | --- | --- |
| `string.*` | `santoku.string` | santoku |
| `table.*` (arrays) | `santoku.array` | santoku |
| `table.*` (maps, nested access) | `santoku.table` | santoku |
| `io.*`, path handling, directory walking | `santoku.fs` | santoku-fs |
| `os.execute`, `io.popen`, process spawning | `santoku.system` | santoku-system |
| `os.getenv`, `package.path` | `santoku.env` | santoku |
| `error`, `assert`, `pcall` | `santoku.error` | santoku |
| `os.time`, `os.date` | `santoku.utc` | santoku |
| `math.*` | `santoku.num` | santoku |
| `math.random` | `santoku.random` | santoku |
| `loadstring`, `setfenv`, `getfenv` | `santoku.lua` | santoku |
| writing a table back out as Lua source | `santoku.serialize` | santoku |
| type and structure checks | `santoku.validate` | santoku |

`santoku.num` and `santoku.lua` merge the stdlib table they replace, so the original
functions remain reachable through the santoku module. Also present: `santoku.functional`,
`santoku.op`, `santoku.inherit`, `santoku.fracidx`, `santoku.async`, `santoku.co`,
`santoku.geo`.

Local aliasing at the top of a file is the house style:

```lua
local str = require("santoku.string")
local arr = require("santoku.array")
local fs = require("santoku.fs")
```

## Verify every name against source

Never infer a santoku API from prose, from a neighbouring file, or from memory. Confirm it:

- Lua module: read its `return { ... }` table.
- C extension: read the `luaL_Reg` table in the `.c` file.
- Either way: https://santoku.dev/llms-full.txt carries every documented module with working
  examples.

A fabricated name that looks plausible is the failure this rule exists to prevent.

## No fallbacks, no compat shims

One implementation that works everywhere. Never a rescue path behind `pcall`, `or`, or a
feature probe, and never an old branch kept alive in case something changes. A fallback that
hides a failure is a bug: work one way or fail loudly.

- `arr.spread`, never `unpack or table.unpack`.
- `santoku.lua` owns loading, never `loadstring or load`.
- No capability guards in code that only ever runs on Lua 5.1.

## Lua 5.1 only

The whole stack targets 5.1, and exploits it: userdata `fenv` for per-object anchoring,
userdata-only `__gc` for finalizers, a single `number` type, lightuserdata pointer keys. Do
not add portability shims or "may break in 5.2" caveats to code, docs or comments.

## Scripting is Lua

Anything that transforms files, generates output, or would plausibly be rerun goes through
santoku: `toku lua`, or a script built on `str`, `arr`, `fs`, `sys`, `santoku.lpeg`. Reaching
for python, perl, or a long sed or awk pipeline is the signal to write it in Lua instead.
Throwaway inspection (`ls`, `grep -c`, `wc`) stays shell. When santoku genuinely cannot do
the job, that is a gap to fill in the owning module.

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

`sys.execute` and `sys.sh` take an argument list and exec it directly, with no shell
between. Nothing in an argument is word split, glob expanded or interpreted, so values
that came from a filename, a network response or user input cannot become commands. They
also raise on a nonzero exit rather than returning a status to check. That is the whole
reason to reach for them instead of building a command string: there is no quoting to get
right, because nothing parses the string.

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

## Parsing and text transformation

`santoku.lpeg` exports finished parsers only (JSON field streaming, CSV, the HTML scanners,
plus `santoku.lpeg.strip`), so a new parser is written one layer down, in either of two
notations for the same engine:

- `santoku.re` compiles a PEG pattern string: `compile`, `match`, `find`, `gsub`. Reach for
  it when the grammar reads better as text and every transform is a literal.
- `santoku.re.core` is the vendored LPeg 1.1.0 engine: the constructors `P`, `S`, `R`, `B`,
  `V`, `utfR`, the capture family `C`, `Cc`, `Cp`, `Cs`, `Ct`, `Cg`, `Cb`, `Cf`, `Cmt`,
  `Carg`, and the operator algebra (`*` sequence, `+` ordered choice, `^n` repetition, `-`
  difference, unary `-` and `#` lookahead, `/` and `%` capture transforms) that grammars are
  built from. Reach for it when captures need Lua functions or rules are assembled from data.

`require("lpeg")` does not reach the engine: the C module is registered as `santoku.re.core`
so a project can depend on an external lpeg rock at the same time. Grammar construction in
both notations is covered at
https://santoku.dev/santoku-lpeg#santoku-lpeg--santoku-re-core-the-combinator-surface


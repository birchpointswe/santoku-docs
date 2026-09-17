---
name: tk-templates
description: Write or edit a .tk file in a santoku or toku project (.tk.lua, .tk.c, .tk.html, .tk.conf, .tk.sh, .tk.txt). Use when putting build-time configuration into generated source, gating debug or verbose code out of a build, choosing between a runtime if and a build-time gate, or when a "<% %>" block is emitting the wrong thing. Covers value interpolation versus conditional inclusion with push and pop.
---

# Writing .tk templates

Any file with `.tk` in its name is rendered by santoku-template during the build and the
`.tk` stripped from the destination: `main.tk.lua` becomes `main.lua`. It is rendered against
the project environment from `make.lua`, so a template can read descriptor values the
generated source cannot compute for itself. Expansion applies to every file in an
environment, `test/spec` included.

## Interpolation versus gating

| Goal | Form |
| --- | --- |
| Put a value into the output | `<% return expr %>` |
| Include or drop a region of output | `<% push(cond) %>` text `<% pop() %>` |

`<% return expr %>` substitutes the returned string at that point. Use it for data: a table
field, a version string, a path.

`push(cond)` opens a gate; everything between it and the matching `pop()` is emitted only
when `cond` is truthy. Use it for code.

## The mistake to avoid

Rendering a condition into a runtime `if` ships the dead branch and everything inside it:

```lua
if <% return tostring(client.verbose or false) %> then
  js.console:log("...")
end
```

Every non-verbose build now carries `if false then ... end`, the log call, and its string
literals. Both forms compile and neither warns, so this survives review. The gate emits
nothing instead:

```lua
<% push(client.verbose) %>
  js.console:log("...")
<% pop() %>
```

The else branch is `<% pop() push(not cond) %>`.

## Gate semantics

- `push(cond)` ANDs with the enclosing gate, so an outer false gate silences everything
  nested inside it.
- `showing()` returns the current gate state from inside a block.
- Gating filters output only. Every block still executes, so an assignment made inside a
  false gate is visible after the `pop()`.
- A block returning a non-string raises during render; a block that is not valid Lua raises
  during compile, before any render.
- A block that returns nothing collapses the blank line it would have left behind.

Verify against the source when in doubt: `push`, `pop` and `showing` are environment globals
installed by `lib/santoku/template.lua` in lua-santoku-template. They are not fields of the
module table, which exports `compile`, `compilefile`, `render`, `renderfile`,
`serialize_deps` and `deserialize_deps`.

## What a template can see

`readfile(path)` and `root_dir` let a small `.tk` file pull in a larger template kept under
`res/`. Web projects additionally inject `hashed(name)` (the correct way to reference a
content-hashed asset), `version`, the descriptor's `client` and `nginx` blocks, `modules`,
`openresty_dir`, the lua package paths, and the output directories. The full list is on the
santoku-template tab.

## Reference

- https://santoku.dev/santoku-template#santoku-template--conditional-sections-with-push-and-pop
- https://santoku.dev/santoku-template#santoku-template--nested-gates-compose-with-and
- https://santoku.dev/santoku-template#santoku-template--hidden-blocks-still-execute
- https://santoku.dev/santoku-template#santoku-template--how-toku-expands-a-tk-file
- https://santoku.dev/santoku-template#santoku-template--what-a-tk-file-can-see-in-a-web-project

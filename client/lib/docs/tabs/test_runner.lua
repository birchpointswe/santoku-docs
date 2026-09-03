return {

  intro = table.concat({
    "santoku-test-runner is the smallest rock in the framework: one module, ",
    "santoku.test.runner, exporting one function, and it is what toku test delegates ",
    "to. Given files and directories it walks them, prints a Test: line per file, and ",
    "runs each one, in-process for Lua files or as a subprocess under an interpreter ",
    "of your choice, with a Lua-pattern file filter and an optional stop-on-failure. ",
    "The spec side of the contract lives in the base library as santoku.test, a ",
    "17-line tagged-block harness. This tab covers both halves, basics to advanced: ",
    "how to write specs the way the santoku repos and their consumers do, and exactly ",
    "how the runner discovers and executes them. The santoku.test harness ships in ",
    "this page's bundle, so writing and running a spec works live below; the runner ",
    "itself spawns real processes, so its examples are display only.",
  }),

  examples = {

    {
      title = "Writing a spec: santoku.test",
      desc = table.concat({
        "A spec file is a plain Lua script: require santoku.test, call test(tag, fn) ",
        "for each case, and assert inside. Blocks nest, and the tags accumulate into ",
        "a chain. A passing suite is silent; a failing assertion prints the full tag ",
        "chain, the error, and a traceback, then exits the process with status 1, so ",
        "the file's exit status is the verdict. There is no registration, no runner ",
        "object, no setup or teardown API: the file just executes top to bottom. This ",
        "spec is real, the base library's fracidx suite: ",
        "https://github.com/birchpointswe/lua-santoku/blob/master/test/spec/santoku/fracidx.lua",
      }),
      code = [[
local test = require("santoku.test")

local fi = require("santoku.fracidx")

test("fracidx", function ()

  test("between empty and empty returns canonical zero", function ()
    assert(fi.between(nil, nil) == "a0")
  end)

  test("repeated mid-insertion stays sorted", function ()
    local a, b = "a0", "a1"
    for _ = 1, 50 do
      local m = fi.between(a, b)
      assert(m > a and m < b, "mid was: " .. tostring(m))
      a = m
    end
  end)

end)
]],
    },

    {
      title = "The whole harness, inlined and live",
      desc = table.concat({
        "This is the entire body of santoku.test, inlined as a local function so ",
        "it runs in the page: push the tag, xpcall the block, pop the ",
        "tag. The failure handler joins the tag stack with colons, prints the error ",
        "and a traceback, and exits. Because exit happens inside the handler, the ",
        "first failed assertion ends the file: every test after it simply never ",
        "runs. Edit the assert to false to see the tag chain (but note that in this ",
        "sandbox os.exit ends the interpreter).",
      }),
      code = [[
local arr = require("santoku.array")
local tags = {}
local function test (tag, fn)
  arr.push(tags, tag)
  xpcall(fn, function (...)
    print()
    print(arr.concat(arr.interleaved(tags, ": ")))
    print()
    print((...))
    print(debug.traceback())
    print()
    os.exit(1)
  end)
  arr.pop(tags)
end
test("outer", function ()
  print("chain so far:", arr.concat(tags, " > "))
  test("inner", function ()
    print("chain so far:", arr.concat(tags, " > "))
    assert(1 + 1 == 2)
  end)
end)
return "suite passed"
]],
    },

    {
      title = "A fuller spec: a suffix grammar",
      desc = table.concat({
        "The idioms ",
        "the ecosystem's specs share: localize err.assert over the global so failures ",
        "carry structured values, one outer block named after the module, one inner ",
        "block per behavior stated as a sentence, and table-driven cases for ",
        "round-trip properties, with the case name threaded into every assertion ",
        "message so a failure names the exact case and field.",
      }),
      runnable = false,
      code = [[
local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local grammar = require("outline.grammar")

test("grammar", function ()

  test("suffix renders dates, ends, reps, delay and done", function ()
    assert(grammar.suffix(nil, false, nil, nil, nil) == "")
    assert(grammar.suffix("2026-08-22", false, nil, nil, nil) == " @2026-08-22")
    assert(grammar.suffix("2026-08-22", true, nil, nil, nil) == " @2026-08-22 @done")
  end)

  test("unsuffix inverts suffix", function ()
    local cases = {
      { "plain text", nil, false, nil, nil, nil },
      { "due", "2026-08-22", false, nil, nil, nil },
      { "done", "2026-08-22", true, nil, nil, nil },
      { "rep", "2026-08-22", false, "1w", nil, nil },
    }
    for _, c in ipairs(cases) do
      local line = c[1] .. grammar.suffix(c[2], c[3], c[4], c[5], c[6])
      local text, due, done, rep = grammar.unsuffix(line)
      assert(text == c[1], c[1] .. ": text")
      assert(due == c[2], c[1] .. ": due")
      assert(done == c[3], c[1] .. ": done")
      assert(rep == c[4], c[1] .. ": rep")
    end
  end)

end)
]],
    },

    {
      title = "Assertions that explain themselves",
      desc = table.concat({
        "The assertion vocabulary comes from the base library, not the harness. ",
        "err.assert passes its arguments through on success, so it wraps expressions ",
        "inline, and raises everything after a falsy first argument as a structured ",
        "error. tbl.equals compares deeply and returns the reason on mismatch, which ",
        "err.assert then raises verbatim: wrapping a multi-return call in a table ",
        "literal and deep-comparing it is the standard way specs pin down a ",
        "function's full return signature. This one runs live.",
      }),
      code = [[
local err = require("santoku.error")
local tbl = require("santoku.table")
local assert = err.assert
local pcall = err.pcall
local teq = tbl.equals

local function unsuffix (line)
  local text, due = line:match("^(.-) @(%d%d%d%d%-%d%d%-%d%d)$")
  return text or line, due
end

assert(teq(
  { "buy milk", "2026-08-22" },
  { unsuffix("buy milk @2026-08-22") }))
assert(teq(
  { "no suffix here" },
  { unsuffix("no suffix here") }))

local n = assert(tonumber("42"), "not a number")
print("passed through:", n)

local ok, why = pcall(function ()
  assert(teq({ due = "2026-08-22" }, { due = "2026-08-23" }))
end)
print("caught:", ok, why)
return "all assertions passed"
]],
    },

    {
      title = "The test/spec contract",
      desc = table.concat({
        "By convention a project's specs live under test/spec, mirroring the module ",
        "tree under lib/ so the spec for santoku.fracidx sits at ",
        "test/spec/santoku/fracidx.lua; web projects add client/test/spec and ",
        "server/test/spec. The runner takes any mix of files and directories: ",
        "directories are walked recursively and every regular file found is a test, ",
        "files are run as given, and paths that do not exist are skipped silently ",
        "(the runner's own spec pins that down). Each file gets one Test: line ",
        "before it runs.",
      }),
      runnable = false,
      code = [[
$ find lib test -name "*.lua" | sort
lib/santoku/fracidx.lua
lib/santoku/table.lua
test/spec/santoku/fracidx.lua
test/spec/santoku/table.lua

$ toku test test/spec
Test:   test/spec/santoku/fracidx.lua
Test:   test/spec/santoku/table.lua

$ toku test test/spec/santoku/table.lua /no/such/file.lua
Test:   test/spec/santoku/table.lua
]],
    },

    {
      title = "One function: santoku.test.runner",
      desc = table.concat({
        "The module returns a single function taking an array of paths and an ",
        "options table with exactly three keys: match, a Lua pattern that a file's ",
        "path must match to run; interp, an argv array to run each file under as a ",
        "subprocess; and stop, which exits with status 1 at the first failing file ",
        "instead of continuing. Both arguments are validated as tables, opts is ",
        "optional, and there is no return value or result object: the report is ",
        "what gets printed, and the process exit status is the verdict.",
      }),
      runnable = false,
      code = [[
local runner = require("santoku.test.runner")

runner({ "test/spec" })

runner({ "test/spec/santoku/fracidx.lua" }, { stop = true })

runner({ "test/spec", "client/test/spec" }, {
  match = "%.lua$",
  interp = { "luajit", "-l", "santoku.profile" },
  stop = true,
})
]],
    },

    {
      title = "opts.match: filtering by Lua pattern",
      desc = table.concat({
        "The filter is literally string.match(fp, match) against each candidate's ",
        "full path, applied after directory walking, so an unanchored pattern ",
        "selects by substring anywhere in the path and anchors or magic characters ",
        "work as in any Lua pattern. This live snippet replicates the runner's ",
        "exact test over a sample tree: a module name picks its spec, a prefix ",
        "anchor picks a subtree, and a suffix anchor keeps only Lua sources.",
      }),
      code = [[
local candidates = {
  "test/spec/santoku/array.lua",
  "test/spec/santoku/fracidx.lua",
  "test/spec/santoku/sqlite/db.lua",
  "test/spec/fixtures/seed.sql",
}
local function selected (match)
  local out = {}
  for i = 1, #candidates do
    local fp = candidates[i]
    if (not match) or string.match(fp, match) then
      out[#out + 1] = fp
    end
  end
  return table.concat(out, "  ")
end
print("fracidx:", selected("fracidx"))
print("sqlite subtree:", selected("^test/spec/santoku/sqlite"))
print("lua only:", selected("%.lua$"))
return selected(nil)
]],
    },

    {
      title = "In-process or subprocess: opts.interp",
      desc = table.concat({
        "Without interp, files ending .lua are loaded and called in the runner's ",
        "own process via fs.runfile, all sharing one environment table backed by ",
        "_G, so accidental globals leak between spec files and any os.exit takes ",
        "the whole run down, including the exit(1) santoku.test performs on ",
        "failure. With interp, each file becomes its own subprocess (the argv ",
        "array plus the file path), so failures are isolated per file and any ",
        "interpreter works: a plain lua, luajit, or node for WASM builds. The ",
        "generated project harness always passes -i for exactly this reason.",
      }),
      runnable = false,
      code = [[
$ toku test test/spec
Test:   test/spec/santoku/fracidx.lua
Test:   test/spec/santoku/table.lua

$ toku test -i lua test/spec
$ toku test -i "luajit -l santoku.profile" test/spec
$ toku test -i "node --expose-gc" test/spec
]],
    },

    {
      title = "Failure semantics: keep going or stop",
      desc = table.concat({
        "Each file runs inside pcall. On failure the runner prints the error and, ",
        "by default, moves on to the next file; with stop it exits 1 immediately. ",
        "Under an interpreter the failing spec process prints santoku.test's block ",
        "(tag chain, message, traceback) and exits 1, which surfaces in the runner ",
        "as a structured child-process error, shown below with the traceback ",
        "elided. Without -s the next Test: line follows; with -s the run ends ",
        "there, which is what the project harness uses.",
      }),
      runnable = false,
      code = [[
$ toku test -i lua test/spec
Test:   test/spec/santoku/fracidx.lua

fracidx: between rejects prev >= next

test/spec/santoku/fracidx.lua:52: assertion failed!
stack traceback:
        ...

child process exited with unexpected status    exited    1
Test:   test/spec/santoku/table.lua

$ toku test -s -i lua test/spec
Test:   test/spec/santoku/fracidx.lua
...
child process exited with unexpected status    exited    1
$ echo $?
1
]],
    },

    {
      title = "Inside the runner: the per-file dispatch",
      desc = table.concat({
        "The heart of the module, verbatim: match filters, the Test: line prints, ",
        "then three branches inside pcall. An interp wins for every file (its argv ",
        "is copied, the path appended, and the child spawned); otherwise .lua ",
        "files run in-process via fs.runfile against the shared run_env; anything ",
        "else is handed to santoku.system.execute as a program of its own. The ",
        "trailing closure receives pcall's results: on failure print the error, ",
        "and exit 1 only when stop is set.",
      }),
      runnable = false,
      code = [[
local function process_fp (fp, interp, match, stop)
  if fp and ((not match) or smatch(fp, match)) then
    print("Test:", fp)
    return (function (ok, ...)
      if stop and not ok then
        print(...)
        os.exit(1)
      elseif not ok then
        print(...)
      end
    end)(pcall(function ()
      if interp then
        execute(push(copy({}, interp), fp))
      elseif endswith(fp, ".lua") then
        runfile(fp, run_env)
      else
        execute(fp)
      end
    end))
  end
end
]],
    },

    {
      title = "toku test standalone mode",
      desc = table.concat({
        "Passing file or directory arguments to toku test bypasses the project ",
        "build entirely and hands them straight to the runner: -m maps to match, ",
        "-s to stop, and -i is split on whitespace into the interp argv. This is ",
        "the quick loop against an already-built tree, or against no tree at all ",
        "when the specs only need installed rocks; combined with toku exec it runs ",
        "inside the project's pinned lua_modules.",
      }),
      runnable = false,
      code = [[
$ toku test -m fracidx -s test/spec
Test:   test/spec/santoku/fracidx.lua

$ toku test -s -i "luajit -l santoku.profile" test/spec

$ toku exec toku test -m sqlite test/spec
]],
    },

    {
      title = "How the project harness drives it",
      desc = table.concat({
        "toku test with no file arguments builds the test tree, then its generated ",
        "run.sh invokes the standalone runner with every option at once: stop on ",
        "first failure, one interpreter subprocess per file ($LUA, plus -l ",
        "santoku.profile or santoku.trace when --profile or --trace was given), ",
        "and a match anchored to .lua so only Lua sources run from the rendered ",
        "tree. The WASM variant runs the same suite as bundled .js files under ",
        "node, and --single narrows the run to one spec, mapped to its .js twin ",
        "in WASM mode.",
      }),
      runnable = false,
      code = [[
toku test -s -i "$LUA $MODS" --match "^.*%.lua$" test/spec

toku test -s -i "node --expose-gc" test/spec

$ toku test --single test/spec/santoku/fracidx.lua
$ toku test --wasm --single test/spec/santoku/fracidx.lua
Test:   test/spec/santoku/fracidx.js
]],
    },

    {
      title = "Testing the tester",
      desc = table.concat({
        "The runner's own spec, verbatim and complete: it asserts the module is a ",
        "callable and that nonexistent paths are skipped without spawning ",
        "anything, with or without a match. A spec calling the runner from inside ",
        "a spec is safe precisely because of the contracts above: the missing ",
        "paths short-circuit before any execution, so nothing recurses and ",
        "nothing exits.",
      }),
      runnable = false,
      code = [[
local test = require("santoku.test")

local validate = require("santoku.validate")
local isfunction = validate.isfunction

local runner = require("santoku.test.runner")

test("runner is the callable entrypoint", function ()
  assert(isfunction(runner))
end)

test("non-existent paths are skipped without spawning", function ()
  runner({ "/no/such/spec/file.lua" })
  runner({ "/no/such/spec/file.lua" }, { match = "nomatch" })
end)
]],
    },

  },

}

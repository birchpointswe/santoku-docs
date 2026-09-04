return {

  intro = table.concat({
    "santoku is the base library of the framework: plain Lua 5.1 modules for arrays, ",
    "strings, tables, functions, numbers, ordering keys, errors, validation, time, ",
    "randomness, and async control flow, with no dependencies beyond Lua itself and ",
    "a few small C helpers. The tour below runs basics to advanced, and every ",
    "example is live: edit the code and press Run to execute it right here, in a ",
    "Lua interpreter compiled to WebAssembly.",
  }),

  examples = {

    {
      title = "santoku.array: pipelines",
      desc = "In-place array pipelines: build a range, filter it, map it, fold it.",
      code = [[
local arr = require("santoku.array")
local t = arr.range(1, 10)
arr.filter(t, function (v)
  return v % 2 == 0
end)
arr.map(t, function (v)
  return v * v
end)
print("squares:", arr.concat(t, ", "))
return arr.sum(t)
]],
    },

    {
      title = "santoku.array: in-place or copying, your choice",
      desc = table.concat({
        "Most transforms come in pairs: sort/sorted, map/mapped, filter/filtered. ",
        "The bare name mutates its argument, the -ed form returns a fresh table. ",
        "sort takes either a comparator or an options table with unique = true.",
      }),
      code = [[
local arr = require("santoku.array")
local words = { "pear", "fig", "apple", "banana" }
local by_len = arr.sorted(words, function (a, b)
  return #a < #b
end)
print("shortest first:", arr.concat(by_len, " "))
print("original intact:", arr.concat(words, " "))
local dedup = arr.sort({ 3, 1, 2, 3, 1 }, { unique = true })
print("sorted unique:", arr.concat(dedup, " "))
local caps = arr.mapped(words, string.upper)
print("mapped copy:", arr.concat(caps, " "))
print("middle:", arr.concat(arr.slice(words, 2, 3), " "))
print("last two:", arr.concat(arr.takelast(words, 2), " "))
return arr.concat(arr.reverse(arr.filtered(words, function (w)
  return #w > 3
end)), " ")
]],
    },

    {
      title = "santoku.array: stacks, queues, and edits",
      desc = table.concat({
        "push/pop and shift make stacks and queues; insert, remove, find, and ",
        "includes edit and query; tabulate turns a positional row into a named ",
        "record, with a rest key for the tail.",
      }),
      code = [[
local arr = require("santoku.array")
local stack = {}
arr.push(stack, "a", "b", "c")
local _, top = arr.pop(stack)
print("popped:", top)
local queue = { "first", "second", "third" }
local _, head = arr.shift(queue)
print("shifted:", head)
arr.insert(queue, 1, "zeroth")
arr.remove(queue, 2, 2)
print("queue:", arr.concat(queue, " "))
local v, i = arr.find(queue, function (x)
  return x == "third"
end)
print("found:", v, "at index", i)
print("includes:", arr.includes(queue, "third", "missing"))
local row = { "Ada", "Lovelace", 1815, "London", "mathematics" }
local person = arr.tabulate(row, { rest = "tags" }, "first", "last", "born")
print("record:", person.first, person.last, person.born)
return arr.concat(person.tags, ", ")
]],
    },

    {
      title = "santoku.array: grouping and reshaping",
      desc = table.concat({
        "group buckets by a key function, partition splits on a predicate, ",
        "zip/unzip pair and unpair, chunked windows, flatten unnests, and ",
        "uniqued dedups without sorting.",
      }),
      code = [[
local arr = require("santoku.array")
local nums = arr.range(1, 10)
local by_parity = arr.group(nums, function (v)
  return v % 2 == 0 and "even" or "odd"
end)
print("evens:", arr.concat(by_parity.even, " "))
local small, large = arr.partition(nums, function (v)
  return v <= 5
end)
print("small:", arr.concat(small, " "))
print("large:", arr.concat(large, " "))
local zipped = arr.zip({ "x", "y", "z" }, { 1, 2, 3 })
print("second pair:", zipped[2][1], zipped[2][2])
local letters, values = arr.unzip(zipped)
print("unzipped:", arr.concat(letters, ""), arr.concat(values, ""))
local windows = arr.chunked(nums, 4)
print("chunks:", #windows, "last:", arr.concat(windows[#windows], " "))
local flat = arr.flatten({ 1, { 2, 3 }, { 4, { 5 } } })
print("flattened one level:", #flat, "items")
return arr.concat(arr.uniqued({ 1, 2, 2, 3, 3, 3 }), " ")
]],
    },

    {
      title = "santoku.array: numbers in tables",
      desc = table.concat({
        "Arrays of numbers get sum, mean, max/min (value and index), plus small ",
        "vector math: dot products, magnitudes, scalar and elementwise arithmetic. ",
        "Range arguments let every one of these work on a slice without copying.",
      }),
      code = [[
local arr = require("santoku.array")
local xs = { 3, 1, 4, 1, 5, 9, 2, 6 }
print("sum:", arr.sum(xs), "mean:", arr.mean(xs))
local m, mi = arr.max(xs)
print("max:", m, "at index", mi)
print("mean of first four:", arr.mean(xs, 1, 4))
local a = { 1, 2, 3 }
local b = { 4, 5, 6 }
print("dot:", arr.dot(a, b))
print("magnitude:", arr.magnitude({ 3, 4 }))
arr.scale(a, 10)
print("scaled:", arr.concat(a, " "))
arr.addv(a, b)
print("elementwise sum:", arr.concat(a, " "))
arr.add(b, 100)
return arr.concat(b, " ")
]],
    },

    {
      title = "santoku.array: lifting iterators",
      desc = table.concat({
        "The i-prefixed functions consume any Lua iterator (gmatch, ipairs, your ",
        "own) without building an intermediate table first: imap, ifilter, ",
        "ireduce, and icollect with an optional limit.",
      }),
      code = [[
local arr = require("santoku.array")
local words = arr.imap(string.upper, ("lift map over any iterator"):gmatch("%a+"))
print("mapped:", arr.concat(words, " "))
local long = arr.ifilter(function (w)
  return #w > 3
end, ("one two three four"):gmatch("%a+"))
print("filtered:", arr.concat(long, " "))
local first3 = arr.icollect(3, ("a b c d e"):gmatch("%a+"))
print("first three:", arr.concat(first3, " "))
return arr.ireduce(function (acc, field)
  return acc + #field
end, 0, ("ab,cde,f"):gmatch("[^,]+"))
]],
    },

    {
      title = "santoku.string: splitting and matching",
      desc = table.concat({
        "splits cuts on a Lua pattern; pass true as the third argument to keep ",
        "the delimiters as their own elements. matches collects every match of ",
        "a pattern into an array.",
      }),
      code = [[
local str = require("santoku.string")
local arr = require("santoku.array")
local parts = str.splits("one,two,three", ",")
print("fields:", #parts, arr.concat(parts, "|"))
local kept = str.splits("key=value", "=", true)
print("with delimiter:", arr.concat(kept, " "))
local nums = arr.map(str.matches("10 39.5 46.8", "%S+"), tonumber)
print("parsed sum:", nums[1] + nums[2] + nums[3])
return arr.concat(str.splits("path/to/some/file.lua", "/"), " > ")
]],
    },

    {
      title = "santoku.string: interp and parse",
      desc = table.concat({
        "interp interpolates by name, position, or with printf formats via ",
        "%fmt#(key); parse is its inverse, mapping capture groups tagged with ",
        "#(key) into a named table.",
      }),
      code = [[
local str = require("santoku.string")
print(str.interp("Hello %who, %adj to meet you!", {
  who = "World",
  adj = "nice",
}))
print(str.interp("%1 %3 %2", { "a", "b", "c" }))
print(str.interp("pi is %.3f#(pi)", { pi = math.pi }))
print(str.interp("%(num_to_display)", { num_to_display = 7 }))
local t = str.parse("2023-10-26 09:10:26",
  "(%d+)#(year)-(%d+)#(month)-(%d+)#(day) (%d+)#(hour):(%d+)#(min):(%d+)#(sec)")
print("year:", t.year, "hour:", t.hour)
return t.month
]],
    },

    {
      title = "santoku.string: predicates and trimming",
      desc = table.concat({
        "Everyday string chores: prefix and suffix tests, trimming with custom ",
        "patterns, common prefixes across many strings, occurrence counts, and ",
        "human-readable number formatting.",
      }),
      code = [[
local str = require("santoku.string")
print("starts:", str.startswith("santoku.array", "santoku."))
print("ends:", str.endswith("init.lua", ".lua"))
print("trimmed:", "[" .. str.trim("  padded  ") .. "]")
print("custom trim:", str.trim("__flag__", "_*"))
print("stripped:", str.stripprefix("santoku.array", "santoku."))
print("common:", str.commonprefix("santoku.array", "santoku.string", "santoku.table"))
print("count:", str.count("banana", "an"))
print("empty:", str.isempty("   "), str.isempty("x"))
return str.format_number(1234567.89)
]],
    },

    {
      title = "santoku.string: hashing and encodings",
      desc = table.concat({
        "The C core merged into santoku.string covers SHA-256 digests, hex, ",
        "base64 (plain and URL-safe), percent-encoding, and parsing a number out ",
        "of the middle of a string.",
      }),
      code = [[
local str = require("santoku.string")
local digest = str.sha256("hello")
print("sha256:", str.to_hex(digest))
local b64 = str.to_base64("hello, world")
print("base64:", b64)
print("decoded:", str.from_base64(b64))
print("url-safe:", str.to_base64_url("data?with=symbols"))
local enc = str.to_url("a value & more")
print("percent-encoded:", enc)
print("round trip:", str.from_url(enc))
print("number at offset 2:", str.number("v1.25-beta", 2))
return str.to_hex("\1\2\255")
]],
    },

    {
      title = "santoku.string: URLs and query strings",
      desc = table.concat({
        "parse_url decomposes a URL into scheme, host, port, path segments, ",
        "typed params (numbers and booleans are converted), and fragment; ",
        "encode_url rebuilds one, and to_query/from_query handle bare query ",
        "strings.",
      }),
      code = [[
local str = require("santoku.string")
local u = str.parse_url("https://example.com:8080/docs/intro?page=2&dark=true#usage")
print("scheme:", u.scheme, "host:", u.host, "port:", u.port)
print("path:", table.concat(u.path, "/"))
print("params:", u.params.page, u.params.dark)
print("fragment:", u.fragment)
u.params.page = u.params.page + 1
u.search = nil
print("rebuilt:", str.encode_url(u))
local q = str.from_query("?limit=10&q=lua")
print("typed:", q.limit + 5, q.q)
return str.to_query({ sort = "asc" })
]],
    },

    {
      title = "santoku.table: paths into nested tables",
      desc = table.concat({
        "get, set, and update address deep keys as a path array, creating ",
        "intermediate tables on the way down; merge fills in missing keys ",
        "recursively without clobbering what is already there.",
      }),
      code = [[
local tbl = require("santoku.table")
local cfg = { server = { host = "localhost" } }
tbl.set(cfg, { "server", "ports", 1 }, 8080)
tbl.update(cfg, { "server", "ports", 1 }, function (p)
  return p + 1
end)
tbl.merge(cfg, {
  server = { host = "ignored", scheme = "https" },
})
print("host:", tbl.get(cfg, { "server", "host" }))
print("scheme:", tbl.get(cfg, { "server", "scheme" }))
print("missing is nil:", tbl.get(cfg, { "server", "tls", "cert" }))
return tbl.get(cfg, { "server", "ports", 1 })
]],
    },

    {
      title = "santoku.table: dictionaries as data",
      desc = table.concat({
        "keys, vals, and entries project a map into arrays; from indexes an ",
        "array by a key function; invert flips keys and values; equals compares ",
        "deeply and, on mismatch, tells you why.",
      }),
      code = [[
local tbl = require("santoku.table")
local arr = require("santoku.array")
local ages = { ada = 36, alan = 41, grace = 85 }
print("keys:", arr.concat(arr.sort(tbl.keys(ages)), " "))
print("total:", arr.sum(tbl.vals(ages)))
local by_letter = tbl.from({ "lua", "santoku" }, function (s)
  return s:sub(1, 1)
end)
print("l:", by_letter.l, "s:", by_letter.s)
local flipped = tbl.invert({ a = 1, b = 2 })
print("flipped:", flipped[1], flipped[2])
print("deep equal:", tbl.equals({ x = { 1, 2 } }, { x = { 1, 2 } }))
local _, why = tbl.equals({ x = 1 }, { x = 2 })
return why
]],
    },

    {
      title = "santoku.functional",
      desc = table.concat({
        "Function combinators: bind for partial application, compose, const, ",
        "sel and take to reshape argument lists, choose as an expression-level ",
        "branch, and get to turn a field name into an accessor.",
      }),
      code = [[
local fun = require("santoku.functional")
local arr = require("santoku.array")
local function add (a, b)
  return a + b
end
local inc = fun.bind(add, 1)
local function double (x)
  return x * 2
end
print("compose:", fun.compose(double, inc)(10))
local from_second = fun.sel(fun.id, 2)
print("sel:", from_second("a", "b", "c"))
local print1 = fun.take(print, 1)
print1("kept", "dropped", "dropped")
print("choose:", fun.choose(1 > 2, "yes", "no"))
local names = arr.mapped({ { name = "ada" }, { name = "alan" } }, fun.get("name"))
print("names:", arr.concat(names, " "))
return fun.const(42)()
]],
    },

    {
      title = "santoku.num",
      desc = table.concat({
        "Rounding to integers or steps, decimal truncation, and exponential ",
        "moving averages; the module also re-exports all of math, so num is a ",
        "drop-in superset.",
      }),
      code = [[
local num = require("santoku.num")
print("round:", num.round(2.5), num.round(2.4))
print("round to 0.25 steps:", num.round(0.30, 0.25))
print("trunc to 3 decimals:", num.trunc(math.pi, 3))
local avg = num.mavg(0.5)
print("mavg:", avg(10), avg(20), avg(30))
print("math included:", num.floor(num.pi), num.max(3, 7))
return num.round(math.pi * 100) / 100
]],
    },

    {
      title = "santoku.fracidx: fractional order keys",
      desc = table.concat({
        "Order keys that sort lexically: insert between any two items without ",
        "renumbering the rest. between_n generates a balanced batch, and ",
        "validate rejects malformed keys. This is how to order list ",
        "items under concurrent edits.",
      }),
      code = [[
local fracidx = require("santoku.fracidx")
local first = fracidx.between(nil, nil)
local second = fracidx.between(first, nil)
local middle = fracidx.between(first, second)
print("first:", first)
print("second:", second)
print("middle:", middle)
print("ordered:", first < middle and middle < second)
local batch = fracidx.between_n(first, second, 3)
print("batch of 3:", table.concat(batch, " "))
print("bad key rejected:", pcall(fracidx.validate, "0oops"))
return fracidx.between(middle, second)
]],
    },

    {
      title = "santoku.error: errors with structure",
      desc = table.concat({
        "error and assert carry multiple values instead of one string; pcall ",
        "returns them all, xpcall hands them to your handler, and wrapnil ",
        "converts nil-plus-message APIs into throwing ones. Outside any pcall ",
        "the values collapse to a readable colon-joined message.",
      }),
      code = [[
local err = require("santoku.error")
local ok, tag, detail, code = err.pcall(function ()
  err.error("db", "connection refused", 111)
end)
print("caught:", ok, tag, detail, code)
local _, val = err.pcall(function ()
  return err.assert(tonumber("42"), "not a number")
end)
print("assert passes values through:", val)
local open = err.wrapnil(function (path)
  return nil, "no such file: " .. path
end)
print("wrapnil:", err.pcall(open, "missing.txt"))
local function div (a, b)
  if b == 0 then
    err.error("divide by zero", a)
  end
  return a / b
end
return err.xpcall(function ()
  return div(1, 0)
end, function (msg)
  return "handled: " .. msg
end)
]],
    },

    {
      title = "santoku.op: operators as functions",
      desc = table.concat({
        "Every Lua operator as a named function, ready to hand to reduce, sort, ",
        "and mapped without writing a wrapper lambda each time.",
      }),
      code = [[
local op = require("santoku.op")
local arr = require("santoku.array")
print("sum:", arr.reduce({ 1, 2, 3, 4 }, op.add))
print("product:", arr.reduce({ 1, 2, 3, 4 }, op.mul))
local words = arr.sort({ "pear", "fig", "apple" }, op.gt)
print("descending:", arr.concat(words, " "))
print("lengths:", arr.concat(arr.mapped({ "ab", "cdef" }, op.len), " "))
print("logic:", op["not"](nil), op.neg(5))
return op.cat("santoku", ".op")
]],
    },

    {
      title = "santoku.validate: checks that explain themselves",
      desc = table.concat({
        "Every validator returns true, or false plus a reason and the offending ",
        "values, which slots straight into error.assert: a failed check throws ",
        "a structured error with the full context attached.",
      }),
      code = [[
local validate = require("santoku.validate")
local err = require("santoku.error")
print(validate.isnumber(42))
print(validate.isnumber("42"))
print(validate.between(5, 1, 10))
print(validate.isarray({ 1, 2, 3 }))
print(validate.isarray({ 1, 2, x = 3 }))
local function set_port (cfg, port)
  err.assert(validate.istable(cfg))
  err.assert(validate.between(port, 1, 65535))
  cfg.port = port
  return cfg
end
local ok, msg, bad = err.pcall(set_port, {}, 99999)
print(ok, msg, bad)
return msg
]],
    },

    {
      title = "santoku.utc: time without timezones",
      desc = table.concat({
        "Epoch seconds in and out (optionally sub-second), broken-down UTC ",
        "dates, strftime formatting, calendar-aware shift and trunc, and a ",
        "stopwatch closure for quick timings.",
      }),
      code = [[
local utc = require("santoku.utc")
local now = utc.time()
print("epoch:", now)
print("precise:", utc.time(true))
local d = utc.date(now)
print("today:", d.year, d.month, d.day)
print("iso:", utc.format(now, "%Y-%m-%dT%H:%M:%SZ"))
print("tomorrow:", utc.format(utc.shift(now, 1, "day"), "%Y-%m-%d"))
print("midnight:", utc.format(utc.trunc(now, "day"), "%H:%M:%S"))
local lap = utc.stopwatch()
local duration, total = lap()
print("elapsed:", duration, total)
]],
    },

    {
      title = "santoku.random",
      desc = table.concat({
        "Seeding, random strings and alphanumerics, a clamped normal variate, ",
        "and a fast seedable PRNG from C (fast_seed, fast_random, fast_max) for ",
        "when math.random is the bottleneck. Requiring the module seeds both ",
        "generators from process entropy, so distinct processes produce distinct ",
        "streams without any setup; call seed or fast_seed with an explicit value ",
        "only when you want a reproducible run. alnum draws from the 62 ASCII ",
        "alphanumerics, while str draws from a raw byte range and will include ",
        "punctuation. C extensions that include <santoku/lua/utils.h> and call ",
        "tk_fast_random directly are a separate case: that generator is thread local ",
        "and starts from a fixed constant, so seed it once with ",
        "tk_fast_seed(tk_fast_entropy()) in your luaopen, or every process will ",
        "produce the same sequence.",
      }),
      code = [[
local random = require("santoku.random")
random.seed()
print("die roll:", random.num(1, 6))
print("string:", random.str(8))
print("alnum:", random.alnum(12))
print("normal-ish:", random.norm())
random.fast_seed(42)
print("fast:", random.fast_random())
print("fast max:", random.fast_max)
]],
    },

    {
      title = "santoku.async: callbacks without the pyramid",
      desc = table.concat({
        "Continuation-passing helpers that flatten callback code: pipe chains ",
        "steps and short-circuits on failure, events is a tiny synchronous ",
        "emitter, and each/map/all walk collections through async functions.",
      }),
      code = [[
local async = require("santoku.async")
async.pipe(
  function (done)
    done(true, 2)
  end,
  function (done, x)
    done(true, x * 10)
  end,
  function (ok, result)
    print("pipe:", ok, result)
  end)
local events = async.events()
events.on("save", function (id)
  print("saved:", id)
end)
events.emit("save", 42)
async.each({ "a", "b" }, function (done, v, i)
  print("item:", i, v)
  done(true)
end, function (ok)
  print("all done:", ok)
end)
]],
    },

    {
      title = "santoku.serialize: tables to Lua source",
      desc = table.concat({
        "Calling the module serializes any value, tables included, to Lua ",
        "source that round-trips through loadstring; requiring ",
        "santoku.autoserialize patches print so every printed table shows its ",
        "contents instead of an address.",
      }),
      code = [[
local serialize = require("santoku.serialize")
local src = serialize({
  name = "example",
  tags = { "lua", "pwa" },
  nested = { deep = true },
})
print(src)
local restored = loadstring("return " .. src)()
print("round trip:", restored.name, restored.tags[2])
require("santoku.autoserialize")
print({ now = { tables = "print readably" } })
]],
    },

    {
      title = "The long tail: co, inherit, geo, env",
      desc = table.concat({
        "santoku.co builds tagged coroutine sets that nest without stealing ",
        "each other's yields, inherit manages __index chains, geo does planar ",
        "and great-circle math, and env reads variables with defaults. bench, ",
        "test, and tracer round out the toolbox for timing and test scripts.",
      }),
      code = [[
local inherit = require("santoku.inherit")
local base = { greet = function () return "hello" end }
local child = inherit.pushindex({}, base)
print("inherited:", child.greet())
local geo = require("santoku.geo")
local tampa = { lat = 27.95, lon = -82.46 }
local albany = { lat = 42.65, lon = -73.75 }
print("km apart:", geo.earth_distance(tampa, albany))
print("angle:", geo.angle({ x = 0, y = 0 }, { x = 1, y = 1 }))
local env = require("santoku.env")
print("editor:", env.var("EDITOR", "vi"))
local co = require("santoku.co")()
local gen = co.wrap(function ()
  co.yield(1)
  co.yield(2)
end)
print("yields:", gen(), gen())
]],
    },

  },

}

return {

  intro = table.concat({
    "santoku.sqlite.sync makes tables you already have syncable between peers. You ",
    "describe which tables and columns participate, and create generates the ",
    "triggers that capture every ordinary SQL write: no funnel, no setters, no ",
    "change to how the application writes. Conflicts resolve last-writer-wins over a ",
    "hybrid logical clock stored as a fixed-width string, so causal order is plain ",
    "string comparison and SQLite itself can do the comparing. Sync is symmetric and ",
    "peer to peer. The module produces and consumes plain Lua tables and never opens ",
    "a socket; the application ships the bytes over HTTP, a websocket, or a file on a ",
    "USB stick. That is also why the examples below run right here: two peers ",
    "converging is two in-memory databases and some function calls, with no network ",
    "involved at all. Encryption, the additional authenticated data that binds it, ",
    "what happens when a record will not decrypt, and how to write without ",
    "syncing are all application choices, and all of them are shown below.",
  }),

  examples = {

    {
      title = "Enabling sync on a table that already has rows",
      desc = table.concat({
        "create takes the db wrapper and a config naming each table's primary key ",
        "and the columns that participate. Columns you leave out stay local and ",
        "never travel. It emits a shadow table per synced table, installs the ",
        "triggers, and backfills the rows already present so existing data joins ",
        "sync without a migration. It is idempotent: run it on every startup after ",
        "your migrations, exactly like sqlite_migrate.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local db = sql(sqlite.open_memory())
db.exec([==[
  create table notes (
    id text primary key,
    title text not null default '',
    draft text
  )
]==])

local add = db.runner("insert into notes (id, title) values (?1, ?2)")
add("n1", "already here")
add("n2", "also here")

local s = sync.create(db, {
  space = "demo",
  tables = {
    notes = { pk = { "id" }, columns = { "title" } },
  },
})

local tracked = db.getter("select count(*) from notes_sync")
print("replica:", s.id())
print("rows tracked after backfill:", tracked())
return tracked()
]],
    },

    {
      title = "Adopting rows that already carry a version",
      desc = table.concat({
        "Backfill normally stamps every pre-existing row with the current clock, ",
        "which is fine for data that has never been synced and wrong for data ",
        "that has. If you are migrating from something that already tracked a ",
        "version per row, point seed at that column and backfill adopts those ",
        "values instead, so a row that is genuinely old stays old and cannot ",
        "clobber a peer holding a newer edit. Rows whose seed value is null or ",
        "empty fall back to a minted clock, so a partially versioned table is ",
        "fine. Seeded values must be comparable with generated ones, meaning the ",
        "same fixed-width format, since the whole ordering rests on string ",
        "comparison. create also ratchets its clock past the highest seeded ",
        "value, otherwise the first local write after migrating would mint ",
        "something lower and lose.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local OLDER = "00000000000001.00000000.0000000000000001"
local NEWER = "00000000000002.00000000.0000000000000002"

local function peer (ver)
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text default '', ver text)")
  db.runner("insert into notes (id, title, ver) values (?1, ?2, ?3)")(
    "n1", "written at " .. ver, ver)
  local s = sync.create(db, {
    space = "demo",
    tables = {
      notes = { pk = { "id" }, columns = { "title" }, seed = "ver" },
    },
  })
  return { sync = s, title = db.getter("select title from notes where id = ?1") }
end

local a, b = peer(OLDER), peer(NEWER)
for _ = 1, 3 do
  a.sync.apply(b.sync.respond(a.sync.request(b.sync.id())))
  b.sync.apply(a.sync.respond(b.sync.request(a.sync.id())))
end

print("a holds:", a.title("n1"))
print("b holds:", b.title("n1"))
return a.title("n1") == b.title("n1")
]],
    },

    {
      title = "Ordinary SQL is captured, with nothing routed through the module",
      desc = table.concat({
        "The triggers fire on plain inserts, updates and deletes issued anywhere in ",
        "the application. An update stamps a new clock value on the same row; a ",
        "delete leaves a tombstone so the deletion can travel. Writing draft, which ",
        "is not in the config, does not stamp anything, so local-only columns cost ",
        "nothing.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local db = sql(sqlite.open_memory())
db.exec("create table notes (id text primary key, title text not null default '', draft text)")
local s = sync.create(db, {
  space = "demo",
  tables = { notes = { pk = { "id" }, columns = { "title" } } },
})

local tracked = db.getter("select count(*) from notes_sync")
local tombs = db.getter("select count(*) from notes_sync where del = 1")

db.exec("insert into notes (id, title) values ('n1', 'hello')")
print("after insert:", tracked(), "tracked,", s.seq(), "changes")

db.exec("update notes set title = 'hello again' where id = 'n1'")
print("after update:", tracked(), "tracked,", s.seq(), "changes")

db.exec("update notes set draft = 'unsynced column' where id = 'n1'")
print("after local-only write:", tracked(), "tracked,", s.seq(), "changes")

db.exec("delete from notes where id = 'n1'")
print("after delete:", tombs(), "tombstone,", s.seq(), "changes")
return tombs()
]],
    },

    {
      title = "Two peers converging, with no network",
      desc = table.concat({
        "This is the whole protocol. request builds what one peer wants, respond ",
        "answers it, apply merges the result. All three are plain Lua tables, so ",
        "the transport is whatever the application wants; here it is a function ",
        "call. Each peer starts with rows the other has never seen, and one ",
        "exchange in each direction converges them. Because everything is ",
        "in-process, this is also how you test a sync protocol without a network, ",
        "which is exactly how the module's own specs are written.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    settitle = db.runner("update notes set title = ?2 where id = ?1"),
    list = db.all("select id, title from notes order by id", true),
  }
end

local function pull (dst, src)
  return dst.sync.apply(src.sync.respond(dst.sync.request(src.sync.id())))
end

local a, b = peer(), peer()
a.add("a1", "written on a")
b.add("b1", "written on b")

local got = pull(a, b)
print("a applied", got.applied, "from b")
pull(b, a)

for _, r in ipairs(a.list()) do print("a holds:", r.id, r.title) end
for _, r in ipairs(b.list()) do print("b holds:", r.id, r.title) end
return #a.list()
]],
    },

    {
      title = "Concurrent edits, and a delete racing an edit",
      desc = table.concat({
        "Both peers edit the same row while apart. The clock decides, both sides ",
        "reach the same answer, and the loser stops propagating rather than ",
        "ping-ponging. A delete racing an edit resolves the same way, with the ",
        "tombstone winning ties so a deletion is not silently undone by a ",
        "simultaneous edit. This is last-writer-wins: the winner is deterministic, ",
        "but it is a choice, not a merge, and the losing edit is gone.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    settitle = db.runner("update notes set title = ?2 where id = ?1"),
    drop = db.runner("delete from notes where id = ?1"),
    title = db.getter("select title from notes where id = ?1"),
    count = db.getter("select count(*) from notes"),
  }
end

local function pull (dst, src)
  return dst.sync.apply(src.sync.respond(dst.sync.request(src.sync.id())))
end

local function converge (x, y)
  for _ = 1, 8 do
    local p, q = pull(x, y), pull(y, x)
    if p.applied == 0 and q.applied == 0 then return end
  end
end

local a, b = peer(), peer()
a.add("n1", "seed")
a.add("n2", "second")
converge(a, b)

a.settitle("n1", "edited on a")
b.settitle("n1", "edited on b")
converge(a, b)
print("a sees:", a.title("n1"))
print("b sees:", b.title("n1"))

a.drop("n2")
b.settitle("n2", "edited while a deleted it")
converge(a, b)
print("rows on a:", a.count(), "rows on b:", b.count())
return a.title("n1") == b.title("n1")
]],
    },

    {
      title = "Shipping changes one way, for transports with no round trip",
      desc = table.concat({
        "request and respond assume the puller can ask. When it cannot, because ",
        "you are writing a file, sending an email attachment or dropping a blob in ",
        "a bucket, push builds a bundle from what that peer has not been told ",
        "about yet. apply treats it exactly like a response. Delivery is ",
        "at-least-once by design: push does not advance its own high-water mark, ",
        "so a bundle lost in transit is rebuilt next time. Call ack once you know ",
        "it landed. Applying the same bundle twice is safe, so a duplicate costs ",
        "nothing.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    count = db.getter("select count(*) from notes"),
  }
end

local a, b = peer(), peer()
a.add("n1", "first")

local bundle = a.sync.push(b.sync.id())
print("bundle carries", #bundle.changes, "change")

print("applied:", b.sync.apply(bundle).applied)
print("applied again:", b.sync.apply(bundle).applied)
print("rows on b:", b.count())

a.sync.ack(b.sync.id(), bundle.seq)
a.add("n2", "second")
print("next bundle carries", #a.sync.push(b.sync.id()).changes, "change")
return b.count()
]],
    },

    {
      title = "Finding real divergence, not just a count mismatch",
      desc = table.concat({
        "Comparing row counts tells you nothing when two peers hold the right ",
        "number of wrong rows. digest folds every tracked row into buckets, ",
        "compare names the buckets that differ, manifest lists what is in them, ",
        "and reconcile turns the other side's manifest into the exact set of rows ",
        "worth asking for. That set feeds the fetch option of request, which ",
        "returns those rows without disturbing the ordinary cursor. Two round ",
        "trips, bounded by what actually differs.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
  })
  return {
    db = db, sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    title = db.getter("select title from notes where id = ?1"),
  }
end

local function pull (dst, src)
  return dst.sync.apply(src.sync.respond(dst.sync.request(src.sync.id())))
end

local a, b = peer(), peer()
a.add("n1", "correct")
a.add("n2", "also correct")
pull(b, a)
pull(a, b)

print("buckets differing while healthy:", next(a.sync.compare(b.sync.digest())) == nil
  and "none" or "some")

b.db.exec("update notes set title = 'corrupted' where id = 'n1'")
b.db.exec([==[
  update notes_sync set hlc = '00000000000001.00000000.0000000000000000'
  where rid = json_array('n1')
]==])

local diff = a.sync.compare(b.sync.digest())
print("tables reported as differing:", diff.notes and #diff.notes or 0, "buckets")

local plan = b.sync.reconcile(a.sync.manifest(diff))
print("rows worth fetching:", #plan.fetch.notes)

b.sync.apply(a.sync.respond(b.sync.request(a.sync.id(), { fetch = plan.fetch })))
print("b now sees:", b.title("n1"))
return b.title("n1")
]],
    },

    {
      title = "Per-column resolution, when whole-row overwrites lose too much",
      desc = table.concat({
        "Row granularity, the default, treats a record as one value: the newest ",
        "write wins entirely, so an edit to one field discards a concurrent edit ",
        "to another. Setting granularity to column tracks a clock per column, so ",
        "two peers editing different fields of the same row both keep their edit. ",
        "It costs one extra tracking row per column that has ever changed, and it ",
        "does not merge concurrent edits to the SAME field, which still resolve ",
        "last-writer-wins.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer (granularity)
  local db = sql(sqlite.open_memory())
  db.exec("create table people (id text primary key, name text default '', phone text default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = {
      people = { pk = { "id" }, columns = { "name", "phone" }, granularity = granularity },
    },
  })
  return {
    sync = s,
    add = db.runner("insert into people (id, name, phone) values (?1, ?2, ?3)"),
    setname = db.runner("update people set name = ?2 where id = ?1"),
    setphone = db.runner("update people set phone = ?2 where id = ?1"),
    row = db.getter("select name || ' / ' || phone from people where id = ?1"),
  }
end

local function converge (x, y)
  for _ = 1, 8 do
    local p = x.sync.apply(y.sync.respond(x.sync.request(y.sync.id())))
    local q = y.sync.apply(x.sync.respond(y.sync.request(x.sync.id())))
    if p.applied == 0 and q.applied == 0 then return end
  end
end

for _, mode in ipairs({ "row", "column" }) do
  local a, b = peer(mode), peer(mode)
  a.add("p1", "Ada", "555-0100")
  converge(a, b)
  a.setname("p1", "Ada Lovelace")
  b.setphone("p1", "555-0199")
  converge(a, b)
  print(mode .. ":", a.row("p1"))
end
return true
]],
    },

    {
      title = "Rebuilding derived state when a change arrives",
      desc = table.concat({
        "apply writes the synced columns and nothing else, so anything your ",
        "application computes from them, a search index, a denormalised ",
        "projection, a cached count, is not maintained for you. Ordinary writes ",
        "go through your own code and can do that work inline; applied writes do ",
        "not, because the module is driving. after_apply is the callback for ",
        "that gap. It runs once per applied row, inside apply's transaction, ",
        "after the row is written, and receives the operation, the row id, the ",
        "decoded values (nil for a delete) and the winning clock. Two properties ",
        "worth knowing. Writes you make from inside it are NOT captured as local ",
        "changes, so recomputing a column cannot re-stamp the row and echo it ",
        "back to the peer it came from. And the clock is passed in, so if your ",
        "schema wants its own version column it can be mirrored here rather than ",
        "read out of the shadow table.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec([==[
    create table notes (
      id text primary key,
      title text not null default '',
      words integer not null default 0,
      version text
    )
  ]==])
  local derive = db.runner(
    "update notes set words = ?2, version = ?3 where json_array(id) = ?1")
  local s = sync.create(db, {
    space = "demo",
    tables = {
      notes = {
        pk = { "id" }, columns = { "title" },
        after_apply = function (op, rid, vals, hlc)
          if op == "delete" then return end
          local n = 0
          for _ in (vals.title or ""):gmatch("%S+") do n = n + 1 end
          derive(rid, n, hlc)
        end,
      },
    },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    row = db.getter("select title || ' -> ' || words from notes where id = ?1"),
    version = db.getter("select version from notes where id = ?1"),
  }
end

local a, b = peer(), peer()
a.add("n1", "four little words here")

local res = a.sync.respond(b.sync.request(a.sync.id()))
b.sync.apply(res)

print("receiver rebuilt:", b.row("n1"))
print("clock mirrored:", b.version("n1") == res.changes[1].hlc)
return b.row("n1")
]],
    },

    {
      title = "Encrypting what leaves the database",
      desc = table.concat({
        "Rows stay plaintext locally, and the codec hook encrypts only what goes ",
        "on the wire, so a relay can carry and merge changes it cannot read: ",
        "merging needs the row id and the clock, never the values. The additional ",
        "authenticated data binds each ciphertext to its space, table, row and ",
        "clock value, so a peer cannot move a payload onto another row or replay ",
        "it under a newer version. Pair it with a real AEAD from ",
        "santoku-monocypher; the toy codec here just shows the shape and the ",
        "binding. Note that row identifiers, clocks and tombstones remain visible ",
        "as metadata.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
    encode = function (v) return v.id .. "\30" .. v.title end,
    decode = function (s2)
      local id, title = s2:match("^(.-)\30(.*)$")
      return { id = id, title = title }
    end,
    codec = {
      enc = function (plain, aad) return aad .. "|" .. plain end,
      dec = function (ct, aad)
        local got, plain = ct:match("^(.-)|(.*)$")
        if got ~= aad then return nil, "auth_failed" end
        return plain
      end,
    },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    title = db.getter("select title from notes where id = ?1"),
  }
end

local a, b = peer(), peer()
a.add("n1", "confidential")

local res = a.sync.respond(b.sync.request(a.sync.id()))
local change = res.changes[1]
print("plaintext on the wire:", change.vals == nil and "none" or "leaked")
print("ciphertext present:", change.ct ~= nil)

b.sync.apply(res)
print("b decrypted:", b.title("n1"))
return b.title("n1")
]],
    },

    {
      title = "Writes that should not sync",
      desc = table.concat({
        "Triggers capture every write to a tracked column, which is usually what ",
        "you want and occasionally is not. Recomputing a cached or derived value ",
        "locally, or repairing a row, should not look like an edit worth sending ",
        "to every peer. quiet runs a function with capture suppressed: the write ",
        "lands, the clock does not move, and nothing resyncs. It nests safely and ",
        "restores suppression correctly if the function errors, so it is also safe ",
        "to use inside an apply hook.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local db = sql(sqlite.open_memory())
db.exec("create table notes (id text primary key, title text not null default '')")
local s = sync.create(db, {
  space = "demo",
  tables = { notes = { pk = { "id" }, columns = { "title" } } },
})

local add = db.runner("insert into notes (id, title) values (?1, ?2)")
local retitle = db.runner("update notes set title = ?2 where id = ?1")

add("n1", "hello")
print("changes after insert:", s.seq())

retitle("n1", "edited by the user")
print("after an ordinary edit:", s.seq())

s.quiet(function ()
  retitle("n1", "recomputed locally")
end)
print("after a quiet edit:", s.seq())

local title = db.getter("select title from notes where id = ?1")
print("the row did change:", title("n1"))
return s.seq()
]],
    },

    {
      title = "Surviving a record you cannot read",
      desc = table.concat({
        "A record that fails to decrypt is not hypothetical: a key rotation gone ",
        "wrong, a partial restore, or a hostile peer all produce one. By default ",
        "(on_codec_error = \"abort\") the whole batch is rolled back and the cursor ",
        "never advances, which is atomic but means one bad record halts sync ",
        "permanently. With \"quarantine\", the healthy records in the batch are ",
        "applied, the bad ones are reported in stats.unreadable with a reason, and ",
        "the cursor is held back so nothing is skipped over silently. The ",
        "application decides what to do next: surface it, discard the record, or ",
        "wait for a peer holding a readable copy.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local function peer (mode)
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "demo",
    on_codec_error = mode,
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
    encode = function (v) return v.id .. "\30" .. v.title end,
    decode = function (s2)
      local id, title = s2:match("^(.-)\30(.*)$")
      return { id = id, title = title }
    end,
    codec = {
      enc = function (plain, ad) return ad .. "|" .. plain end,
      dec = function (ct, ad)
        local got, plain = ct:match("^(.-)|(.*)$")
        if got ~= ad then return nil, "auth_failed" end
        return plain
      end,
    },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    count = db.getter("select count(*) from notes"),
  }
end

local src = peer("abort")
src.add("n1", "damaged in transit")
src.add("n2", "perfectly fine")

local dst = peer("quarantine")
local res = src.sync.respond(dst.sync.request(src.sync.id()))
for _, c in ipairs(res.changes) do
  if c.rid:find("n1", 1, true) then c.ct = "tampered|garbage" end
end

local stats = dst.sync.apply(res)
print("applied:", stats.applied, "unreadable:", #stats.unreadable)
print("reason:", stats.unreadable[1].reason)
print("rows that landed:", dst.count())
print("cursor held at:", stats.cursor)
return #stats.unreadable
]],
    },

    {
      title = "Binding ciphertext to your own identifiers",
      desc = table.concat({
        "The default additional authenticated data is ",
        "space:table:rid:hlc, where rid is the JSON-encoded primary key. That is ",
        "fine for a new database and wrong for an existing one: if you already ",
        "encrypt records under some other binding, matching it exactly is the ",
        "difference between adopting sync and re-encrypting every record you own. ",
        "The aad option lets you construct the string yourself. Keep whatever ",
        "identifies the record and its version in there; dropping the clock would ",
        "let a peer replay an old payload under a newer one.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local sync = require("santoku.sqlite.sync")

local seen = {}

local function peer ()
  local db = sql(sqlite.open_memory())
  db.exec("create table notes (id text primary key, title text not null default '')")
  local s = sync.create(db, {
    space = "account-7",
    tables = { notes = { pk = { "id" }, columns = { "title" } } },
    aad = function (space, _, rid, hlc)
      return space .. ":" .. (rid:match('^%["(.-)"%]$') or rid) .. ":" .. hlc
    end,
    encode = function (v) return v.id .. "\30" .. v.title end,
    decode = function (s2)
      local id, title = s2:match("^(.-)\30(.*)$")
      return { id = id, title = title }
    end,
    codec = {
      enc = function (plain, ad)
        seen[#seen + 1] = ad
        return ad .. "|" .. plain
      end,
      dec = function (ct, ad)
        local got, plain = ct:match("^(.-)|(.*)$")
        if got ~= ad then return nil, "auth_failed" end
        return plain
      end,
    },
  })
  return {
    sync = s,
    add = db.runner("insert into notes (id, title) values (?1, ?2)"),
    title = db.getter("select title from notes where id = ?1"),
  }
end

local a, b = peer(), peer()
a.add("n1", "bound to a bare id")

local res = a.sync.respond(b.sync.request(a.sync.id()))
print("aad used:", seen[1])
b.sync.apply(res)
print("decrypted on the other side:", b.title("n1"))
return seen[1]
]],
    },

    {
      title = "Behind OpenResty: create belongs in the worker",
      desc = table.concat({
        "Under nginx the rule from the server API page applies unchanged, and one ",
        "step further: create prepares statements, so it belongs in ",
        "init_worker_by_lua_file beside the connection, never in the master. It is ",
        "safe there because the DDL is create-if-not-exists and the backfill only ",
        "inserts rows it is missing, so every worker converges on the same state ",
        "and only the first does real work. The consequence is that every worker ",
        "opens a write transaction at boot, all at once, which makes busy_timeout ",
        "load-bearing rather than defensive. Measured on four workers over a ",
        "200,000 row table: at busy_timeout 30000 the first worker's backfill ",
        "takes 0.23s and the rest about 0.04s each, while at 100 the boot ",
        "collapses, with create failing on its first DDL statement and workers ",
        "left running without capture. Set it generously, as the server API page ",
        "does; sync does not retry, because a timeout that low also breaks the ",
        "ordinary pragma setup around it. apply is likewise a write transaction, ",
        "so concurrent workers applying batches depend on the same timeout, and ",
        "there contention is benign: it surfaces as a plain database-is-locked ",
        "error rather than anything silent.",
      }),
      runnable = false,
      lang = "lua",
      code = [[
local config = require("my-api.config")
local db = require("my-api.db")(config.db_file, { no_migrate = true })
local sync = require("santoku.sqlite.sync")

package.loaded["my-api.db.loaded"] = db
package.loaded["my-api.sync.loaded"] = sync.create(db.db, {
  space = "my-api",
  tables = {
    items = { pk = { "id" }, columns = { "name" } },
  },
})
]],
    },

  },

}

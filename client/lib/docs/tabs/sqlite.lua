return {

  intro = table.concat({
    "santoku-sqlite is the framework's SQLite binding: a small C core ",
    "(santoku.sqlite.db) over the SQLite C API, and a Lua wrapper (santoku.sqlite) ",
    "that turns prepared statements into reusable query closures with transaction ",
    "control. On top sit a carray virtual table that binds santoku-matrix vectors as ",
    "zero-copy SQL inputs, a TF/cosine search index (santoku.sqlite.search), and an ",
    "encrypting VFS that seals every byte on disk. The same C core compiles ",
    "unchanged to WebAssembly, where it additionally registers an OPFS-backed VFS ",
    "(opfs-coop): synchronous access handles held in a dedicated worker, one ",
    "cooperative Web Lock shared across tabs, and a pool of slot files. That wasm ",
    "build is what this page ships, so most examples below run live against ",
    "in-memory databases in your ",
    "browser. File persistence and the encryption key ceremony need a real ",
    "filesystem, so those examples are shown for reading.",
  }),

  examples = {

    {
      title = "open a database",
      desc = table.concat({
        "open_memory gives a connection userdata (nil on failure), and the wrapper turns it into a table of ",
        "factories. exec runs raw SQL including multi-statement scripts, the raw connection stays reachable at ",
        "db.db, and close finalizes every cached statement before closing the handle.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec([=[
  create table cities (name text, state text);
  create index cities_state on cities (state);
]=])
print("tables:", db.getter(
  "select count(*) from sqlite_master where type = 'table'")())
print("raw handle:", type(db.db))
db.close()
return "closed"
]],
    },

    {
      title = "runner and getter: prepared closures",
      desc = table.concat({
        "Each factory prepares its statement once and returns a closure you call with bind values. ",
        "runner executes for effect, getter fetches one row: with prop true a named table, otherwise ",
        "the column values themselves.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table cities (name text, state text)")
local addcity = db.runner("insert into cities (name, state) values (?, ?)")
addcity("Tampa", "Florida")
addcity("Albany", "New York")
local getcity = db.getter("select * from cities where name = ?", true)
local city = getcity("Tampa")
print("row:", city.name, city.state)
local getstate = db.getter("select state from cities where name = ?")
print("value:", getstate("Albany"))
return getstate("Tampa")
]],
    },

    {
      title = "prop: how rows come back",
      desc = table.concat({
        "The prop argument controls row shape everywhere: true yields a { column = value } table, false ",
        "discards the row (run for effect), and anything else, including omitting it, spreads the columns ",
        "as multiple return values.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table people (name text, age integer)")
db.runner("insert into people (name, age) values (?, ?)")("Ada", 36)
local get_cols = db.getter("select name, age from people where name = ?")
local name, age = get_cols("Ada")
print("spread:", name, age)
local get_row = db.getter("select name, age from people where name = ?", true)
local row = get_row("Ada")
print("table:", row.name, row.age)
local discard = db.getter("select name, age from people where name = ?", false)
print("discarded:", discard("Ada"))
return name
]],
    },

    {
      title = "named parameters",
      desc = table.concat({
        "Pass a single table and its string keys bind to :name parameters; keys without a matching ",
        "parameter are ignored. Positional and named styles are chosen per call, not per statement.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table cities (name text, state text)")
local add = db.runner("insert into cities (name, state) values (:name, :state)")
add({ name = "Tampa", state = "Florida" })
add({ name = "Miami", state = "Florida" })
local get = db.getter("select state from cities where name = :name")
print("state:", get({ name = "Tampa" }))
return get({ name = "Miami" })
]],
    },

    {
      title = "inserter: closures that return the rowid",
      desc = "inserter runs like a runner but hands back last_insert_rowid, which is how integer primary keys come home.",
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table notes (id integer primary key, body text)")
local add = db.inserter("insert into notes (body) values (?)")
local id1 = add("first")
local id2 = add("second")
print("rowids:", id1, id2)
local get = db.getter("select body from notes where id = ?")
print("fetched:", get(id2))
return id2
]],
    },

    {
      title = "iter: streaming rows",
      desc = table.concat({
        "iter returns a bind closure plus a resetter. Calling the closure binds and yields an iterator: ",
        "default prop spreads the columns per row, prop true yields tables. One closure holds one ",
        "statement, so use the resetter after abandoning a traversal early (each new bind also resets ",
        "first), and build two closures if you need two live cursors over the same SQL.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table cities (name text, state text)")
local add = db.runner("insert into cities (name, state) values (?, ?)")
add("Tampa", "Florida")
add("Miami", "Florida")
add("Albany", "New York")
local rows = db.iter("select name, state from cities order by name")
for name, state in rows() do
  print(name, state)
end
local bystate, reset = db.iter("select name from cities where state = ?")
for name in bystate("Florida") do
  print("first hit only:", name)
  break
end
reset()
return "done"
]],
    },

    {
      title = "all: collect rows",
      desc = table.concat({
        "all materialises the result: prop true collects named-table rows, the default collects just the ",
        "first column of each row into a flat list. Bind values go to the second call, so one factory ",
        "serves many queries.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table cities (name text, state text)")
local add = db.runner("insert into cities (name, state) values (?, ?)")
add("Tampa", "Florida")
add("Miami", "Florida")
add("Albany", "New York")
local rows = db.all("select name, state from cities order by name", true)()
print("rows:", #rows, "first:", rows[1].name)
local names = db.all("select name from cities where state = ? order by name")
print("florida:", table.concat(names("Florida"), ", "))
return #rows
]],
    },

    {
      title = "transactions",
      desc = table.concat({
        "transaction(fn, ...) begins, calls fn with the trailing arguments, commits on return and returns ",
        "fn's results; on error it rolls back and re-raises. A leading string picks the begin mode, and ",
        "nested calls simply run inline inside the outer transaction.",
      }),
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table t (n integer)")
local addn = db.runner("insert into t (n) values (?)")
local count = db.getter("select count(*) from t")
local total = db.transaction(function (a, b)
  addn(a)
  addn(b)
  return count()
end, 1, 2)
print("committed:", total)
local ok, e = err.pcall(db.transaction, function ()
  addn(3)
  err.error("boom")
end)
print("rolled back:", ok, e, "count still", count())
db.transaction("deferred", function ()
  db.transaction(function ()
    addn(4)
  end)
end)
print("nested commits once:", count())
return count()
]],
    },

    {
      title = "manual begin, commit, rollback",
      desc = table.concat({
        "For control flow that does not fit a closure, drive the transaction yourself. begin defaults to ",
        "immediate; pass deferred or exclusive to choose.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table t (n integer)")
local addn = db.runner("insert into t (n) values (?)")
local count = db.getter("select count(*) from t")
db.begin("immediate")
addn(1)
addn(2)
db.commit()
print("after commit:", count())
db.begin()
addn(3)
db.rollback()
print("after rollback:", count())
return count()
]],
    },

    {
      title = "errors carry the SQLite message and code",
      desc = table.concat({
        "The wrapper raises through santoku.error with errmsg and errcode from the connection, so ",
        "err.pcall recovers them as separate values. The module also exports the raw result constants ",
        "OK, ERROR, ROW, and DONE.",
      }),
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
local ok, msg, code = err.pcall(function ()
  return db.exec("not valid sql")
end)
print("ok:", ok)
print("message:", msg)
print("code:", code, code == sqlite.ERROR)
local ok2 = err.pcall(function ()
  return db.runner("select x from nope")
end)
print("prepare fails too:", ok2)
return code
]],
    },

    {
      title = "values across the boundary",
      desc = table.concat({
        "nil binds SQL null both ways, booleans bind as 0 or 1, numbers always bind as doubles (exact ",
        "for integers up to 2^53, and integer columns read back as plain Lua numbers), and strings are ",
        "byte-exact in both directions, embedded zeros included.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec("create table t (a, b, c, d)")
db.runner("insert into t (a, b, c, d) values (?, ?, ?, ?)")(
  nil, true, 1.5, "x\0y")
local a, b, c, d = db.getter("select a, b, c, d from t")()
print("null:", a)
print("boolean as int:", b)
print("number:", c)
print("bytes:", #d, d == "x\0y")
return #d
]],
    },

    {
      title = "a module of closures",
      desc = table.concat({
        "Prepare each statement once at module setup, then compose the closures inside one ",
        "transaction, running ",
        "every mutation path through db.transaction.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local db = sql(sqlite.open_memory())
db.exec([=[
  create table users (id integer primary key, email text unique);
  create table tokens (user_id integer, token text);
]=])
local get_user = db.getter("select * from users where email = ?", true)
local create_user = db.inserter("insert into users (email) values (?)")
local delete_user_tokens = db.runner("delete from tokens where user_id = ?")
local insert_token = db.runner("insert into tokens (user_id, token) values (?, ?)")
local function login (email, token)
  return db.transaction(function ()
    local user = get_user(email)
    local id = user and user.id or create_user(email)
    delete_user_tokens(id)
    insert_token(id, token)
    return id
  end)
end
print("first login:", login("a@example.com", "t1"))
print("second login:", login("a@example.com", "t2"))
return db.getter("select count(*) from tokens")()
]],
    },

    {
      title = "migrations",
      desc = table.concat({
        "santoku.sqlite.migrate (its own rock, santoku-sqlite-migrate) takes a { filename = sql } table, ",
        "sorts the names with numeric-aware ordering, and applies unseen ones inside one transaction, ",
        "recording each in a migrations table so reruns are idempotent. Embed the migration ",
        "files at build time and run this on every open, server side and in the browser.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local db = sql(sqlite.open_memory())
local migrations = {
  ["001-init.sql"] = "create table notes (id integer primary key, body text);",
  ["002-tags.sql"] = [=[
    create table tags (note_id integer, tag text);
    create index tags_note on tags (note_id);
  ]=],
}
migrate(db, migrations)
migrate(db, migrations)
migrations["003-drafts.sql"] =
  "alter table notes add column draft integer not null default 0;"
migrate(db, migrations)
print("applied:", db.getter("select count(*) from migrations")())
return db.all("select filename from migrations order by id")()
]],
    },

    {
      title = "carray: a vector as a table-valued input",
      desc = table.concat({
        "Pass a santoku-matrix vec where a parameter is expected and it is bound as a carray table of a ",
        "single value column, read zero-copy from the vec's backing store in rowid order. ivec binds as ",
        "int64, svec int32, fvec float, dvec double.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local db = sql(sqlite.open_memory())
db.exec("create table items (id integer primary key, label text)")
local add = db.runner("insert into items (id, label) values (?, ?)")
add(1, "alpha")
add(2, "beta")
add(3, "gamma")
add(4, "delta")
local pick = db.all(
  "select label from items where id in (select value from carray(?)) order by id")
local labels = pick(ivec.create({ 2, 4 }))
for i = 1, #labels do
  print("hit:", labels[i])
end
local above = db.all("select value from carray(?) where value > ?")
print("filtered:", table.concat(above(fvec.create({ 0.5, 2.5, 1.5 }), 1.0), ", "))
return #labels
]],
    },

    {
      title = "raw statements and carray slices",
      desc = table.concat({
        "db.db:prepare exposes the statement object: step, reset (which also clears bindings), ",
        "get_value, get_named_values, columns, bind_values, bind_names, and bind_carray(pidx, vec, ",
        "start, count), which binds a zero-copy slice and raises on out-of-range bounds. Compare step ",
        "results against the exported ROW and DONE constants.",
      }),
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local ivec = require("santoku.ivec")
local db = sql(sqlite.open_memory())
local stmt = db.db:prepare("select value from carray(?1) order by rowid")
local v = ivec.create({ 1, 2, 3, 4, 5 })
stmt:reset()
stmt:bind_carray(1, v, 1, 3)
while true do
  local res = stmt:step()
  if res == sqlite.ROW then
    print("value:", stmt:get_value(0))
  elseif res == sqlite.DONE then
    stmt:reset()
    break
  else
    err.error(db.db:errmsg(), db.db:errcode())
  end
end
return "done"
]],
    },

    {
      title = "cosine search from scratch with carray joins",
      desc = table.concat({
        "The whole TF/cosine index is plain SQL over carray inputs; this is the exact statement shape ",
        "santoku.sqlite.search prepares, inlined so it runs here. Token ids and weights stream in as ",
        "vecs, norms are precomputed per document, and one grouped join scores and ranks the corpus ",
        "(the build enables SQLite's math functions, so sqrt is available).",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local db = sql(sqlite.open_memory())
db.exec([=[
  create table docs_tf (id, token integer not null, tf real not null);
  create index docs_tf_tok on docs_tf (token);
  create table docs_doc (id, norm real not null, primary key (id));
]=])
local add_tf = db.runner([=[
  insert into docs_tf (id, token, tf)
  select ?1, t.value, w.value
  from carray(?2) t join carray(?3) w on t.rowid = w.rowid
]=])
local add_norm = db.runner([=[
  insert into docs_doc (id, norm)
  select ?1, sqrt(sum(w.value * w.value)) from carray(?2) w
]=])
local function add (id, tokens, weights)
  add_tf(id, tokens, weights)
  add_norm(id, weights)
end
add("a", ivec.create({ 1, 2, 3 }), fvec.create({ 1, 1, 1 }))
add("b", ivec.create({ 2, 3, 4 }), fvec.create({ 1, 1, 1 }))
add("c", ivec.create({ 5, 6 }), fvec.create({ 1, 1 }))
local query = db.all([=[
  select s.id as id, sum(s.tf * q.tf) /
    (d.norm * (select sqrt(sum(value * value)) from carray(?3))) as score
  from docs_tf s
  join (select t.value as token, w.value as tf
    from carray(?2) t join carray(?3) w on t.rowid = w.rowid) q
    on s.token = q.token
  join docs_doc d on d.id = s.id
  group by s.id order by score desc limit ?1
]=], true)
local hits = query(10, ivec.create({ 2, 3 }), fvec.create({ 1, 1 }))
for i = 1, #hits do
  print(hits[i].id, string.format("%.4f", hits[i].score))
end
return #hits
]],
    },

    {
      title = "search: the packaged TF cosine index",
      desc = table.concat({
        "santoku.sqlite.search wraps that SQL behind create, add, search, remove, and clear. Documents ",
        "are csr rows (token ids as columns, weights as values); re-adding an id reindexes it, and a csr ",
        "without values derives tf from token occurrence counts. Create one with ",
        "search.create(db, { name = \"search\" }).",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local search = require("santoku.sqlite.search")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local csr = require("santoku.csr")
local db = sql(sqlite.open_memory())
local idx = search.create(db, { name = "docs" })
idx.add({ "a", "b", "c" }, csr.create({
  offsets = ivec.create({ 0, 3, 6, 8 }),
  neighbors = ivec.create({ 1, 2, 3, 2, 3, 4, 5, 6 }),
  values = fvec.create({ 1, 1, 1, 1, 1, 1, 1, 1 }),
}))
local q = csr.create({
  offsets = ivec.create({ 0, 2 }),
  neighbors = ivec.create({ 2, 3 }),
  values = fvec.create({ 1, 1 }),
})
local hits = idx.search(q, 10)
for i = 1, #hits do
  print(hits[i].id, hits[i].score)
end
idx.remove({ "a" })
print("after remove:", #idx.search(q, 10))
idx.add({ "a" }, csr.create({
  offsets = ivec.create({ 0, 2 }),
  neighbors = ivec.create({ 7, 8 }),
  values = fvec.create({ 1, 1 }),
}))
print("reindexed elsewhere:", #idx.search(q, 10))
return #hits
]],
    },

    {
      title = "search: partitions and presence-only ranking",
      desc = table.concat({
        "partition = true (or a custom column name) namespaces every call by a leading key with full ",
        "isolation, which is how multi-tenant indexes share one table. weighted = false skips norms and ",
        "ranks by raw match count, and schema places the index tables in an attached database.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local search = require("santoku.sqlite.search")
local ivec = require("santoku.ivec")
local fvec = require("santoku.fvec")
local csr = require("santoku.csr")
local db = sql(sqlite.open_memory())
local function doc (tokens, weights)
  return csr.create({
    offsets = ivec.create({ 0, #tokens }),
    neighbors = ivec.create(tokens),
    values = weights and fvec.create(weights) or nil,
  })
end
local idx = search.create(db, { name = "p", partition = true })
idx.add("u1", { "doc1" }, doc({ 1, 2 }, { 1, 1 }))
idx.add("u2", { "doc2" }, doc({ 1, 2 }, { 1, 1 }))
print("u1 sees:", idx.search("u1", doc({ 1, 2 }, { 1, 1 }), 10)[1].id)
idx.clear("u1")
print("u1 cleared:", #idx.search("u1", doc({ 1, 2 }, { 1, 1 }), 10))
print("u2 intact:", #idx.search("u2", doc({ 1, 2 }, { 1, 1 }), 10))
local pres = search.create(db, { name = "pres", weighted = false })
pres.add({ "a", "b" }, csr.create({
  offsets = ivec.create({ 0, 3, 5 }),
  neighbors = ivec.create({ 1, 2, 3, 1, 4 }),
}))
local hits = pres.search(doc({ 1, 2, 3 }), 10)
print("by match count:", hits[1].id, hits[1].score)
return #hits
]],
    },

    {
      title = "files and persistence",
      desc = table.concat({
        "open(path) creates or reopens a database file (nil on failure, so wrap in assert), and ",
        "open_v2(path, vfs) additionally picks the VFS by name. The wasm flag reports which build you ",
        "are on; in the browser the default filesystem is memory-backed, so durable storage goes ",
        "through the OPFS story below.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local d1 = sql(err.assert(sqlite.open("app.db")))
d1.exec("create table if not exists t (n)")
d1.runner("insert into t (n) values (?)")(42)
d1.close()
local d2 = sql(err.assert(sqlite.open("app.db")))
print("persisted:", d2.getter("select n from t")())
d2.close()
print("wasm build:", sqlite.wasm)
return "done"
]],
    },

    {
      title = "encrypted databases",
      desc = table.concat({
        "open_encrypted seals every byte on disk with XChaCha20-Poly1305 under a 32-byte key: pages, ",
        "journal, and WAL all live in the same authenticated container (magic TKSQENC1), each block ",
        "write draws a fresh nonce, and the AAD binds the block index and a per-file salt, so tampered, ",
        "reordered, or transplanted blocks fail closed instead of decrypting. A wrong key or a ",
        "wrong-size key cannot read anything, and closing the connection releases the key.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local key = string.rep("\42", 32)
local db = sql(err.assert(sqlite.open_encrypted("notes.db", key)))
db.exec("create table if not exists notes (id integer primary key, body text)")
db.runner("insert into notes (body) values (?)")("sealed at rest")
print("rows:", db.getter("select count(*) from notes")())
db.close()
local wrong = string.rep("\7", 32)
local ok = err.pcall(function ()
  local raw = err.assert(sqlite.open_encrypted("notes.db", wrong))
  return sql(raw).getter("select count(*) from notes")()
end)
print("wrong key reads:", ok)
local nope, msg = sqlite.open_encrypted("notes.db", "tooshort")
print("bad key size:", nope, msg)
return "closed, key released"
]],
    },

    {
      title = "key registry and merged read connections",
      desc = table.concat({
        "Keys register per resolved path in a process-wide table: key_set before ATTACH lets one ",
        "connection span databases sealed under different keys, and key_clear evicts a key (in-flight ",
        "writes on a cleared key fail loudly rather than guessing). Attached databases inherit the ",
        "connection's VFS, so a plain connection can never read an encrypted attach; enc_vfs names the ",
        "encrypting VFS so even a :memory: main can host encrypted attaches as a merged read view.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local key_a = string.rep("A", 32)
local key_b = string.rep("B", 32)
err.assert(sqlite.key_set("a.db", key_a))
err.assert(sqlite.key_set("b.db", key_b))
local vfs = err.assert(sqlite.enc_vfs())
local merged = sql(err.assert(sqlite.open_v2(":memory:", vfs)))
merged.exec("attach database 'a.db' as s1")
merged.exec("attach database 'b.db' as s2")
print("all notes:", merged.getter([=[
  select count(*) from (
    select id from s1.notes union all select id from s2.notes)
]=])())
merged.exec("detach database s1")
merged.exec("detach database s2")
merged.close()
sqlite.key_clear("a.db")
sqlite.key_clear("b.db")
return "done"
]],
    },

    {
      title = "encrypted SQLite over OPFS in the browser",
      desc = table.concat({
        "In the wasm build the module registers the opfs-coop VFS: OPFS synchronous access handles in ",
        "a dedicated worker, one cooperative exclusive Web Lock shared across tabs, and a pool of slot ",
        "files that the encrypting VFS stacks on top of via the third parent-vfs argument. A complete ",
        "encrypted open sequence: a hashed filename, a derived ",
        "key, key_set then open_encrypted on the parent VFS, pragmas, then migrations. ",
        "When another tab held the lock and wrote in between, reset_cache drops the page cache and ",
        "resets statements so the next read sees the new state.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local path = "/d-0123abcd.db"
local key32 = string.rep("\1", 32)
err.assert(sqlite.key_set(path, key32, "opfs-coop"))
local raw = err.assert(sqlite.open_encrypted(path, key32, "opfs-coop"))
local db = sql(raw)
db.exec("pragma journal_mode = TRUNCATE")
db.exec("pragma synchronous = NORMAL")
db.exec("pragma temp_store = MEMORY")
db.exec("create table if not exists notes (id integer primary key, body text)")
db.runner("insert into notes (body) values (?)")("durable and sealed")
print("rows:", db.getter("select count(*) from notes")())
db.db:reset_cache()
db.close()
sqlite.key_clear(path, "opfs-coop")
return "done"
]],
    },

  },

}

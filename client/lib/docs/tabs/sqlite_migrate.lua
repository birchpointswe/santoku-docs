return {

  intro = table.concat({
    "santoku-sqlite-migrate is versioned schema migration in one function: pass a ",
    "santoku-sqlite handle and a table mapping names to SQL strings, and it applies ",
    "the ones that have not run yet, in version order, inside a single transaction, ",
    "recording each in a bookkeeping table. There is no down direction: the posture ",
    "is forward-only, append a new numbered migration and never edit an applied ",
    "one, and when a change is too deep to express as SQL over live data, wipe and ",
    "rebuild under a schema epoch instead, shown at the end. The first five ",
    "examples run live in this page against an ",
    "in-memory database; the consumer patterns after them touch files or build ",
    "machinery and are shown for reading.",
  }),

  examples = {

    {
      title = "the whole API: migrate(db, migrations)",
      desc = table.concat({
        "requiring santoku.sqlite.migrate returns one function. Keys name the migrations, values are SQL ",
        "scripts. It ensures a migrations(id integer primary key, filename text not null) table, applies ",
        "what is missing in version order, and records each name; id preserves application order. ",
        "The module's full spec: ",
        "https://github.com/birchpointswe/lua-santoku-sqlite-migrate/blob/master/test/spec/santoku/sqlite/migrate.lua",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local db = sql(sqlite.open_memory())
migrate(db, {
  ["0.0.1"] = "create table items (id integer primary key, name text);",
  ["0.0.2"] = "alter table items add column done integer not null default 0;",
})
db.runner("insert into items (name) values (?)")("write docs")
local applied = db.all("select id, filename from migrations order by id", true)()
for i = 1, #applied do
  print(applied[i].id, applied[i].filename)
end
return db.getter("select count(*) from items")()
]],
    },

    {
      title = "idempotent: re-running is a no-op",
      desc = table.concat({
        "Applied names are skipped, so calling migrate again with the same table does nothing, even when ",
        "a migration has side effects like inserting rows. That makes it safe to run unconditionally at ",
        "every startup, which is exactly how every consumer uses it.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local db = sql(sqlite.open_memory())
local m = {
  ["0.0.1"] = "create table c (n integer); insert into c (n) values (1);",
}
migrate(db, m)
migrate(db, m)
migrate(db, m)
return db.getter("select count(*) from c")()
]],
    },

    {
      title = "forward-only: append, never edit",
      desc = table.concat({
        "A later call with a superset applies only the new keys. Since applied migrations are matched by ",
        "name alone, editing the body of an already-applied migration changes nothing on existing ",
        "databases: new schema work is always a new numbered entry.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local db = sql(sqlite.open_memory())
local first = "create table d (n integer); insert into d (n) values (1);"
migrate(db, { ["0.0.1"] = first })
migrate(db, {
  ["0.0.1"] = first,
  ["0.0.2"] = "insert into d (n) values (2);",
})
local rows = db.all("select n from d order by n", true)()
for i = 1, #rows do
  print(rows[i].n)
end
return #rows
]],
    },

    {
      title = "version-aware ordering",
      desc = table.concat({
        "Keys sort with a comparator that compares digit runs as numbers, so 0.0.2 < 0.0.10 < 0.1.0 ",
        "rather than the lexical 0.0.10 first.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local db = sql(sqlite.open_memory())
local function log (v)
  return "create table if not exists log (seq integer primary key, name text);" ..
    " insert into log (name) values ('" .. v .. "');"
end
migrate(db, {
  ["0.0.2"] = log("0.0.2"),
  ["0.0.10"] = log("0.0.10"),
  ["0.1.0"] = log("0.1.0"),
})
local rows = db.all("select name from log order by seq", true)()
for i = 1, #rows do
  print(rows[i].name)
end
return #rows
]],
    },

    {
      title = "one transaction: all or nothing",
      desc = table.concat({
        "The whole batch runs inside one db.transaction. A failing migration rolls back every change ",
        "from that call, including migrations earlier in the same batch and their bookkeeping rows, so ",
        "a database is never left half-migrated: it stays exactly where the last successful call left ",
        "it. A non-table migrations argument raises immediately.",
      }),
      code = [[
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")
local err = require("santoku.error")
local db = sql(sqlite.open_memory())
migrate(db, { ["0.0.1"] = "create table a (n);" })
local ok = err.pcall(migrate, db, {
  ["0.0.1"] = "create table a (n);",
  ["0.0.2"] = "create table e (n);",
  ["0.0.3"] = "this is not valid sql;",
})
print("batch applied:", ok)
print("table e exists:", err.pcall(function ()
  db.exec("insert into e (n) values (1)")
end))
print("recorded:", db.getter("select count(*) from migrations")())
return err.pcall(migrate, db, "not a table")
]],
    },

    {
      title = "migrations are scripts, not statements",
      desc = table.concat({
        "Each value goes through db.exec, which runs multi-statement scripts, so one migration can ",
        "create tables, build indexes, backfill data, and drop what it replaced. Below, ",
        "0.0.2 adds a parent column and its index, and 0.0.6 replaces the sequence table ",
        "with durable hybrid-logical-clock state and seeds it.",
      }),
      runnable = false,
      code = [[
local migrate = require("santoku.sqlite.migrate")
migrate(db, {
  ["0.0.2.sql"] = [=[
    alter table records add column parent_id text;
    create index records_parent on records(parent_id);
  ]=],
  ["0.0.6.sql"] = [=[
    drop table hlc_seq;
    create table hlc_state (
      id integer primary key check (id = 1),
      pt integer not null,
      c integer not null
    );
    insert into hlc_state values (1, 0, 0);
  ]=],
})
]],
    },

    {
      title = "loading migrations from files at build time",
      desc = table.concat({
        "Consumers keep migrations as numbered .sql files and inline them with a santoku template: a ",
        ".tk.lua preamble reads res/migrations at build time, keys by basename (the version comparator ",
        "ignores the .sql suffix), and serializes the table into the emitted source. The shipped bundle ",
        "carries its schema with no filesystem access at runtime, which is what lets the same pattern ",
        "work inside a browser worker.",
      }),
      runnable = false,
      code = [[
<%
  local fs = require("santoku.fs")
  local serialize = require("santoku.serialize")
  local migrations = {}
  for fp in fs.files("res/migrations") do
    migrations[fs.basename(fp)] = fs.readfile(fp)
  end
  t_migrations = serialize(migrations, true)
%>

local migrate = require("santoku.sqlite.migrate")

migrate(db, <% return t_migrations %>) -- luacheck: ignore
]],
    },

    {
      title = "two migration sets, two moments",
      desc = table.concat({
        "A client that keeps one small plaintext index database plus many encrypted per-account ",
        "databases migrates them at different times. The index migrates once at worker boot, right ",
        "after its pragmas. Each account database migrates at open, inside a pcall that closes the ",
        "handle and clears the VFS key on failure, so a bad migration never leaves a key registered for ",
        "a broken database.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")

local index_migrations = {
  ["0.0.1"] = "create table accounts (id text primary key);",
}
local account_migrations = {
  ["0.0.1"] = "create table notes (id integer primary key, body text);",
}

local index_db = sql(err.assert(sqlite.open("index.db")))
index_db.exec("pragma journal_mode = TRUNCATE")
index_db.exec("pragma synchronous = NORMAL")
migrate(index_db, index_migrations)

local function open_account (path, key32, parent_vfs)
  local db = sql(err.assert(sqlite.open_encrypted(path, key32, parent_vfs)))
  local ok, e = err.pcall(function ()
    db.exec("pragma journal_mode = TRUNCATE")
    db.exec("pragma synchronous = NORMAL")
    migrate(db, account_migrations)
  end)
  if not ok then
    pcall(db.close)
    sqlite.key_clear(path, parent_vfs)
    err.error("account database open failed", tostring(e))
  end
  return db
end

return open_account
]],
    },

    {
      title = "server side: migrate on connection open",
      desc = table.concat({
        "A server wrapper opens its file database, sets pragmas (WAL, busy_timeout for concurrent ",
        "writers), and migrates unconditionally unless the caller opts out. Idempotence plus the single ",
        "transaction make this safe under OpenResty where many workers race to open the same file: one ",
        "applies, the rest skip.",
      }),
      runnable = false,
      code = [[
local err = require("santoku.error")
local sqlite = require("santoku.sqlite.db")
local sql = require("santoku.sqlite")
local migrate = require("santoku.sqlite.migrate")

local migrations = {
  ["0.0.1"] = "create table events (id integer primary key, at integer);",
}

return function (db_file, opts)
  opts = opts or {}
  local db = sql(err.assert(sqlite.open(db_file)))
  db.exec("pragma busy_timeout = 30000")
  db.exec("pragma journal_mode = WAL")
  db.exec("pragma synchronous = NORMAL")
  if not opts.no_migrate then
    migrate(db, migrations)
  end
  return db
end
]],
    },

    {
      title = "beyond migrations: the schema epoch wipe",
      desc = table.concat({
        "Forward-only migrations move a database ahead; they cannot rewrite history. When a format ",
        "change leaves existing rows unrepresentable, no SQL over them can produce valid new ones. ",
        "Instead of a data migration, record a schema epoch in the migrated database, and when the ",
        "stored epoch is behind the code's, delete every derived database minted under the old one and ",
        "let the source of truth rebuild them. The meta table read below is created by those same ",
        "index migrations. Migrations handle additive change; the epoch handles ",
        "everything they should not.",
      }),
      runnable = false,
      code = [[
local migrate = require("santoku.sqlite.migrate")

local EPOCH = "4"

return function (db, index_migrations, store)
  migrate(db, index_migrations)
  local get_epoch = db.getter("select value from meta where key = 'schema_epoch'")
  local set_epoch = db.runner(
    "insert or replace into meta (key, value) values ('schema_epoch', ?)")
  if get_epoch() ~= EPOCH then
    local paths = store.list_files()
    for i = 1, #paths do
      if paths[i]:match("^/d%-%x+%.db$") then
        store.delete_file(paths[i])
      end
    end
    set_epoch(EPOCH)
  end
end
]],
    },

  },

}

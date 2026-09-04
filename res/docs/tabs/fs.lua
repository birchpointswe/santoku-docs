return {

  intro = table.concat({
    "santoku-fs is the framework's filesystem library: whole-file and streamed ",
    "I/O, pure-string path helpers, directory traversal iterators, and a thin ",
    "POSIX C extension (santoku.fs.posix) whose primitives are merged, along with ",
    "stock io, into the santoku.fs table. Failures raise structured errors ",
    "through santoku.error (the OS message plus errno), so call sites use pcall ",
    "rather than checking nil, and errno constants like fs.ENOENT and fs.EEXIST ",
    "are exported for matching. It sits under every native part of the stack, ",
    "from toku build scripts to CLI tools. This page ships the library in its ",
    "wasm bundle, so most examples below run live against MEMFS, emscripten's ",
    "ephemeral in-memory filesystem: real files, directories, and errors, gone ",
    "when you leave the page. Hardlinks and symlinks are compiled out under ",
    "emscripten, and host-path idioms are meaningless in a browser, so those are ",
    "shown for reading.",
  }),

  examples = {

    {
      title = "path joins and names",
      desc = table.concat({
        "Pure string path work, no disk involved. join inserts separators only where needed (a trailing ",
        "slash on the left or a leading slash on the right suppresses the inserted one). dirname of a bare ",
        "name is the current directory, and basename of a path ending in a slash is nil.",
      }),
      code = [[
local fs = require("santoku.fs")
print("join:", fs.join("a/", "b"))
print("join:", fs.join("srv", "web", "assets"))
print("join:", fs.join("srv", "/web"))
print("dirname:", fs.dirname("/opt/bin/sort"))
print("dirname:", fs.dirname("stdio.h"))
print("dirname:", fs.dirname("../../test"))
print("basename:", fs.basename("/opt/bin/sort"))
print("basename:", fs.basename("stdio.h"))
print("basename:", fs.basename("/home/user/"))
return fs.join("a", "b", "c")
]],
    },

    {
      title = "extensions",
      desc = table.concat({
        "extension takes the last dot segment, extensions takes everything from the first dot, and the ",
        "strip variants remove them. splitexts iterates the extension parts, bare or with keep_dots. ",
        "A name with no dot gives nil.",
      }),
      code = [[
local fs = require("santoku.fs")
print("extension:", fs.extension("release.tar.gz"))
print("extensions:", fs.extensions("release.tar.gz"))
print("stripextension:", fs.stripextension("release.tar.gz"))
print("stripextensions:", fs.stripextensions("release.tar.gz"))
print("no dot:", fs.extension("Makefile"))
local exts = {}
for e in fs.splitexts("/this/test.tar.gz", true) do
  exts[#exts + 1] = e
end
print("splitexts:", table.concat(exts, " "))
return fs.stripextensions("release.tar.gz")
]],
    },

    {
      title = "splitting and stripping parts",
      desc = table.concat({
        "splitparts iterates path components, collapsing repeated slashes; a delim of right or left keeps ",
        "the separators attached to one side. stripparts drops n leading components, returns the path ",
        "unchanged for 0, and nil when n consumes everything.",
      }),
      code = [[
local fs = require("santoku.fs")
local plain = {}
for p in fs.splitparts("/deploy//web/assets/") do
  plain[#plain + 1] = p
end
print("parts:", table.concat(plain, " "))
local right = {}
for p in fs.splitparts("/deploy//web/assets/", "right") do
  right[#right + 1] = p
end
print("right:", table.concat(right, " "))
print("strip 2:", fs.stripparts("/home/user/a/b/c.txt", 2))
print("strip 4:", fs.stripparts("/home/user/a/b/c.txt", 4))
print("strip 0:", fs.stripparts("/home/user/a/b/c.txt", 0))
print("strip 5:", fs.stripparts("/home/user/a/b/c.txt", 5))
return fs.stripparts("/home/user/a/b/c.txt", 2)
]],
    },

    {
      title = "whole-file round trips",
      desc = table.concat({
        "writefile truncates by default and appends with the a flag, readfile slurps, mv renames, touch ",
        "creates an empty file, and exists returns two values: found, and the entry kind when found.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.writefile("greeting.txt", "hello")
fs.writefile("greeting.txt", " world", "a")
print("contents:", fs.readfile("greeting.txt"))
fs.mv("greeting.txt", "renamed.txt")
fs.touch("empty.txt")
local found, kind = fs.exists("renamed.txt")
print("exists:", found, kind)
print("empty:", fs.readfile("empty.txt") == "")
fs.rm("renamed.txt")
fs.rm("empty.txt")
return fs.exists("greeting.txt")
]],
    },

    {
      title = "probes: exists, isdir, isfile",
      desc = table.concat({
        "The predicates stat the path and answer with plain booleans, swallowing only ENOENT: a missing ",
        "path is false, not an error, while any other failure still raises. mode gives the raw entry ",
        "kind string that exists returns as its second value.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.mkdirp("probe/dir")
fs.writefile("probe/f.txt", "x")
print("isdir dir:", fs.isdir("probe/dir"))
print("isdir file:", fs.isdir("probe/f.txt"))
print("isfile file:", fs.isfile("probe/f.txt"))
print("isfile missing:", fs.isfile("probe/ghost"))
print("mode:", fs.mode("probe"))
local found, kind = fs.exists("probe/f.txt")
print("exists:", found, kind)
fs.rm("probe/f.txt")
fs.rmdirs("probe")
return kind
]],
    },

    {
      title = "structured errors",
      desc = table.concat({
        "Failures raise through santoku.error carrying the OS message and errno, so santoku.error's pcall ",
        "spreads them back as values you can match against the exported constants. rm raises on a missing ",
        "path unless allow_noexist is passed.",
      }),
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
local ok, msg, code = err.pcall(fs.mode, "ghost")
print("ok:", ok)
print("message:", msg)
print("is ENOENT:", code == fs.ENOENT)
local ok2 = err.pcall(fs.rm, "ghost")
print("rm missing raises:", not ok2)
fs.rm("ghost", true)
print("rm allow_noexist:", "no raise")
return code == fs.ENOENT
]],
    },

    {
      title = "with: scoped handles",
      desc = table.concat({
        "with opens a handle, runs your function with it, and always closes it, then re-raises anything ",
        "the function threw. Pass an already-open handle instead of a path and with leaves closing it ",
        "to you.",
      }),
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
fs.writefile("data.txt", "line 1\nline 2\n")
local first = fs.with("data.txt", "r", function (fh)
  return fs.read(fh, "*l")
end)
print("first line:", first)
local ok, msg = err.pcall(fs.with, "data.txt", "r", function ()
  return err.error("boom")
end)
print("re-raised:", not ok, msg)
fs.rm("data.txt")
return first
]],
    },

    {
      title = "handle primitives",
      desc = table.concat({
        "open, read, write, seek, flush, and close wrap the io methods with raising semantics. open ",
        "returns the handle plus a was_open flag: given an existing handle it passes it through with ",
        "true, which is how with and chunks accept either a path or a handle.",
      }),
      code = [[
local fs = require("santoku.fs")
local fh = fs.open("notes.txt", "w")
fs.write(fh, "alpha\nbeta\n")
fs.flush(fh)
fs.close(fh)
fh = fs.open("notes.txt", "r")
print("first:", fs.read(fh, "*l"))
print("seek:", fs.seek(fh, "set", 6))
print("second:", fs.read(fh, "*l"))
local same, was_open = fs.open(fh)
print("passthrough:", same == fh, was_open)
fs.close(fh)
fs.rm("notes.txt")
return was_open
]],
    },

    {
      title = "mkdirp and rmdirs",
      desc = table.concat({
        "mkdirp creates every missing component and is idempotent, while the raw mkdir raises EEXIST on ",
        "a second call. rmdirs removes a directory tree bottom-up, which works because dirs with leaves ",
        "true yields children before their parents.",
      }),
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
fs.mkdirp("deep/x/y")
print("created:", fs.isdir("deep/x/y"))
fs.mkdirp("deep/x/y")
print("mkdirp again:", "no raise")
local ok, _, code = err.pcall(fs.mkdir, "deep")
print("mkdir again:", ok, code == fs.EEXIST)
for d in fs.dirs("deep", true, true) do
  print("leaves-first:", d)
end
fs.rmdirs("deep")
return fs.exists("deep")
]],
    },

    {
      title = "files and dirs",
      desc = table.concat({
        "files iterates regular files, dirs iterates directories, each with a recurse flag; non-recursive ",
        "files stays in the top level, non-recursive dirs lists immediate subdirectories without ",
        "descending. Directory order comes from readdir, so collect and sort when order matters.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.mkdirp("proj/src/util")
fs.writefile("proj/readme.md", "# proj")
fs.writefile("proj/src/main.lua", "return true")
fs.writefile("proj/src/util/str.lua", "return true")
local all = {}
for fp in fs.files("proj", true) do
  all[#all + 1] = fp
end
table.sort(all)
print("recursive:", table.concat(all, " "))
local top = {}
for fp in fs.files("proj") do
  top[#top + 1] = fp
end
print("top only:", table.concat(top, " "))
local ds = {}
for d in fs.dirs("proj", true) do
  ds[#ds + 1] = d
end
table.sort(ds)
print("dirs:", table.concat(ds, " "))
for i = 1, #all do
  fs.rm(all[i])
end
fs.rmdirs("proj")
return #all
]],
    },

    {
      title = "walk with prune",
      desc = table.concat({
        "walk yields every entry as name, kind. The prune callback runs for each directory: true skips ",
        "the subtree entirely, the string keep yields the directory itself without descending (how ",
        "non-recursive dirs is built), and false descends normally.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.mkdirp("site/src")
fs.mkdirp("site/build")
fs.writefile("site/src/main.lua", "return true")
fs.writefile("site/build/cache.bin", "x")
fs.writefile("site/doc.md", "# doc")
local seen = {}
for name, kind in fs.walk("site", function (dir)
  if fs.basename(dir) == "build" then
    return true
  end
end) do
  seen[#seen + 1] = name .. " (" .. kind .. ")"
end
table.sort(seen)
print("pruned:", table.concat(seen, " "))
local kept = {}
for name, kind in fs.walk("site", function ()
  return "keep"
end) do
  kept[#kept + 1] = name .. " (" .. kind .. ")"
end
table.sort(kept)
print("keep:", table.concat(kept, " "))
fs.rm("site/src/main.lua")
fs.rm("site/build/cache.bin")
fs.rm("site/doc.md")
fs.rmdirs("site")
return #seen
]],
    },

    {
      title = "low-level directory stream",
      desc = table.concat({
        "dir wraps the raw diropen, dirent, and dirclose primitives into an iterator over entry name and ",
        "kind, including the dot entries, which callers filter themselves. The handle closes itself at ",
        "end of stream and carries a __gc closer for early exits.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.mkdirp("box")
fs.writefile("box/a.txt", "a")
fs.writefile("box/b.txt", "b")
local ents = {}
for name, kind in fs.dir("box") do
  if name ~= "." and name ~= ".." then
    ents[#ents + 1] = name .. " (" .. kind .. ")"
  end
end
table.sort(ents)
print(table.concat(ents, ", "))
fs.rm("box/a.txt")
fs.rm("box/b.txt")
fs.rmdirs("box")
return #ents
]],
    },

    {
      title = "chunks: fixed-size blocks",
      desc = table.concat({
        "With no delimiters, chunks streams a file in blocks of at most the given size, each yielded as ",
        "a fresh string, so a 28-byte file read 8 bytes at a time gives three full blocks and a 4-byte ",
        "tail. Buffer size defaults to BUFSIZ when omitted.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.writefile("blob.txt", "line 1\nline 2\nline 3\nline 4\n")
local blocks = {}
for chunk in fs.chunks("blob.txt", nil, 8) do
  blocks[#blocks + 1] = chunk
end
print("count:", #blocks)
print("first:", (blocks[1]:gsub("\n", "\\n")))
print("last:", (blocks[#blocks]:gsub("\n", "\\n")))
fs.rm("blob.txt")
return #blocks
]],
    },

    {
      title = "chunks: delimited records",
      desc = table.concat({
        "With delimiter bytes, chunks yields the buffer plus start and end positions of each segment, ",
        "slicing without copying; omit true excludes the delimiter run from the end position. Records ",
        "spanning a buffer boundary are re-read, and a record larger than the buffer raises chunk ",
        "doesn't fit with the byte offsets.",
      }),
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
fs.writefile("log.txt", "alpha\nbeta\ngamma\n")
local lines = {}
for chunk, s, e in fs.chunks("log.txt", "\n", 8, true) do
  lines[#lines + 1] = chunk:sub(s, e)
end
print("lines:", table.concat(lines, ", "))
local ok, msg = err.pcall(function ()
  for chunk in fs.chunks("log.txt", "\n", 3) do
    local _ = chunk
  end
end)
print("too small:", not ok, msg)
fs.rm("log.txt")
return #lines
]],
    },

    {
      title = "pushd",
      desc = table.concat({
        "pushd changes into a directory, calls your function with any extra arguments, and restores the ",
        "previous cwd on every exit path: on error it still restores first, then re-raises. This is how ",
        "the make engine runs each dependency build inside its own checkout.",
      }),
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
fs.mkdirp("scratch")
local before = fs.cwd()
local inside = fs.pushd("scratch", function (tag)
  fs.writefile("note.txt", tag)
  return fs.cwd()
end, "written inside")
print("changed:", inside ~= before)
print("restored:", fs.cwd() == before)
print("note:", fs.readfile("scratch/note.txt"))
local ok, msg = err.pcall(fs.pushd, "scratch", function ()
  return err.error("inner failure")
end)
print("re-raised:", not ok, msg)
print("still restored:", fs.cwd() == before)
fs.rm("scratch/note.txt")
fs.rmdirs("scratch")
return fs.basename(inside)
]],
    },

    {
      title = "loadfile and runfile",
      desc = table.concat({
        "loadfile compiles a Lua file to a function under an optional environment; runfile loads and ",
        "calls it. runfile's environment falls through to _G by default so scripts can still reach ",
        "globals, and the nog flag cuts that link for full isolation.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.writefile("script.lua", "return x + y")
print("loadfile:", fs.loadfile("script.lua", { x = 1, y = 2 })())
local result = fs.runfile("script.lua", { x = 10, y = 20 })
print("runfile:", result)
fs.writefile("script.lua", "return print ~= nil")
print("sees _G:", fs.runfile("script.lua"))
print("isolated:", fs.runfile("script.lua", {}, true))
fs.rm("script.lua")
return result
]],
    },

    {
      title = "absolute paths",
      desc = table.concat({
        "absolute resolves a path against the real filesystem with realpath, walking back to the ",
        "deepest existing prefix so a not-yet-created leaf still gets an absolute answer. The empty ",
        "string gives nil.",
      }),
      code = [[
local fs = require("santoku.fs")
fs.mkdirp("abs/demo")
local a = fs.absolute("abs/demo")
print("anchored:", a == fs.join(fs.cwd(), "abs/demo"))
local leaf = fs.absolute("abs/demo/new.txt")
print("missing leaf:", leaf == fs.join(fs.cwd(), "abs/demo/new.txt"))
print("empty:", fs.absolute("") == nil)
fs.rmdirs("abs")
return a ~= nil
]],
    },

    {
      title = "the copy idiom",
      desc = table.concat({
        "The pattern the make engine uses everywhere: mkdirp the ",
        "destination's dirname, then writefile a readfile, and drive it from a files iteration to ",
        "mirror a whole tree.",
      }),
      code = [[
local fs = require("santoku.fs")
local function copy (src, dest)
  fs.mkdirp(fs.dirname(dest))
  fs.writefile(dest, fs.readfile(src))
end
fs.mkdirp("src/icons")
fs.writefile("src/app.lua", "return 1")
fs.writefile("src/icons/logo.svg", "<svg/>")
for fp in fs.files("src", true) do
  copy(fp, fs.join("dist", fp))
end
local out = {}
for fp in fs.files("dist", true) do
  out[#out + 1] = fp
end
table.sort(out)
print("mirrored:", table.concat(out, " "))
local body = fs.readfile("dist/src/app.lua")
local function nuke (dir)
  for fp in fs.files(dir, true) do
    fs.rm(fp)
  end
  fs.rmdirs(dir)
end
nuke("src")
nuke("dist")
return body
]],
    },

    {
      title = "hardlink and symlink",
      desc = table.concat({
        "Compiled out under emscripten, so this page's wasm bundle has neither: feature-detect with a ",
        "nil check, exactly as the library's own tests do. A hardlink shares content with its source, ",
        "mode follows a symlink to the target's kind, and exists on a dangling symlink is false ",
        "because stat fails with ENOENT.",
      }),
      runnable = false,
      code = [[
local fs = require("santoku.fs")
if fs.hardlink then
  fs.writefile("shared.txt", "hello")
  fs.hardlink("shared.txt", "alias.txt")
  print("alias:", fs.readfile("alias.txt"))
  fs.writefile("shared.txt", "changed")
  print("alias sees:", fs.readfile("alias.txt"))
end
if fs.symlink then
  fs.symlink("shared.txt", "pointer.txt")
  print("mode:", fs.mode("pointer.txt"))
  fs.symlink("missing.txt", "dangling.txt")
  print("dangling exists:", fs.exists("dangling.txt"))
end
]],
    },

    {
      title = "host tooling idioms",
      desc = table.concat({
        "Patterns from the CLI tools and build scripts that only make sense on a real machine: pcall a ",
        "readfile to treat a missing config as defaults, absolute to canonicalize a user path before ",
        "recording it, exists as a cheap guard, and tmpname for compiler scratch files.",
      }),
      runnable = false,
      code = [[
local fs = require("santoku.fs")
local err = require("santoku.error")
local ok, raw = err.pcall(fs.readfile, "ll.conf.lua")
if not ok then
  raw = "return {}"
end
local canonical = fs.absolute("notes/sync.md")
if fs.exists("notes/sync.md") then
  print("syncing:", canonical)
end
local tmp = fs.tmpname() .. ".c"
fs.writefile(tmp, "int main () { return 0; }")
print("scratch:", tmp)
fs.rm(tmp)
return canonical
]],
    },

  },

}

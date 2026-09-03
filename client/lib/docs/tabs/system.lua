return {

  intro = table.concat({
    "santoku-system is the process layer of the framework: fork a program or a plain ",
    "Lua function across one or more jobs and stream its output back as an iterator, ",
    "built directly on fork, pipe, poll, and execvp. Requiring santoku.system returns ",
    "one table merging execute, pread, and sh with the POSIX bindings ",
    "(santoku.system.posix) and everything from Lua's os library, so sys.fork and ",
    "sys.getenv live beside sys.sh. Failures raise structured errors through ",
    "santoku.error carrying the OS message and errno. This is the engine under toku ",
    "build hooks, deploy tooling, and the ll secrets CLI; everything here needs a ",
    "real operating system underneath, so the examples are shown for reading rather ",
    "than wired to the in-page interpreter.",
  }),

  examples = {

    {
      title = "One merged table",
      desc = "The module is three layers in one namespace: the high-level trio (execute, sh, pread), the raw POSIX bindings, and stock os. Earlier layers win on name clashes, so nothing from os is shadowed unexpectedly.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
print(type(sys.execute), type(sys.sh), type(sys.pread))
print(type(sys.fork), type(sys.pipe), type(sys.execp))
print(type(sys.getenv), type(sys.time), type(sys.exit))
print("cores:", sys.get_num_cores())
]],
    },

    {
      title = "sys.execute",
      desc = "Run a program to completion. The child inherits the terminal, so its output flows straight through untouched; the call raises if the child exits non-zero, and returns normally otherwise.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
sys.execute({ "git", "status", "--short" })
sys.execute({ "tar", "-C", "dist", "-czf", "release.tar.gz", "." })
]],
    },

    {
      title = "Build configure hooks",
      desc = "The workhorse pattern in toku make files: shell out to asset tooling from a target's build function: CSS build, icon rasterization, dev-only self-signed TLS.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
sys.execute({
  "tailwindcss",
  "-i", "res/index.css",
  "-o", "public/index.css",
  "--minify",
})
sys.execute({
  "rsvg-convert", "-w", "192", "-h", "192",
  "-o", "public/icon-192.png", "res/icons/icon.svg",
})
sys.execute({
  "openssl", "req", "-x509", "-nodes", "-days", "365",
  "-newkey", "rsa:2048",
  "-keyout", "ssl/localhost.key",
  "-out", "ssl/localhost.crt",
  "-subj", "/CN=localhost/O=DEV ONLY",
})
]],
    },

    {
      title = "sys.sh: line iterator",
      desc = "Fork a child and iterate its stdout line by line, trailing newlines stripped. When the child exits, the iterator ends; a non-zero exit raises through santoku.error instead.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
for line in sys.sh({ "sh", "-c", "echo a; echo b" }) do
  print(line)
end
]],
    },

    {
      title = "One-shot capture",
      desc = "The iterator is just a function, so calling it once grabs the first line and discards the rest. Deploy tooling uses this to probe the toolchain: architecture, compiler resource dirs, which symbolizer is on PATH.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local arch = sys.sh({ "uname", "-m" })()
print("arch:", arch)
local symbolizer = sys.sh({
  "sh", "-c", "command -v llvm-symbolizer 2>/dev/null || true"
})()
print("symbolizer:", symbolizer)
]],
    },

    {
      title = "Collect and join",
      desc = "Accumulate every line into a buffer to capture a program's whole output as a string: here the make engine's JS minifier, feeding a temp file through esbuild.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local fs = require("santoku.fs")
local tmp = fs.tmpname() .. ".js"
fs.writefile(tmp, "function add (a, b) { return a + b; }")
local parts = {}
for chunk in sys.sh({ "esbuild", "--minify", tmp }) do
  parts[#parts + 1] = chunk
end
os.remove(tmp)
print(table.concat(parts, "\n"))
]],
    },

    {
      title = "sys.pread: raw events",
      desc = "Beneath sh sits pread: an iterator of (event, pid, ...) tuples. stdout and stderr events carry raw chunks (no line buffering), and every child ends with an exit event carrying a reason and status.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local it = sys.pread({
  "sh", "-c", "echo out; echo err >&2; exit 1",
  stderr = true,
})
for ev, pid, a, b in it do
  if ev == "exit" then
    print(ev, a, b)
  else
    print(ev, a)
  end
end
]],
    },

    {
      title = "Tuning the streams",
      desc = "stdout is watched by default, stderr only when stderr = true, and bufsize caps each read (default BUFSIZ). With stdout = false nothing is watched and the iterator yields only the exit event.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
for ev, pid, reason, status in sys.pread({
  "sh", "-c", "exit 7",
  stdout = false,
}) do
  print(ev, reason, status)
end
for ev, pid, chunk in sys.pread({
  "sh", "-c", "echo hello",
  bufsize = 500,
}) do
  print(ev, chunk)
end
]],
    },

    {
      title = "pread tolerates failure, sh does not",
      desc = "pread reports a non-zero exit as data rather than raising, so a CLI can sweep a child's stderr into a diagnostic and decide for itself. This is the ll secrets client collecting a helper's failure message.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local reason, rc, diag = nil, nil, {}
for what, _, r, c in sys.pread({
  "sh", "-c", "echo broadcast refused >&2; exit 3",
  stdout = true, stderr = true,
}) do
  if what == "exit" then
    reason, rc = r, c
  elseif what == "stderr" then
    diag[#diag + 1] = r
  end
end
if reason ~= "exited" or rc ~= 0 then
  print("failed: " .. table.concat(diag):gsub("%s+$", ""))
end
]],
    },

    {
      title = "Probing with execute",
      desc = "Since execute raises on non-zero exit, wrapping it in pcall turns any exit-status idiom into a boolean. Deploy tooling checks server liveness this way with kill -0.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local err = require("santoku.error")
local pid = "12345"
local alive = err.pcall(sys.execute, { "kill", "-0", pid })
print("alive:", alive)
]],
    },

    {
      title = "Environment control",
      desc = "The env option setenvs each pair in the child before exec, leaving the parent untouched. The make engine drives luarocks this way, pinning LUAROCKS_CONFIG and MAKEFLAGS per invocation.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
for line in sys.sh({
  "sh", "-c", "echo $GREETING",
  env = { GREETING = "hello" },
}) do
  print(line)
end
sys.execute({
  "luarocks", "make", "lib.rockspec",
  env = {
    LUAROCKS_CONFIG = "/abs/path/luarocks.lua",
    MAKEFLAGS = "--no-print-directory",
  },
})
]],
    },

    {
      title = "Parallel jobs",
      desc = "jobs = N forks N copies of the same argv and one iterator interleaves all their output; job_var exposes each worker's index (1 to N) as an env var. Exit events surface per child under pread.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
for line in sys.sh({
  "sh", "-c", "echo worker $JOB",
  jobs = 4, job_var = "JOB",
}) do
  print(line)
end
]],
    },

    {
      title = "Parallel Lua functions",
      desc = "Instead of an argv, fn forks a plain Lua closure per job: each child runs fn(job, opts) in its own process and its prints stream back through the same iterator. A raised error in the child becomes a non-zero exit.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
for line in sys.sh({
  jobs = 4,
  fn = function (job)
    print("worker " .. job .. " pid " .. sys.pid())
  end,
}) do
  print(line)
end
]],
    },

    {
      title = "sys.atom: shared counter",
      desc = "atom(initial) allocates a semaphore-guarded counter in shared memory before forking; each call returns the old value and increments, so workers can pull from one queue without duplicating work. Guard for availability: it is compiled out on Android.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
if not sys.atom then
  return "atom unavailable on this platform"
end
local vals = { "a", "b", "c", "d", "e", "f" }
local next_i = sys.atom(1)
for line in sys.sh({
  jobs = 3,
  fn = function (job)
    while true do
      local i = next_i()
      if i > #vals then break end
      print(job, i, vals[i])
      io.stdout:flush()
    end
  end,
}) do
  print("result", line)
end
]],
    },

    {
      title = "Throttled atoms",
      desc = "atom(initial, throttle) also records the time of the last take and sleeps inside the semaphore until at least throttle seconds have passed, making it a cross-process rate limiter: N workers hammering one API share a single global pace. The call accepts an optional increment (default 1).",
      runnable = false,
      code = [[
local sys = require("santoku.system")
if not sys.atom then
  return "atom unavailable on this platform"
end
local next_page = sys.atom(1, 0.5)
for line in sys.sh({
  jobs = 4,
  fn = function (job)
    for _ = 1, 3 do
      local page = next_page()
      print(job, "fetching page", page)
      io.stdout:flush()
    end
  end,
}) do
  print(line)
end
]],
    },

    {
      title = "sys.mutex: cross-process critical section",
      desc = "mutex() returns a lock function: lock(fn, ...) runs fn under a shared semaphore, releases it even if fn raises (the error re-raises after release), and passes fn's return values through. Like atom, it is unavailable on Android.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
if not sys.mutex then
  return "mutex unavailable on this platform"
end
local lock = sys.mutex()
local a, b = lock(function ()
  return 1, 2
end)
print(a, b)
for line in sys.sh({
  jobs = 4,
  fn = function (job)
    lock(function ()
      print("job " .. job .. " has the lock")
      io.stdout:flush()
    end)
  end,
}) do
  print(line)
end
]],
    },

    {
      title = "sys.execp: becoming another program",
      desc = "execp(prog, argv) replaces the current process via execvp (PATH search, argv from the table) and never returns on success, so reaching the next line means it failed with errno. The ll CLI ends this way: inject secrets with setenv, then exec the user's command.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local payload_env = { API_KEY = "s3cret", REGION = "us-east-1" }
for k, v in pairs(payload_env) do
  sys.setenv(k, v)
end
local ok, e = pcall(sys.execp, "terraform", { "plan" })
io.stderr:write("terraform: " .. tostring(e) .. "\n")
os.exit(127)
]],
    },

    {
      title = "fork plus execp: a supervised child",
      desc = "fork() returns the child pid in the parent and 0 in the child (on Linux the child also gets SIGHUP if the parent dies). The ll CLI forks, points the child at a private SSH_AUTH_SOCK, execs the user's command, and serves the agent socket from the parent until the child exits.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
local path = "/tmp/ll-agent.sock"
local pid = sys.fork()
if pid == 0 then
  sys.setenv("SSH_AUTH_SOCK", path)
  local _, e = pcall(sys.execp, "ssh", { "deploy@host", "uptime" })
  io.stderr:write("ssh: " .. tostring(e) .. "\n")
  os.exit(127)
end
local _, reason, status = sys.wait(pid)
print(reason, status)
]],
    },

    {
      title = "pipe, dup2, read: the raw plumbing",
      desc = "The same primitives sh is built from are exported directly: pipe() returns read and write fds (close-on-exec), dup2 rewires a child's stdout, read pulls raw bytes, wait reaps.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
io.flush()
local r, w = sys.pipe()
local pid = sys.fork()
if pid == 0 then
  sys.close(r)
  sys.dup2(w, 1)
  sys.close(w)
  io.write("hello from the child")
  io.flush()
  os.exit(0)
end
sys.close(w)
print(sys.read(r, sys.BUFSIZ))
sys.close(r)
sys.wait(pid)
]],
    },

    {
      title = "Identity, cores, sleep, wait reasons",
      desc = "Process identity and sizing: pid(), ppid() for the current parent (ppid(pid) walks /proc, Linux only), get_num_cores() for sizing jobs, fractional sleep(seconds), and BUFSIZ. wait(pid) returns the pid plus a reason: exited or signaled or stopped with a status, continued without one.",
      runnable = false,
      code = [[
local sys = require("santoku.system")
print("pid:", sys.pid(), "ppid:", sys.ppid())
print("cores:", sys.get_num_cores())
print("bufsiz:", sys.BUFSIZ)
sys.sleep(0.25)
local pid = sys.fork()
if pid == 0 then
  os.exit(3)
end
local wpid, reason, status = sys.wait(pid)
print(wpid, reason, status)
for line in sys.sh({
  "sh", "-c", "echo up",
  jobs = sys.get_num_cores(),
}) do
  print(line)
end
]],
    },

  },

}

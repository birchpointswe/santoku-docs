local fs = require("santoku.fs")
local sys = require("santoku.system")

local hl_script = [[
const fs = require("fs");
const path = require("path");
const vendor = process.argv[2];
const dir = process.argv[3];
global.Prism = require(path.join(vendor, "prism-core.min.js"));
for (const c of process.argv.slice(4)) {
  if (c !== "core") {
    require(path.join(vendor, "prism-" + c + ".min.js"));
  }
}
for (const f of fs.readdirSync(dir).sort()) {
  if (!f.endsWith(".in")) continue;
  const raw = fs.readFileSync(path.join(dir, f), "utf8");
  const nl = raw.indexOf("\n");
  const lang = raw.slice(0, nl);
  const code = raw.slice(nl + 1);
  const grammar = Prism.languages[lang] || Prism.languages.text;
  const out = Prism.highlight(code, grammar, lang);
  fs.writeFileSync(path.join(dir, f.replace(/\.in$/, ".out")), out);
}
]]

return function (opts)
  local content = opts.content
  local dir = fs.join(opts.work_dir, "render-hl")
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  local script = fs.join(opts.work_dir, "render-hl.js")
  fs.writefile(script, hl_script)
  local keys = {}
  local n = 0
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      for j = 1, #tab.content.examples do
        local ex = tab.content.examples[j]
        n = n + 1
        local key = string.format("%04d", n)
        keys[tab.id .. "/" .. j] = key
        fs.writefile(fs.join(dir, key .. ".in"),
          (ex.lang or "lua") .. "\n" .. ex.code)
      end
    end
  end
  local cmd = { "node", script, opts.vendor_dir, dir }
  for i = 1, #opts.prism do
    cmd[#cmd + 1] = opts.prism[i]
  end
  sys.execute(cmd)
  local out = { "return {\n" }
  local sorted = {}
  for k in pairs(keys) do
    sorted[#sorted + 1] = k
  end
  table.sort(sorted)
  for i = 1, #sorted do
    local k = sorted[i]
    out[#out + 1] = string.format("  [%q] = %q,\n",
      k, fs.readfile(fs.join(dir, keys[k] .. ".out")))
  end
  out[#out + 1] = "}\n"
  sys.execute({ "rm", "-rf", dir })
  fs.rm(script)
  fs.mkdirp(fs.dirname(opts.out_path))
  fs.writefile(opts.out_path, table.concat(out))
end

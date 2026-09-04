local fs = require("santoku.fs")

return function (opts)
  local readfile = opts.readfile
  local root_dir = opts.root_dir
  local gen_dir = opts.gen_dir
  local preload = opts.preload or {}
  local loaded = {}
  local env
  local function resolve (rel)
    local roots = {}
    if gen_dir then
      roots[#roots + 1] = fs.join(gen_dir, "docs", rel)
    end
    roots[#roots + 1] = fs.join(root_dir, "res/docs", rel)
    for i = 1, #roots do
      if fs.exists(roots[i]) then
        return roots[i]
      end
    end
    error("docs loader: no source for " .. rel)
  end
  local function req (mod)
    if loaded[mod] ~= nil then
      return loaded[mod]
    end
    if preload[mod] ~= nil then
      loaded[mod] = preload[mod]
      return loaded[mod]
    end
    if not string.match(mod, "^docs%.") then
      return require(mod)
    end
    local rel = string.gsub(string.gsub(mod, "^docs%.", ""), "%.", "/") .. ".lua"
    local fp = resolve(rel)
    local chunk = assert(loadstring(readfile(fp), "@" .. fp))
    setfenv(chunk, env)
    loaded[mod] = chunk()
    return loaded[mod]
  end
  env = setmetatable({ require = req }, { __index = _G })
  return req
end

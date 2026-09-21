local specs = {
  { key = "lib", name = "my-lib" },
  { key = "web", name = "my-app" },
  { key = "api", name = "my-api" },
}

local function build (snapshot, dir_for)
  local out = {}
  for _, spec in ipairs(specs) do
    local snap = snapshot(spec.key, {
      name = spec.name,
      dir = dir_for(spec.key),
    })
    out[spec.key] = { name = spec.name, all = snap.all }
  end
  return out
end

return {
  build = build,
}

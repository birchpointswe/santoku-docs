local scaffold = require("docs.scaffold")

return function (kind, path)
  local group = scaffold[kind]
  if not group then
    error("unknown scaffold kind: " .. tostring(kind))
  end
  local want = string.gsub(path, "%%[sm]", {
    ["%s"] = group.name,
    ["%m"] = group.mod or group.name,
  })
  for i = 1, #group.files do
    if group.files[i].path == want then
      return group.files[i]
    end
  end
  error("scaffold file not found: " .. kind .. " " .. want)
end

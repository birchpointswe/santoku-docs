local function slug (s)
  local out = string.lower(s or "")
  out = string.gsub(out, "[^%w]+", "-")
  out = string.gsub(out, "^%-+", "")
  out = string.gsub(out, "%-+$", "")
  return out
end

local function example_ids (tab)
  local ids, seen = {}, {}
  for i = 1, #tab.content.examples do
    local base = tab.id .. "--" .. slug(tab.content.examples[i].title)
    local id, n = base, 1
    while seen[id] do
      n = n + 1
      id = base .. "-" .. n
    end
    seen[id] = true
    ids[i] = id
  end
  return ids
end

return {
  slug = slug,
  example_ids = example_ids,
}

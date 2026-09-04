local function pusher (out)
  return function (...)
    for i = 1, select("#", ...) do
      out[#out + 1] = (select(i, ...))
    end
  end
end

local function preamble (push, content)
  push("# ", content.title, "\n\n")
  push("> ", content.summary, "\n\n")
  push("## About\n\n")
  push(content.about, "\n\n")
  push("## Lua version\n\n")
  push(content.lua_position, "\n\n")
end

local function render (content, site)
  local out = {}
  local push = pusher(out)
  preamble(push, content)
  local order, groups = {}, {}
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    local name = tab.group or "Libraries"
    if not groups[name] then
      groups[name] = {}
      order[#order + 1] = name
    end
    local items = groups[name]
    items[#items + 1] = tab
  end
  for i = 1, #order do
    local name = order[i]
    push("## ", name, "\n\n")
    local items = groups[name]
    for j = 1, #items do
      local tab = items[j]
      push("- [", tab.label, "](", site, "/", tab.id, "): ", tab.desc)
      if tab.url then
        push(" (source: ", tab.url, ")")
      end
      push("\n")
    end
    push("\n")
  end
  return table.concat(out)
end

local function render_full (content, site)
  local out = {}
  local push = pusher(out)
  preamble(push, content)
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    if tab.content then
      push("\n## ", tab.label, "\n\n")
      push(site, "/", tab.id, "\n\n")
      push(tab.content.intro, "\n")
      for j = 1, #tab.content.examples do
        local ex = tab.content.examples[j]
        push("\n### ", ex.title, "\n\n")
        push(ex.desc, "\n\n")
        push("```", ex.lang or "lua", "\n", ex.code)
        if not string.match(ex.code, "\n$") then
          push("\n")
        end
        push("```\n")
      end
    end
  end
  return table.concat(out)
end

return {
  render = render,
  render_full = render_full,
}

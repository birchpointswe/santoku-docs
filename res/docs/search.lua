return function (content, ids)
  local out = { "return {\n" }
  local function entry (e)
    out[#out + 1] = string.format(
      "  { id = %q, tab_id = %q, url = %q, label = %q, sub = %q,\n" ..
      "    is_tab = %s, title_hay = %q, hay = %q },\n",
      e.id, e.tab_id, e.url, e.label, e.sub,
      e.is_tab and "true" or "nil", e.title_hay, e.hay)
  end
  for i = 1, #content.tabs do
    local tab = content.tabs[i]
    entry({
      id = tab.id,
      tab_id = tab.id,
      url = "/" .. tab.id,
      label = tab.label,
      sub = tab.group or "Libraries",
      is_tab = true,
      title_hay = string.lower(tab.label),
      hay = string.lower(tab.label .. " " .. (tab.desc or "")),
    })
    if tab.content then
      local ex_ids = ids.example_ids(tab)
      for ei = 1, #tab.content.examples do
        local ex = tab.content.examples[ei]
        entry({
          id = ex_ids[ei],
          tab_id = tab.id,
          url = "/" .. tab.id .. "#" .. ex_ids[ei],
          label = ex.title,
          sub = tab.label,
          title_hay = string.lower(ex.title),
          hay = string.lower(ex.title .. " " .. (ex.desc or "") .. " " .. (ex.code or "")),
        })
      end
    end
  end
  out[#out + 1] = "}\n"
  return table.concat(out)
end

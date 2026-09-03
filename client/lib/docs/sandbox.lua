-- luacheck: ignore 122

local function exit (code)
  error("os.exit(" .. tostring(code or 0) .. ") called", 2)
end

os.exit = exit

return exit

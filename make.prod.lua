local fs = require("santoku.fs")
local tbl = require("santoku.table")

return tbl.merge({
  env = {
    nginx = {
      port = "8080",
      ssl_port = "8443",
    },
  }
}, fs.runfile("make.common.lua"))

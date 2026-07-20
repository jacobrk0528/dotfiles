require("config.lazy")
require("config.init")

vim.filetype.add({
  extension = {
    sqlx = "sql",
  },
  pattern = {
    [".*%.blade%.php"] = "blade",
  },
})
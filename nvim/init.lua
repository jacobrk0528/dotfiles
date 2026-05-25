require("config.lazy")
require("config.init")

vim.filetype.add({
  pattern = {
    [".*%.blade%.php"] = "blade",
  },
})
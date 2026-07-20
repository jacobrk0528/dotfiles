require("jkrebs.set")
require("jkrebs.remap")

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      require("config.colorscheme")
    end, 10)
  end,
})

-- Format SQL/SQLX on save (sqlx is mapped to the "sql" filetype in init.lua)
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.sql", "*.sqlx" },
  callback = function()
    vim.lsp.buf.format({ async = false, timeout_ms = 10000 })
  end,
  desc = "Format SQL/SQLX buffer on save",
})
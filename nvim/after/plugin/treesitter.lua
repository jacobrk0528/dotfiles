-- after/plugin/treesitter.lua (main-branch rewrite compatible)

local treesitter_languages = {
  "c", "lua", "vim", "vimdoc", "query",
  "markdown", "markdown_inline",
  "javascript", "typescript", "python",
  "html", "go", "php", "json", "css",
  "regex", "bash", "yaml", "toml", "blade",
}

vim.filetype.add({
  pattern = {
    [".*%.blade%.php"] = "blade",
  },
})

require("nvim-treesitter").setup({
  install_dir = vim.fn.stdpath("data") .. "/site",
})

vim.api.nvim_create_autocmd("User", {
  pattern = "TSUpdate",
  callback = function()
    require("nvim-treesitter.parsers").blade = {
      install_info = {
        url = "https://github.com/EmranMR/tree-sitter-blade",
        branch = "main",
        files = { "src/parser.c" },
      },
    }
  end,
})

require("nvim-treesitter").install(treesitter_languages)

local function too_big(buf)
  local max = 500 * 1024
  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
  return ok and stats and stats.size > max
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = treesitter_languages,
  callback = function(ev)
    if not too_big(ev.buf) then
      vim.treesitter.start(ev.buf)
    end

    if vim.bo[ev.buf].filetype == "blade" then
      vim.opt_local.commentstring = "{{-- %s --}}"
      pcall(function() vim.bo[ev.buf].syntax = "php" end)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = treesitter_languages,
  callback = function(ev)
    if vim.bo[ev.buf].filetype ~= "yaml" then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})


vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.scrolloff = 20
vim.opt.sidescrolloff = 8
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
vim.opt.breakindentopt = "shift:2,sbr"
vim.opt.showbreak = "↳ "
vim.opt.cmdheight = 1
vim.opt.spelllang = { "en" }

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = false
vim.opt.smarttab = true
vim.opt.autoindent = true
vim.opt.smartindent = true

vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.grepprg = "rg --vimgrep"
vim.opt.grepformat = "%f:%l:%c:%m"

vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.showmatch = true
vim.opt.colorcolumn = "100"
vim.opt.matchtime = 1
vim.opt.completeopt = "menuone,noinsert,noselect"
vim.opt.showmode = true
vim.opt.pumheight = 10
vim.opt.pumblend = 10
vim.opt.conceallevel = 0
vim.opt.concealcursor = ""

vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.updatetime = 50
vim.opt.timeoutlen = 1000
vim.opt.ttimeoutlen = 0
vim.opt.autoread = true
vim.opt.autowrite = false
vim.opt.diffopt:append("vertical")
vim.opt.diffopt:append("algorithm:patience")
vim.opt.diffopt:append("linematch:60")

local undopath = os.getenv("HOME") .. "/.vim/undodir"
vim.fn.mkdir(undopath, "p")
vim.opt.undodir = undopath

vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  callback = function()
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
    vim.bo.expandtab = true
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "csv", "tsv" },
  callback = function()
    vim.wo.wrap = false
  end,
})

-- =============================================
-- Neovim Keymaps Configuration
-- =============================================

-- Leader key
vim.g.mapleader = " " -- Use space as leader

-- =============================================
-- General Mappings
-- =============================================

-- Open file explorer (netrw/Ex)
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex, { desc = "Open file explorer (Ex)" })

-- Move selected lines up/down in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep cursor centered when paging or searching
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Page down and center cursor" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Page up and center cursor" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result and center" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result and center" })

-- Paste over selection without yanking replaced text
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste without overwriting register" })

-- Yank/Delete to/from system clipboard or black hole register
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete into black hole register" })

-- Disable Ex mode
vim.keymap.set("n", "Q", "<nop>", { desc = "Disable Ex mode mapping" })

-- Manual format buffer via LSP
-- vim.keymap.set("n", "<leader>f", vim.lsp.buf.format, { desc = "Format buffer (LSP)" })
vim.keymap.set("n", "<leader>f", function()
	if vim.bo.filetype == "blade" then
		vim.lsp.buf.format({
			async = false,
			filter = function(client)
				return client.name == "null-ls"
			end,
		})
	else
		vim.lsp.buf.format({ async = false }) -- whatever other LSPs you have
	end
end, { desc = "Format buffer (LSP/null-ls for Blade)" })

-- Quickfix and Location-list navigation, keep center
vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz", { desc = "Quickfix next and center" })
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz", { desc = "Quickfix previous and center" })
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz", { desc = "Location-list next and center" })
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz", { desc = "Location-list previous and center" })

-- Make current file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make file executable" })

-- Open Neovim config directory
vim.keymap.set("n", "<leader>vpp", "<cmd>e ~/.config/nvim<CR>", { desc = "Edit Neovim config" })

-- Source (reload) current file
vim.keymap.set("n", "<leader><leader>", function()
	vim.cmd("so")
end, { desc = "Source current file" })

-- Comment toggling via plugin (assuming comment.nvim or similar)
vim.keymap.set("n", "<leader>/", "gcc", { remap = true, desc = "Toggle comment line" })
vim.keymap.set("v", "<leader>/", "gc", { remap = true, desc = "Toggle comment selection" })

-- Put contents of black hole register below cursor
vim.keymap.set(
	"n",
	"<leader>o",
	"<cmd>put _<CR>",
	{ noremap = true, silent = true, desc = "Put black hole register below" }
)

-- User commands: alias W for write, Q for quit
vim.api.nvim_create_user_command("W", "w", { desc = "Write file (alias)" })
vim.api.nvim_create_user_command("Q", "q", { desc = "Quit Neovim (alias)" })

-- Reindent entire file or yank entire file to system clipboard
vim.keymap.set("n", "<leader>g=", "ma gg=G `a", { noremap = true, silent = true, desc = "Reindent entire file" })
vim.keymap.set(
	"n",
	"<leader>gy",
	'ma ggVG"+y`a',
	{ noremap = true, silent = true, desc = "Yank entire file to system clipboard" }
)
vim.keymap.set("n", "<leader>Gd", "ggVGd", { desc = "Delete entire file contents" })
vim.keymap.set("n", "<leader>G<leader>d", 'ggVG"_d', { desc = "Delete entire file into black hole register" })

-- In visual mode, indent and keep selection
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and reselect" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and reselect" })

-- Quit all windows
vim.keymap.set("n", "<leader>q", "<cmd>qa<CR>", { desc = "Quit all windows" })

vim.keymap.set("n", "<leader>L", "<cmd>Lazy<CR>", { desc = "Open Lazy vim window" })

-- Move between windows with Ctrl + H/J/K/L
vim.keymap.set("n", "<C-H>", "<C-w>h", { noremap = true })
vim.keymap.set("n", "<C-J>", "<C-w>j", { noremap = true })
vim.keymap.set("n", "<C-K>", "<C-w>k", { noremap = true })
vim.keymap.set("n", "<C-L>", "<C-w>l", { noremap = true })

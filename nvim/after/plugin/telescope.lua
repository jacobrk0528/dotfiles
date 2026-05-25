local builtin = require("telescope.builtin")

vim.keymap.set("n", "<leader>ff", function()
	builtin.find_files({ hidden = true, no_ignore = true })
end, { desc = "Telescope: Find files (including hidden)" })

vim.keymap.set("n", "<leader>gf", builtin.git_files, { desc = "Telescope: Git files" })
vim.keymap.set("n", "<leader>fs", builtin.live_grep, { desc = "Telescope: Live grep" })
vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Telescope: List buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope: Help tags" })

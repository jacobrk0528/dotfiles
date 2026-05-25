local mark = require("harpoon.mark")
local ui = require("harpoon.ui")

vim.keymap.set("n", "<leader>a", function()
  mark.add_file()
  vim.notify("Added to harpoon")
end, { desc = "Harpoon: Add file" })

vim.keymap.set("n", "<leader>e", function()
  ui.toggle_quick_menu()
end, { desc = "Harpoon: Toggle quick menu" })

vim.keymap.set("n", "<leader>h", function() ui.nav_file(1) end, { desc = "Harpoon: Go to file 1" })
vim.keymap.set("n", "<leader>j", function() ui.nav_file(2) end, { desc = "Harpoon: Go to file 2" })
vim.keymap.set("n", "<leader>k", function() ui.nav_file(3) end, { desc = "Harpoon: Go to file 3" })
vim.keymap.set("n", "<leader>l", function() ui.nav_file(4) end, { desc = "Harpoon: Go to file 4" })

for i = 1, 9 do
  vim.keymap.set("n", "<leader>" .. i, function()
    ui.nav_file(i)
  end, { desc = "Harpoon: Go to file " .. i })
end
require("jkrebs.remap")
require("jkrebs.set")

vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		vim.defer_fn(function()
			require("config.colorscheme")
		end, 10)
	end
})

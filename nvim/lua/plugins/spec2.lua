return {
	{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			local treesitter_languages = {
				"c", "lua", "vim", "vimdoc", "query",
				"markdown", "markdown_inline",
				"javascript", "typescript", "python",
				"html", "go", "php", "php_only", "json", "css",
				"regex", "bash", "yaml", "toml", "blade",
			}

			local function too_big(buf)
				local max = 500 * 1024
				local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
				return ok and stats and stats.size > max
			end

			local ts = require("nvim-treesitter")
			ts.setup({
				install_dir = vim.fn.stdpath("data") .. "/site",
			})

			-- Enable highlighting for each language
			vim.api.nvim_create_autocmd("FileType", {
				pattern = treesitter_languages,
				callback = function(args)
					if not too_big(args.buf) then
						pcall(vim.treesitter.start, args.buf)
					end
				end,
			})

			-- Manually trigger install for missing parsers
			-- Note: This is async and requires tree-sitter-cli
			pcall(ts.install, treesitter_languages)

			vim.api.nvim_create_autocmd("FileType", {
				pattern = "blade",
				callback = function(ev)
					vim.opt_local.commentstring = "{{-- %s --}}"
					pcall(function()
						vim.bo[ev.buf].syntax = "php"
					end)
				end,
			})
		end,
	},
	{ "ThePrimeagen/harpoon" },
	{ "mbbill/undotree" },
	{ "numToStr/Comment.nvim" },
	{ "windwp/nvim-ts-autotag", config = function() require("nvim-ts-autotag").setup() end },
	{
		"nvimtools/none-ls.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"jay-babu/mason-null-ls.nvim",
		},
	},
}

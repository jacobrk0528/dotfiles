return {
	{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
	{ "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
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

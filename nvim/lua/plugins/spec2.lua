return {
	{ "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
	{ "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
	{ "ThePrimeagen/harpoon" },
	{ "mbbill/undotree" },
	{ "numToStr/Comment.nvim" },
	{
		"nvimtools/none-ls.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
	},
}

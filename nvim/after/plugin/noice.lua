require("noice").setup({
	lsp = {
		override = {
			["vim.lsp.diagnostic.set_signs"] = false,
			["vim.lsp.diagnostic.on_publish_diagnostics"] = false,
			["vim.lsp.convert_input_to_markdown_lines"] = false,
			["vim.lsp.util.stylize_markdown"] = false,
		},
	},
	presets = {
		bottom_search = true,
		command_palette = true,
		long_message_to_split = true,
		inc_rename = true,
		lsp_doc_border = true,
	},
})

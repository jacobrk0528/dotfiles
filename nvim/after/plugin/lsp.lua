-- lua/config/lsp.lua
-- Comprehensive LSP configuration with Blade embedded PHP & JS support

-- Initialize capabilities for nvim-cmp
local capabilities = require("cmp_nvim_lsp").default_capabilities()

local function setup_lsp_keymaps(bufnr)
	local opts = { buffer = bufnr, noremap = true, silent = true }
	vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
	vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Show hover information" }))
	vim.keymap.set(
		"n",
		"<leader>vws",
		vim.lsp.buf.workspace_symbol,
		vim.tbl_extend("force", opts, { desc = "Search workspace symbols" })
	)
	vim.keymap.set(
		"n",
		"<leader>vd",
		vim.diagnostic.open_float,
		vim.tbl_extend("force", opts, { desc = "Open diagnostic float" })
	)

	vim.keymap.set(
		"n",
		"<leader>ca",
		vim.lsp.buf.code_action,
		vim.tbl_extend("force", opts, { desc = "Show code actions" })
	)
	vim.keymap.set(
		"n",
		"<leader>rf",
		vim.lsp.buf.references,
		vim.tbl_extend("force", opts, { desc = "List references" })
	)
	vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename symbol" }))

	vim.keymap.set(
		"i",
		"<C-h>",
		vim.lsp.buf.signature_help,
		vim.tbl_extend("force", opts, { desc = "Show signature help" })
	)
	vim.keymap.set(
		"n",
		"<leader>sh",
		vim.lsp.buf.signature_help,
		vim.tbl_extend("force", opts, { desc = "Show signature help" })
	)
end

-- =============================================
-- LSP SIGNATURE CONFIG
-- =============================================
local function setup_signature(bufnr)
	require("lsp_signature").on_attach({
		bind = true,
		floating_window = true,
		hint_enable = true,
		handler_opts = { border = "rounded" },
	}, bufnr)
end

-- =============================================
-- ON LSP ATTACH HANDLER
-- =============================================
-- create the augroup once, not per client
local lsp_format_augroup = vim.api.nvim_create_augroup("user_lsp_format_on_save", { clear = true })

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("user_lsp_attach_once", { clear = true }),
	callback = function(event)
		local bufnr = event.buf

		setup_lsp_keymaps(bufnr)
		setup_signature(bufnr)

		vim.api.nvim_clear_autocmds({ group = lsp_format_augroup, buffer = bufnr })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = lsp_format_augroup,
			buffer = bufnr,
			desc = "Auto format on save",
			callback = function()
				local ft = vim.bo[bufnr].filetype
				local filter = nil
				if ft == "blade" then
					filter = function(client)
						return client.name == "null-ls"
					end
				else
					filter = function(client)
						return client.supports_method and client:supports_method("textDocument/formatting")
					end
				end

				vim.lsp.buf.format({
					bufnr = bufnr,
					async = false,
					timeout_ms = 5000,
					filter = filter,
				})
			end,
		})
	end,
})

-- =============================================
-- LSP SERVER CONFIGS
-- =============================================
local server_configs = {
	-- Vue + TS
	volar = {
		filetypes = { "vue", "javascript", "typescript", "javascriptreact", "typescriptreact" },
	},

	-- HTML LSP with Blade support
	html = {
		filetypes = { "html", "blade", "php" },
		init_options = {
			configurationSection = { "html", "css", "javascript", "php" },
			embeddedLanguages = {
				css = true,
				javascript = true,
				php = true,
			},
			provideFormatter = true,
		},
		settings = {
			html = {
				validate = true,
				hover = {
					documentation = true,
					references = true,
				},
			},
		},
	},

	-- PHP LSP (Intelephense) with Blade support
	intelephense = {
		filetypes = { "php", "blade" },
		settings = {
			intelephense = {
				licenseKey = "00REIZG3OJICXJJ",
				files = {
					maxSize = 5000000000,
					associations = { "*.blade.php", "*.php" },
					exclude = {
						"**/.git/**",
						"**/.svn/**",
						"**/.hg/**",
						"**/CVS/**",
						"**/.DS_Store/**",
						"**/node_modules/**",
						"**/bower_components/**",
						"**/vendor/**/{Tests,tests}/**",
						"**/.history/**",
						"**/vendor/**/vendor/**",
					},
				},
				environment = {
					phpVersion = "8.3",
					includePaths = { "./vendor", "./app", "./resources/views" },
				},
				telemetry = { enable = false },
				diagnostics = {
					enable = true,
					undefinedTypes = true,
					undefinedFunctions = true,
					undefinedMethods = true,
					undefinedConstants = true,
					unusedVariables = true,
					missingReturn = true,
					missingDocblock = true,
				},
				stubs = {
					"bcmath",
					"bz2",
					"Core",
					"curl",
					"date",
					"dom",
					"fileinfo",
					"filter",
					"gd",
					"hash",
					"json",
					"libxml",
					"mbstring",
					"openssl",
					"pcre",
					"PDO",
					"phar",
					"readline",
					"Reflection",
					"session",
					"SimpleXML",
					"sodium",
					"standard",
					"tokenizer",
					"xml",
					"xmlwriter",
					"zip",
					"zlib",
					"laravel",
					"auth",
					"cache",
					"config",
					"event",
					"filesystem",
					"foundation",
					"http",
					"log",
					"mail",
					"queue",
					"routing",
					"session",
					"support",
					"validation",
					"view",
				},
				completion = {
					fullyQualifyGlobalConstantsAndFunctions = true,
					insertUseDeclaration = true,
				},
			},
		},
	},

	-- Emmet (HTML/CSS)
	emmet_ls = {
		filetypes = { "html", "blade", "css", "javascriptreact", "typescriptreact", "vue", "php" },
		init_options = {
			html = { options = { ["bem.enabled"] = true } },
		},
	},

	-- Tailwind CSS
	tailwindcss = {
		filetypes = { "html", "blade", "css", "javascriptreact", "typescriptreact", "vue", "svelte" },
		settings = {
			tailwindCSS = {
				includeLanguages = {
					blade = "html",
				},
				experimental = {
					classRegex = {
						{ "@class\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
						{ "@?class\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
					},
				},
			},
		},
	},

	-- Lua
	lua_ls = {
		settings = {
			Lua = {
				diagnostics = { globals = { "vim" } },
				workspace = { library = vim.api.nvim_get_runtime_file("", true), checkThirdParty = false },
				telemetry = { enable = false },
			},
		},
	},

	-- Python
	pyright = {
		settings = {
			python = {
				analysis = {
					typeCheckingMode = "basic",
					autoSearchPaths = true,
					useLibraryCodeForTypes = true,
					diagnosticMode = "openFilesOnly",
				},
			},
		},
	},

	-- JS/TS LSP with Blade support
	tsserver = {
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "blade" },
		init_options = {
			hostInfo = "neovim",
			preferences = {
				includeInlayParameterNameHints = "all",
				includeInlayParameterNameHintsWhenArgumentMatchesName = false,
				includeInlayFunctionParameterTypeHints = true,
				includeInlayVariableTypeHints = true,
			},
		},
		root_dir = function(fname)
			local util = require("lspconfig.util")
			return util.root_pattern("package.json", "tsconfig.json", ".git")(fname)
				or util.find_git_ancestor(fname)
				or vim.fn.getcwd()
		end,
	},
}

-- =============================================
-- MASON & LSP SETUP
-- =============================================
require("mason").setup()
require("mason-lspconfig").setup({
	ensure_installed = {
		"bashls",
		"clangd",
		"emmet_ls",
		"eslint",
		"gopls",
		"html",
		"intelephense",
		"lua_ls",
		"pyright",
		"rust_analyzer",
		"tailwindcss",
	},
	handlers = {
		function(server_name)
			local config = server_configs[server_name] or {}
			config.capabilities = capabilities
			require("lspconfig")[server_name].setup(config)
		end,
	},
})

-- =============================================
-- COMPLETION (CMP) SETUP
-- =============================================
local cmp = require("cmp")
local cmp_select = { behavior = cmp.SelectBehavior.Select }

-- Base configuration
cmp.setup({
	sources = {
		{ name = "nvim_lsp", priority = 1000 },
		{ name = "luasnip", priority = 750 },
		{ name = "buffer", priority = 500 },
		{ name = "path", priority = 250 },
	},
	mapping = cmp.mapping.preset.insert({
		["<C-p>"] = cmp.mapping.select_prev_item(cmp_select),
		["<C-n>"] = cmp.mapping.select_next_item(cmp_select),
		["<C-y>"] = cmp.mapping.confirm({ select = true }),
		["<C-Space>"] = cmp.mapping.complete(),
	}),
	snippet = {
		expand = function(args)
			require("luasnip").lsp_expand(args.body)
		end,
	},
	window = {
		completion = cmp.config.window.bordered(),
		documentation = cmp.config.window.bordered(),
	},
})

-- =============================================
-- NULL-LS (DIAGNOSTICS/FORMATTING)
-- =============================================

-- ftdetect/blade.lua
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "*.blade.php",
	callback = function()
		vim.bo.filetype = "blade"
	end,
})

local null_ls = require("null-ls")
null_ls.setup({
	sources = {
		null_ls.builtins.formatting.stylua,
		null_ls.builtins.formatting.prettier.with({
			filetypes = { "blade" },
			command = "npx",
			args = { "prettier", "--stdin-filepath", "$FILENAME" },
			prefer_local = "node_modules/.bin",
		}),
		-- null_ls.builtins.diagnostics.eslint,
		-- null_ls.builtins.completion.spell,
	},
})

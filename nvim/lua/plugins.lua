return {
  { "rose-pine/neovim", name = "rose-pine" },
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },

  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
    config = function()
      local ts = require("nvim-treesitter")
      ts.setup({
        ensure_installed = {
          "c", "lua", "vim", "vimdoc", "query",
          "markdown", "markdown_inline",
          "javascript", "typescript", "tsx", "python",
          "html", "go", "php", "php_only", "json", "css",
          "regex", "bash", "yaml", "toml", "blade",
          "sql", "dockerfile", "dart", "rust",
        },
        indent = { enable = true },
        highlight = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
            },
          },
        },
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "php", "php_only" },
        callback = function()
          vim.b.indentexpr = "nvim_treesitter#indentexpr()"
        end,
      })
    end,
  },

  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  { "ThePrimeagen/harpoon" },
  { "mbbill/undotree" },
  { "numToStr/Comment.nvim" },
  { "windwp/nvim-ts-autotag" },

  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    config = function()
      require("mason").setup()
    end,
  },

  {
    "neovim/nvim-lspconfig",
    dependencies = { "williamboman/mason-lspconfig.nvim" },
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      local servers = {
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "basic",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },
        ts_ls = {
          init_options = { hostInfo = "neovim" },
        },
        lua_ls = {
          settings = {
            Lua = {
              diagnostics = { globals = { "vim" } },
              workspace = { library = vim.api.nvim_get_runtime_file("", true), checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        gopls = {},
        rust_analyzer = {},
        intelephense = {
          settings = {
intelephense = {
          filetypes = { "php", "blade" },
              licenseKey = "00REIZG3OJICXJJ",
              files = {
                maxSize = 5000000000,
                associations = { "*.blade.php", "*.php" },
                exclude = {
                  "**/.git/**",
                  "**/node_modules/**",
                  "**/vendor/**/tests/**",
                  "**/vendor/**/vendor/**",
                },
              },
              environment = {
                phpVersion = "8.3",
                includePaths = { "vendor", "app", "resources/views" },
              },
              telemetry = { enable = false },
              stubs = {
                "bcmath", "bz2", "Core", "curl", "date", "dom", "fileinfo",
                "filter", "gd", "hash", "json", "libxml", "mbstring", "openssl",
                "pcre", "PDO", "phar", "readline", "Reflection", "session",
                "SimpleXML", "sodium", "standard", "tokenizer", "xml", "xmlwriter",
                "zip", "zlib",
                "laravel", "app", "auth", "cache", "config", "event", "filesystem",
                "foundation", "http", "log", "mail", "queue", "routing", "support",
                "validation", "view", " illuminate", "facades",
              },
              diagnostics = {
                enable = true,
                undefinedTypes = true,
                undefinedFunctions = true,
                undefinedMethods = true,
              },
              completion = {
                fullyQualifyGlobalConstantsAndFunctions = true,
                insertUseDeclaration = true,
              },
            },
          },
        },
        html = { filetypes = { "html", "blade" } },
        tailwindcss = {
          filetypes = { "blade", "html", "css" },
          settings = {
            tailwindCSS = {
              includeLanguages = { blade = "html" },
            },
          },
        },
        emmet_ls = { filetypes = { "html", "blade", "css" } },
        cssls = { filetypes = { "css", "scss", "less" } },
        jsonls = {},
        yamlls = {},
        dockerls = {},
        clangd = {},
        bashls = {},
      }

      local installed = vim.tbl_keys(servers)
      vim.list_extend(installed, { "stylua", "prettierd" })

      require("mason-lspconfig").setup({
        ensure_installed = installed,
        handlers = {
          function(server_name)
            local invalid = {
              ["null-ls"] = true,
              ["jedi_language_server"] = true,
              ["stylua"] = true,
              ["prettierd"] = true,
            }
            if invalid[server_name] then return end
            local config = {
              capabilities = capabilities,
              settings = servers[server_name] and servers[server_name].settings or {},
              init_options = servers[server_name] and servers[server_name].init_options or {},
            }
            if servers[server_name].filetypes then
              config.filetypes = servers[server_name].filetypes
            end
            lspconfig[server_name].setup(config)
          end,
        },
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufnr = args.buf
          local client = vim.lsp.get_client_by_id(args.data.client_id)

          vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr, desc = "Go to definition" })
          vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Show hover" })
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr, desc = "Code actions" })
          vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, { buffer = bufnr, desc = "Open diagnostic float" })
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { buffer = bufnr, desc = "Rename" })
          vim.keymap.set("n", "<leader>rf", vim.lsp.buf.references, { buffer = bufnr, desc = "References" })

          if client and client.server_capabilities.signatureHelpProvider then
            vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, { buffer = bufnr, desc = "Signature help" })
          end
        end,
      })
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-p>"] = cmp.mapping.select_prev_item(),
          ["<C-y>"] = cmp.mapping.confirm({ select = true }),
          ["<C-Space>"] = cmp.mapping.complete(),
        }),
        sources = {
          { name = "nvim_lsp", priority = 1000 },
          { name = "luasnip", priority = 750 },
          { name = "buffer", priority = 500 },
          { name = "path", priority = 250 },
        },
      })
    end,
  },

  {
    "nvimtools/none-ls.nvim",
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.formatting.prettierd,
          null_ls.builtins.formatting.gofmt,
          null_ls.builtins.diagnostics.trail_space,
        },
      })
    end,
  },

  {
    "ray-x/lsp_signature.nvim",
    event = "InsertEnter",
    config = function()
      require("lsp_signature").setup({
        bind = true,
        handler_opts = { border = "rounded" },
        hint_enable = false,        -- no inline virtual text, just the float
        floating_window = true,
        floating_window_above_cur_line = true,
        close_timeout = 4000,
        toggle_key = "<C-k>",       -- manually toggle the float in insert mode
      })
    end,
  },

  { "supermaven-inc/supermaven-nvim", config = function() require("supermaven-nvim").setup({}) end },

  {
    "adalessa/laravel.nvim",
    cmd = "Laravel",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>la", "<cmd>Laravel artisan<cr>", desc = "Laravel artisan" },
      { "<leader>ll", "<cmd>Laravel<cr>", desc = "Laravel picker" },
    },
  },

  { "jwalton512/vim-blade" },
}

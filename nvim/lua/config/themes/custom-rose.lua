function RosePine_Theme()
    vim.cmd("colorscheme catppuccin-mocha") -- Using Catppuccin-mocha as a base
    vim.cmd([[set guicursor=n-v-c:block-Cursor\/lCursor,i-ci-ve:ver25-Cursor\/lCursor,r-cr:hor20,o:hor50]])

    -- Base colors inspired by Rosé Pine Dark but with custom variations
    local bg_deep = "#191724"    -- Base background (slightly deeper than original)
    local bg_surface = "#1f1d2e" -- Surface background
    local bg_overlay = "#26233a" -- Overlays and secondary surfaces
    local bg_inactive = "#282638"
    local fg_main = "#e0def4"    -- Main foreground text
    local fg_muted = "#908caa"   -- Muted foreground text
    local fg_subtle = "#6e6a86"  -- Subtle foreground text

    -- Accent colors
    local rose = "#ebbcba"        -- Rose
    local pine = "#31748f"        -- Pine
    local love = "#eb6f92"        -- Love (red/pink)
    local foam = "#9ccfd8"        -- Foam (cyan)
    local gold = "#f6c177"        -- Gold
    local iris = "#c4a7e7"        -- Iris (purple)
    local subtle_iris = "#9a86c9" -- Subtle iris (muted purple)

    -- Custom accent colors to complement Rose Pine
    local deep_pine = "#235a70"    -- Deeper pine
    local vintage_rose = "#d9adad" -- Vintage rose
    local faded_gold = "#c8a088"   -- Faded gold
    local muted_green = "#9bab7e"  -- Muted green accent

    -- Set cursor and normal background
    vim.api.nvim_set_hl(0, "Cursor", { fg = bg_deep, bg = rose })
    vim.api.nvim_set_hl(0, "Normal", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NormalFloat", { fg = fg_main, bg = bg_deep })

    -- Ensure all UI panels have dark backgrounds
    -- vim.api.nvim_set_hl(0, "NormalNC", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NormalNC", { fg = fg_muted, bg = bg_inactive })  -- Slightly different dark color
    vim.api.nvim_set_hl(0, "WinBar", { fg = fg_muted, bg = bg_deep })
    vim.api.nvim_set_hl(0, "WinBarNC", { fg = fg_subtle, bg = bg_inactive })
    vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = bg_deep, bg = bg_deep })

    -- File explorer backgrounds
    vim.api.nvim_set_hl(0, "netrwDir", { fg = foam, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Directory", { fg = foam, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "netrwClassify", { fg = subtle_iris, bg = bg_deep })
    vim.api.nvim_set_hl(0, "netrwTreeBar", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "netrwPlain", { fg = fg_main, bg = bg_deep })

    -- NvimTree backgrounds
    vim.api.nvim_set_hl(0, "NvimTreeNormal", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = bg_deep, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeVertSplit", { fg = bg_deep, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { fg = bg_deep, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = foam, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = foam, bold = true, italic = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName", { fg = fg_muted, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeFileName", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = vintage_rose, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeStatusLine", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "NvimTreeStatusLineNC", { fg = fg_muted, bg = bg_deep })

    -- Terminal colors
    vim.api.nvim_set_hl(0, "Terminal", { fg = fg_main, bg = bg_deep })

    -- Syntax highlighting for code
    vim.api.nvim_set_hl(0, "Identifier", { fg = pine })              -- Pine for identifiers
    vim.api.nvim_set_hl(0, "Statement", { fg = love })               -- Love for statements
    vim.api.nvim_set_hl(0, "Keyword", { fg = iris, bold = true })    -- Bold iris for keywords
    vim.api.nvim_set_hl(0, "Function", { fg = foam, bold = false })  -- Foam for functions
    vim.api.nvim_set_hl(0, "String", { fg = muted_green })           -- Muted green for strings
    vim.api.nvim_set_hl(0, "Number", { fg = gold })                  -- Gold for numbers
    vim.api.nvim_set_hl(0, "Boolean", { fg = love })                 -- Love for booleans
    vim.api.nvim_set_hl(0, "Operator", { fg = subtle_iris })         -- Subtle iris for operators
    vim.api.nvim_set_hl(0, "Type", { fg = faded_gold, bold = true }) -- Bold faded gold for types
    vim.api.nvim_set_hl(0, "Special", { fg = vintage_rose })         -- Vintage rose for special chars

    -- Lua-specific syntax
    vim.api.nvim_set_hl(0, "luaFunc", { fg = foam })                 -- Foam for Lua functions
    vim.api.nvim_set_hl(0, "luaStatement", { fg = love })            -- Love for Lua statements
    vim.api.nvim_set_hl(0, "luaString", { fg = muted_green })        -- Muted green for Lua strings
    vim.api.nvim_set_hl(0, "luaOperator", { fg = subtle_iris })      -- Subtle iris for Lua operators
    vim.api.nvim_set_hl(0, "luaKeyword", { fg = iris, bold = true }) -- Bold iris for keywords
    vim.api.nvim_set_hl(0, "luaIn", { fg = iris })                   -- Iris for Lua 'in' keyword

    -- Essential UI elements
    vim.api.nvim_set_hl(0, "LineNr", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "LineNrNC", { fg = fg_subtle, bg = bg_inactive })
    vim.api.nvim_set_hl(0, "CursorLineNr", { fg = rose, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Comment", { fg = fg_subtle, italic = true })
    vim.api.nvim_set_hl(0, "NonText", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Conceal", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "SpecialKey", { fg = fg_muted, bg = bg_deep })

    -- Status line and tabs with dark backgrounds
    vim.api.nvim_set_hl(0, "StatusLine", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "StatusLineNC", { fg = fg_muted, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TabLine", { fg = fg_muted, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TabLineFill", { fg = fg_muted, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TabLineSel", { fg = fg_main, bg = bg_overlay, bold = true })

    -- Cursor line and column
    vim.api.nvim_set_hl(0, "CursorLine", { bg = bg_surface })
    vim.api.nvim_set_hl(0, "CursorColumn", { bg = bg_surface })
    vim.api.nvim_set_hl(0, "ColorColumn", { bg = bg_surface })

    -- Help text highlights with consistent background
    vim.api.nvim_set_hl(0, "helpHyperTextEntry", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "helpHeader", { fg = fg_main, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "helpHeadline", { fg = iris, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "helpSectionDelim", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "helpExample", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "helpHyperTextJump", { fg = foam, underline = true, bg = bg_deep })

    -- Command line highlighting
    vim.api.nvim_set_hl(0, "MsgArea", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "CommandLine", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "CommandLineCursor", { fg = bg_deep, bg = fg_main })

    -- Search highlighting
    vim.api.nvim_set_hl(0, "Search", { fg = bg_deep, bg = gold })
    vim.api.nvim_set_hl(0, "IncSearch", { fg = bg_deep, bg = rose })
    vim.api.nvim_set_hl(0, "CurSearch", { fg = bg_deep, bg = rose })

    -- Visual selection
    vim.api.nvim_set_hl(0, "Visual", { fg = fg_main, bg = bg_overlay })
    vim.api.nvim_set_hl(0, "VisualNOS", { fg = fg_main, bg = bg_overlay })

    -- Splits and window borders
    vim.api.nvim_set_hl(0, "VertSplit", { fg = bg_overlay, bg = bg_deep })
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = bg_overlay, bg = bg_deep })

    -- Completion menu with dark background
    vim.api.nvim_set_hl(0, "Pmenu", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "PmenuSel", { fg = bg_deep, bg = rose })
    vim.api.nvim_set_hl(0, "PmenuSbar", { bg = bg_deep })
    vim.api.nvim_set_hl(0, "PmenuThumb", { bg = fg_subtle })

    -- Folds with dark background
    vim.api.nvim_set_hl(0, "Folded", { fg = fg_muted, bg = bg_deep, italic = true })
    vim.api.nvim_set_hl(0, "FoldColumn", { fg = fg_subtle, bg = bg_deep })

    -- Git integration with dark backgrounds
    vim.api.nvim_set_hl(0, "DiffAdd", { fg = muted_green, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiffChange", { fg = gold, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiffDelete", { fg = love, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiffText", { fg = foam, bg = bg_surface, bold = true })

    -- Errors, warnings, and diagnostics
    vim.api.nvim_set_hl(0, "Error", { fg = love, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Warning", { fg = gold, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Info", { fg = foam, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Hint", { fg = subtle_iris, bg = bg_deep })
    vim.api.nvim_set_hl(0, "Todo", { fg = bg_deep, bg = gold, bold = true })

    -- Floating windows with dark backgrounds
    vim.api.nvim_set_hl(0, "FloatBorder", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "FloatTitle", { fg = rose, bg = bg_deep, bold = true })

    -- LSP related with dark backgrounds
    vim.api.nvim_set_hl(0, "LspReferenceText", { bg = bg_overlay })
    vim.api.nvim_set_hl(0, "LspReferenceRead", { bg = bg_overlay })
    vim.api.nvim_set_hl(0, "LspReferenceWrite", { bg = bg_overlay, underline = true })
    vim.api.nvim_set_hl(0, "DiagnosticError", { fg = love, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = gold, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = foam, bg = bg_deep })
    vim.api.nvim_set_hl(0, "DiagnosticHint", { fg = subtle_iris, bg = bg_deep })

    -- Telescope colors with dark backgrounds
    vim.api.nvim_set_hl(0, "TelescopeNormal", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopeBorder", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopeSelection", { fg = fg_main, bg = bg_surface })
    vim.api.nvim_set_hl(0, "TelescopeMatching", { fg = vintage_rose, bold = true, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopePrompt", { fg = fg_main, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopePromptBorder", { fg = fg_subtle, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopePromptPrefix", { fg = rose, bg = bg_deep })
    vim.api.nvim_set_hl(0, "TelescopeResultsTitle", { fg = rose, bg = bg_deep })

    -- Specific plugin backgrounds
    vim.api.nvim_set_hl(0, "WhichKeyFloat", { bg = bg_deep })
    vim.api.nvim_set_hl(0, "NotifyBackground", { bg = bg_deep })
    vim.api.nvim_set_hl(0, "BufferLineBackground", { bg = bg_deep })
    vim.api.nvim_set_hl(0, "BufferLineFill", { bg = bg_deep })

    print("Custom Rosé Pine Dark theme applied with consistent dark backgrounds across all UI panels!")
end

return RosePine_Theme


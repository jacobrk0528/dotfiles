function Coffee_Theme()
    vim.cmd("colorscheme catppuccin-latte") -- Using Catppuccin as base
    vim.cmd([[set guicursor=n-v-c:block-Cursor\/lCursor,i-ci-ve:ver25-Cursor\/lCursor,r-cr:hor20,o:hor50]])

    -- Base colors
    local coffee_bg = "#f5deb3"      -- Light coffee cream background
    local coffee_text = "#3b2c20"    -- Dark coffee brown for text
    local coffee_light = "#dbc1a7"   -- Light coffee/cream
    local coffee_medium = "#967259"  -- Medium roast coffee
    local coffee_dark = "#634832"    -- Dark roast coffee
    local coffee_accent1 = "#9b6647" -- Cinnamon accent
    local coffee_accent2 = "#a05e2c" -- Caramel accent
    local coffee_accent3 = "#704214" -- Espresso accent
    local coffee_green = "#4a6b22"   -- Coffee plant green
    local coffee_red = "#872d2d"     -- Reddish coffee cherry

    -- Set cursor and normal background
    vim.api.nvim_set_hl(0, "Cursor", { fg = coffee_dark, bg = coffee_light })
    vim.api.nvim_set_hl(0, "Normal", { fg = coffee_text, bg = coffee_bg })

    -- Syntax highlighting for code
    vim.api.nvim_set_hl(0, "Identifier", { fg = coffee_accent3 })           -- Espresso for identifiers
    vim.api.nvim_set_hl(0, "Statement", { fg = coffee_accent2 })            -- Caramel for statements
    vim.api.nvim_set_hl(0, "Keyword", { fg = coffee_accent2, bold = true }) -- Bold caramel for keywords
    vim.api.nvim_set_hl(0, "Function", { fg = coffee_dark, bold = true })   -- Bold dark coffee for functions
    vim.api.nvim_set_hl(0, "String", { fg = coffee_green })                 -- Coffee plant green for strings
    vim.api.nvim_set_hl(0, "Number", { fg = coffee_accent1 })               -- Cinnamon for numbers
    vim.api.nvim_set_hl(0, "Boolean", { fg = coffee_accent2 })              -- Caramel for booleans
    vim.api.nvim_set_hl(0, "Operator", { fg = coffee_medium })              -- Medium roast for operators
    vim.api.nvim_set_hl(0, "Type", { fg = coffee_accent3, bold = true })    -- Bold espresso for types
    vim.api.nvim_set_hl(0, "Special", { fg = coffee_red })                  -- Coffee cherry red for special chars

    -- Lua-specific syntax
    vim.api.nvim_set_hl(0, "luaFunc", { fg = coffee_dark, bold = true })       -- Bold dark coffee for Lua functions
    vim.api.nvim_set_hl(0, "luaStatement", { fg = coffee_accent2 })            -- Caramel for Lua statements
    vim.api.nvim_set_hl(0, "luaString", { fg = coffee_green })                 -- Coffee plant green for Lua strings
    vim.api.nvim_set_hl(0, "luaOperator", { fg = coffee_medium })              -- Medium roast for Lua operators
    vim.api.nvim_set_hl(0, "luaKeyword", { fg = coffee_accent2, bold = true }) -- Bold caramel for keywords
    vim.api.nvim_set_hl(0, "luaIn", { fg = coffee_accent2 })                   -- Caramel for Lua 'in' keyword

    -- Fix Netrw colors for better contrast
    vim.api.nvim_set_hl(0, "Directory", { fg = coffee_dark, bold = true })
    vim.api.nvim_set_hl(0, "netrwDir", { fg = coffee_dark, bold = true })
    vim.api.nvim_set_hl(0, "netrwClassify", { fg = coffee_medium })
    vim.api.nvim_set_hl(0, "netrwTreeBar", { fg = coffee_light })
    vim.api.nvim_set_hl(0, "netrwPlain", { fg = coffee_text })

    -- Fix text colors for NvimTree if you use it
    vim.api.nvim_set_hl(0, "NvimTreeNormal", { fg = coffee_text, bg = coffee_bg })
    vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = coffee_text, bg = coffee_bg })
    vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = coffee_dark, bold = true })
    vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = coffee_dark, bold = true })
    vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName", { fg = coffee_medium })
    vim.api.nvim_set_hl(0, "NvimTreeFileName", { fg = coffee_text })
    vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = coffee_accent3, bold = true })

    -- Essential UI elements
    vim.api.nvim_set_hl(0, "LineNr", { fg = coffee_medium })
    vim.api.nvim_set_hl(0, "Comment", { fg = "#8c7b6e", italic = true }) -- Lighter coffee for comments
    vim.api.nvim_set_hl(0, "NonText", { fg = coffee_light })
    vim.api.nvim_set_hl(0, "SpecialKey", { fg = coffee_medium })

    -- Status line and tabs
    vim.api.nvim_set_hl(0, "StatusLine", { fg = coffee_bg, bg = coffee_dark })
    vim.api.nvim_set_hl(0, "StatusLineNC", { fg = coffee_light, bg = coffee_medium })
    vim.api.nvim_set_hl(0, "TabLine", { fg = coffee_text, bg = coffee_light })
    vim.api.nvim_set_hl(0, "TabLineFill", { fg = coffee_text, bg = coffee_light })
    vim.api.nvim_set_hl(0, "TabLineSel", { fg = coffee_bg, bg = coffee_dark, bold = true })

    -- Help text highlights
    vim.api.nvim_set_hl(0, "helpHyperTextEntry", { fg = coffee_text })
    vim.api.nvim_set_hl(0, "helpHeader", { fg = coffee_text, bold = true })
    vim.api.nvim_set_hl(0, "helpHeadline", { fg = coffee_accent3, bold = true })
    vim.api.nvim_set_hl(0, "helpSectionDelim", { fg = coffee_medium })

    -- Command line highlighting
    vim.api.nvim_set_hl(0, "MsgArea", { fg = coffee_text, bg = coffee_light })
    vim.api.nvim_set_hl(0, "CommandLine", { fg = coffee_text, bg = coffee_light })
    vim.api.nvim_set_hl(0, "CommandLineCursor", { fg = coffee_light, bg = coffee_text })

    -- Search highlighting
    vim.api.nvim_set_hl(0, "Search", { fg = coffee_bg, bg = coffee_accent1 })
    vim.api.nvim_set_hl(0, "IncSearch", { fg = coffee_bg, bg = coffee_accent2 })

    -- Visual selection
    vim.api.nvim_set_hl(0, "Visual", { fg = coffee_bg, bg = coffee_medium })

    -- Splits and window borders
    vim.api.nvim_set_hl(0, "VertSplit", { fg = coffee_light, bg = coffee_bg })
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = coffee_light, bg = coffee_bg })

    -- Completion menu
    vim.api.nvim_set_hl(0, "Pmenu", { fg = coffee_text, bg = coffee_light })
    vim.api.nvim_set_hl(0, "PmenuSel", { fg = coffee_bg, bg = coffee_dark })
    vim.api.nvim_set_hl(0, "PmenuSbar", { bg = coffee_light })
    vim.api.nvim_set_hl(0, "PmenuThumb", { bg = coffee_medium })

    -- Git integration (if using fugitive or gitsigns)
    vim.api.nvim_set_hl(0, "DiffAdd", { fg = coffee_green, bg = "#e8f0e8" })
    vim.api.nvim_set_hl(0, "DiffChange", { fg = coffee_accent1, bg = "#f0e8e0" })
    vim.api.nvim_set_hl(0, "DiffDelete", { fg = coffee_red, bg = "#f0e0e0" })
    vim.api.nvim_set_hl(0, "DiffText", { fg = coffee_accent2, bg = "#f0e8d0", bold = true })

    -- Errors, warnings, and diagnostics
    vim.api.nvim_set_hl(0, "Error", { fg = coffee_red })
    vim.api.nvim_set_hl(0, "Warning", { fg = coffee_accent1 })
    vim.api.nvim_set_hl(0, "Todo", { fg = coffee_accent3, bg = coffee_light, bold = true })

    print("Coffee theme applied - enjoy your brew!")
end

return Coffee_Theme

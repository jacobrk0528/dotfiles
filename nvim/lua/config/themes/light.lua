function Light_Theme()
    vim.cmd("colorscheme catppuccin-latte")
    vim.cmd([[set guicursor=n-v-c:block-Cursor\/lCursor,i-ci-ve:ver25-Cursor\/lCursor,r-cr:hor20,o:hor50]])

    vim.api.nvim_set_hl(0, "Cursor", { fg = "#6e6d8d", bg = "#000000" })
    vim.api.nvim_set_hl(0, "Normal", { bg = "#e6e6d8" })

    -- Improved syntax highlighting for code
    vim.api.nvim_set_hl(0, "Identifier", { fg = "#000080" })           -- Dark blue for identifiers
    vim.api.nvim_set_hl(0, "Statement", { fg = "#8B0000" })            -- Dark red for statements
    vim.api.nvim_set_hl(0, "Keyword", { fg = "#8B0000", bold = true }) -- Bold dark red for keywords
    vim.api.nvim_set_hl(0, "Function", { fg = "#0000CD" })             -- Medium blue for functions
    vim.api.nvim_set_hl(0, "String", { fg = "#006400" })               -- Dark green for strings
    vim.api.nvim_set_hl(0, "Number", { fg = "#B8860B" })               -- Dark goldenrod for numbers
    vim.api.nvim_set_hl(0, "Boolean", { fg = "#8B0000" })              -- Dark red for booleans
    vim.api.nvim_set_hl(0, "Operator", { fg = "#4B0082" })             -- Indigo for operators
    vim.api.nvim_set_hl(0, "Type", { fg = "#4B0082" })                 -- Indigo for types
    vim.api.nvim_set_hl(0, "Special", { fg = "#0550a0" })              -- Dark blue for special chars

    -- Lua-specific syntax
    vim.api.nvim_set_hl(0, "luaFunc", { fg = "#0000CD" })                 -- Medium blue for Lua functions
    vim.api.nvim_set_hl(0, "luaStatement", { fg = "#8B0000" })            -- Dark red for Lua statements
    vim.api.nvim_set_hl(0, "luaString", { fg = "#006400" })               -- Dark green for Lua strings
    vim.api.nvim_set_hl(0, "luaOperator", { fg = "#4B0082" })             -- Indigo for Lua operators
    vim.api.nvim_set_hl(0, "luaKeyword", { fg = "#8B0000", bold = true }) -- Bold dark red
    vim.api.nvim_set_hl(0, "luaIn", { fg = "#8B0000" })                   -- Dark red

    -- Fix Netrw colors for better contrast
    vim.api.nvim_set_hl(0, "Directory", { fg = "#0550a0", bold = true })
    vim.api.nvim_set_hl(0, "netrwDir", { fg = "#0550a0", bold = true })
    vim.api.nvim_set_hl(0, "netrwClassify", { fg = "#333333" })
    vim.api.nvim_set_hl(0, "netrwTreeBar", { fg = "#555555" })
    vim.api.nvim_set_hl(0, "netrwPlain", { fg = "#333333" })

    -- Fix text colors for NvimTree if you use it
    vim.api.nvim_set_hl(0, "NvimTreeNormal", { fg = "#333333", bg = "#e6e6d8" })
    vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { fg = "#333333", bg = "#e6e6d8" })
    vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = "#0550a0", bold = true })
    vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = "#0550a0", bold = true })
    vim.api.nvim_set_hl(0, "NvimTreeEmptyFolderName", { fg = "#0550a0" })
    vim.api.nvim_set_hl(0, "NvimTreeFileName", { fg = "#333333" })
    vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = "#1a1a1a", bold = true })

    -- Essential UI elements
    vim.api.nvim_set_hl(0, "LineNr", { fg = "#555555" })
    vim.api.nvim_set_hl(0, "Comment", { fg = "#505050", italic = true })
    vim.api.nvim_set_hl(0, "NonText", { fg = "#505050" })
    vim.api.nvim_set_hl(0, "SpecialKey", { fg = "#333333" })

    -- Help text highlights
    vim.api.nvim_set_hl(0, "helpHyperTextEntry", { fg = "#333333" })
    vim.api.nvim_set_hl(0, "helpHeader", { fg = "#333333", bold = true })
    vim.api.nvim_set_hl(0, "helpHeadline", { fg = "#333333", bold = true })
    vim.api.nvim_set_hl(0, "helpSectionDelim", { fg = "#555555" })

    -- Command line highlighting
    vim.api.nvim_set_hl(0, "MsgArea", { fg = "#333333", bg = "#d8d8c0" })
    vim.api.nvim_set_hl(0, "CommandLine", { fg = "#333333", bg = "#d8d8c0" })
    vim.api.nvim_set_hl(0, "CommandLineCursor", { fg = "#d8d8c0", bg = "#333333" })
end

return Light_Theme

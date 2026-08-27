-- Let the terminal's background show through.
--
-- ghostty is set to 85% opacity, but Neovim paints its own background over the
-- whole window, so the transparency is invisible until these groups are
-- cleared. This has to run AFTER a theme is applied: the themes in
-- config/themes set Normal's background explicitly, after `:colorscheme`, so a
-- ColorScheme autocmd alone fires too early and gets overwritten.

local M = {}

-- Cleared with :highlight rather than nvim_set_hl so each group keeps its own
-- foreground and attributes, and only the background is dropped.
local groups = {
    "Normal",
    "NormalNC",
    "NormalFloat",
    "FloatBorder",
    "SignColumn",
    "LineNr",
    "CursorLineNr",
    "EndOfBuffer",
    "FoldColumn",
    "Folded",
    "NonText",
    "WinBar",
    "WinBarNC",
    "WinSeparator",
    "VertSplit",
    "MsgArea",
    "TabLine",
    "TabLineFill",
    "StatusLine",
    "StatusLineNC",
    -- telescope: its windows would otherwise float as opaque slabs
    "TelescopeNormal",
    "TelescopeBorder",
    "TelescopePromptNormal",
    "TelescopePromptBorder",
    "TelescopeResultsNormal",
    "TelescopeResultsBorder",
    "TelescopePreviewNormal",
    "TelescopePreviewBorder",
}

function M.apply()
    if vim.g.transparency_disabled then
        return
    end

    -- Whatever the theme painted as the window background. Read before
    -- anything is cleared, which is why apply() must run right after a theme.
    local base = vim.api.nvim_get_hl(0, { name = "Normal" }).bg

    for _, group in ipairs(groups) do
        vim.cmd("highlight " .. group .. " guibg=NONE ctermbg=NONE")
    end

    -- Then everything else carrying that same background. The themes set it on
    -- groups the list above will never anticipate — netrw's Directory and
    -- netrwPlain, for instance, which rendered as solid blocks behind every
    -- filename. Matching on the colour keeps genuinely coloured backgrounds
    -- (Visual, Search, CursorLine, diagnostics) intact.
    if base == nil then
        return
    end

    for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
        if hl.bg == base and not hl.link then
            vim.cmd("highlight " .. name .. " guibg=NONE ctermbg=NONE")
        end
    end
end

function M.toggle()
    vim.g.transparency_disabled = not vim.g.transparency_disabled

    if vim.g.transparency_disabled then
        -- Reapplying the theme is what restores the backgrounds.
        vim.cmd("doautocmd ColorScheme")
        vim.notify("Transparency off (reload the theme to fully restore)")
    else
        M.apply()
        vim.notify("Transparency on")
    end
end

vim.api.nvim_create_user_command("Transparency", M.toggle, {})

return M

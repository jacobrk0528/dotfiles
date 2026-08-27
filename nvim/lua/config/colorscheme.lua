-- Applies the theme, then clears the backgrounds so the terminal's
-- transparency shows through. Transparency has to come after: the theme sets
-- Normal's background itself, after `:colorscheme`.
local transparency = require("config.transparency")

dofile(vim.fn.stdpath("config") .. "/lua/config/themes/custom-rose.lua")()
transparency.apply()

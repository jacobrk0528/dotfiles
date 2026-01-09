local function apply_dark_theme()
    dofile(vim.fn.stdpath('config') .. '/lua/config/themes/custom-rose.lua')()
end

local function apply_light_theme()
    dofile(vim.fn.stdpath('config') .. '/lua/config/themes/coffee.lua')()
end

-- Theme toggle function to handle both terminal and Neovim themes
local function toggle_theme()
    local is_dark = vim.env.TERMINAL_THEME ~= "light"

    is_dark = not is_dark

    vim.g.is_dark_theme = is_dark

    local theme_cmd = is_dark and "dark" or "light"
    vim.fn.system("source ~/.zshrc && theme " .. theme_cmd)

    vim.env.TERMINAL_THEME = theme_cmd
    vim.fn.system("echo 'export TERMINAL_THEME=" .. theme_cmd .. "' > ~/.terminal_theme")

    vim.env.TERMINAL_THEME = theme_cmd

    if not is_dark then
        apply_light_theme()
    else
        apply_dark_theme()
    end

    local message = "Switched to " .. (is_dark and "dark" or "light") .. " theme"

    vim.notify(message)
    return message
end

vim.api.nvim_create_user_command('Theme', function()
    toggle_theme()
end, {})

vim.keymap.set('n', '<leader>tt', function()
    toggle_theme()
end, { noremap = true, silent = true })

----------------------------
-- keep theme synced
----------------------------
local function setup_theme_sync()
    local check_terminal_theme = function()
        local handle = io.open(vim.fn.expand("~/.terminal_theme"), "r")

        if not handle then return end
        local content = handle:read("*a")
        handle:close()

        local terminal_theme = content:match("TERMINAL_THEME=(%w+)")

        if not terminal_theme then return end
        local is_dark = terminal_theme == "dark"

        if vim.g.is_dark_theme ~= is_dark then
            vim.g.is_dark_theme = is_dark
            if not is_dark then
                apply_light_theme()
            else
                apply_dark_theme()
            end

            vim.notify("Theme synchronized to " .. terminal_theme)
        end
    end

    check_terminal_theme()

    local timer_id = nil
    local function schedule_check()
        timer_id = vim.defer_fn(function()
            check_terminal_theme()
            schedule_check()
        end, 30 * 1000) -- x * 1000 = x seconds 
    end

    schedule_check()

    return function()
        if timer_id then
            vim.fn.timer_stop(timer_id)
            timer_id = nil
        end
    end
end

local theme_timer = setup_theme_sync()

vim.g.theme_timer = theme_timer

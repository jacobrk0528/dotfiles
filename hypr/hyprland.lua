-- Hyprland Lua configuration
-- See https://wiki.hypr.land/Configuring/Start/


--------------------
---- ENV VARS ----
--------------------

-- The session runs under uwsm, so environment variables live in
-- ~/dotfiles/uwsm/env and uwsm/env-hyprland, where systemd units and portals
-- see them too (https://wiki.hypr.land/Useful-Utilities/Systemd-start/).


--------------------
---- MONITORS ----
--------------------

local hostname = io.popen("cat /etc/hostname"):read("*l")

hl.monitor({ output = "desc:Acer Technologies XB273 GX 0x15205CF0", mode = "1920x1080@60", position = "0x0", scale = 1 })		-- Middle
-- Left and Right are the two Sceptres. They report byte-identical EDID -- same
-- make, model, and the placeholder serial 0x00000001 -- so a desc: selector
-- matches BOTH and stacks them at one position (they came up mirrored that
-- way). Connector names do distinguish them, but a driver upgrade renumbered
-- DP-7/DP-8 to DP-5/DP-6 and silently dropped both rules.
--
-- So hypr/scripts/side-monitors resolves the pair at login (they are the
-- connected monitors that are not the two Acers, which DO have unique serials)
-- and caches the connectors below. Reading that cache here -- rather than
-- applying only via hyprctl -- is what makes the placement survive a reload.
-- Which one is physically left cannot be detected; SUPER+CTRL+M flips it.
local side = { LEFT = nil, RIGHT = nil }
do
    local path = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
                 .. "/hypr/side-monitors.conf"
    local fh = io.open(path)
    if fh then
        for line in fh:lines() do
            local k, v = line:match("^(%u+)=(.+)$")
            if k == "LEFT" or k == "RIGHT" then side[k] = v end
        end
        fh:close()
    end
end

-- No cache yet (first ever boot): leave them auto-placed. The autostart call to
-- side-monitors writes the cache and fixes the layout a moment later.
if side.LEFT and side.RIGHT then
    hl.monitor({ output = side.RIGHT, mode = "1920x1080@60", position = "1920x0", scale = 1 })   -- Right
    hl.monitor({ output = side.LEFT,  mode = "1920x1080@60", position = "-1920x0", scale = 1 })  -- Left
end
hl.monitor({ output = "desc:Acer Technologies PM161Q C 25230110E4HA1", mode = "1920x1080@60", position = "0x1080", scale = 1 }) -- Bottom

-----------------------
---- MY PROGRAMS ----
-----------------------

-- Palette generated from quickshell/theme.json (quickshell/scripts/apply-theme)
local colors = dofile(os.getenv("HOME") .. "/.config/hypr/colors.lua")

local terminal    = "ghostty"
local fileManager = "/home/jkrebs/dotfiles/scripts/yazi-window"
-- Kept alongside yazi for the things yazi has no native answer to: sftp:// and
-- smb:// browsing.
local dolphin     = "dolphin"
-- Wrapped in a systemd cgroup scope as a backstop against a total runaway. NOTE: the
-- ballooning BigQuery/Dataform tabs (8GB+ per renderer, then GC lock-up) turned out to be
-- Dark Reader re-styling the Cloud Console on every DOM mutation, not browser memory
-- policy; fix that by disabling Dark Reader on console.cloud.google.com. MemoryHigh is
-- deliberately loose: the scope covers the WHOLE browser (all windows/tabs), and a low
-- value throttles every tab via kernel reclaim long before any single leaker is helped.
local browser     = 'systemd-run --user --scope --collect -p MemoryHigh=32G -p MemoryMax=64G -- brave --profile-picker --js-flags="--max-old-space-size=4096"'
local slack       = "slack"
local btop        = "ghostty --title=btop -e bash -c 'btop'"


--------------------
---- AUTOSTART ----
--------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/dotfiles/hypr/scripts/night-mode startup")
    -- hypridle and hyprpolkitagent run as enabled systemd user units.
    -- Long-running helpers go through `uwsm app --` so each gets its own unit
    -- instead of living inside the compositor's.
    hl.exec_cmd("uwsm app -- qs")
    -- Re-resolve which connectors the two identical Sceptres are on and place
    -- them. Self-corrects after a driver upgrade renumbers the connectors.
    hl.exec_cmd(os.getenv("HOME") .. "/dotfiles/hypr/scripts/side-monitors --quiet")
    hl.exec_cmd(os.getenv("HOME") .. "/dotfiles/scripts/start_tmux_sessions.sh")
    -- Placement is done by the script, not by exec workspace hints: the hint
    -- targets the next window to map rather than the process launched, and a
    -- visible special workspace swallows everything opened after it.
    hl.exec_cmd(os.getenv("HOME") .. "/dotfiles/scripts/start-apps.sh")
	hl.exec_cmd("uwsm app -- wl-paste --type text --watch cliphist store")
	hl.exec_cmd("uwsm app -- wl-paste --type image --watch cliphist store")
	-- Titles copied images with a local vision model for the clipboard panel.
	hl.exec_cmd("uwsm app -- wl-paste --type image --watch " .. os.getenv("HOME") .. "/dotfiles/quickshell/scripts/clip-label --copied")
	hl.exec_cmd("uwsm app -- wl-clip-persist --clipboard regular")
end)


---------------------------
---- LOOK AND FEEL ----
---------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 12,

        border_size = 1,

        col = {
            active_border   = colors.active_border,
            inactive_border = colors.inactive_border,
        },

        resize_on_border = false,
        allow_tearing    = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 8,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 2,
            color        = colors.shadow,
        },

        blur = {
            enabled    = true,
            size       = 8,
            passes     = 2,
            vibrancy   = 0.1696,
            brightness = 1.0,
        },
    },

    animations = {
        enabled = false,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },

    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "ctrl:nocaps,altwin:menu_win",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = -0.8,

        touchpad = {
            natural_scroll = false,
        },
    },
})

-- Animation curves (kept for easy enable later)
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

hl.animation({ leaf = "global",        enabled = false, speed = 10,   bezier = "default"      })
hl.animation({ leaf = "border",        enabled = false, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = false, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = false, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = false, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = false, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = false, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = false, speed = 3.03, bezier = "quick"        })
hl.animation({ leaf = "layers",        enabled = false, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = false, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = false, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = false, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = false, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = false, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = false, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = false, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = false, speed = 7,    bezier = "quick"        })


-----------------
---- INPUT ----
-----------------

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })


---------------------------
---- LAYER RULES ----
---------------------------

-- make the quickshell surfaces pretty
-- Top bar + dock. ignore_alpha keeps the blur inside their rounded corners.
hl.layer_rule({ match = { namespace = "quickshell-bar" },           blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "quickshell-notifications" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell-osd" },           blur = true })
hl.layer_rule({ match = { namespace = "quickshell-overlay" },       blur = true })
-- Control center + notifications: ignore_alpha sits above the scrim's 0.45
-- so only the panel itself is blurred, not the dimmed screen behind it.
hl.layer_rule({ match = { namespace = "quickshell-clear-overlay" }, blur = true, ignore_alpha = 0.5 })
-- ignore_alpha keeps the blur on the widget panels only, not the
-- fully transparent space between them.
hl.layer_rule({ match = { namespace = "quickshell-desktop" },       blur = true, ignore_alpha = 0.2 })

-- log windows go to special:logs
hl.window_rule({ match = { title = "bc_utils_log" }, workspace = "special:logs" })
hl.window_rule({ match = { title = "narsil_log"   }, workspace = "special:logs" })

-- YouTube Music goes to special:media. Chrome ignores the --class the launcher
-- passes for --app windows and derives one from the URL and profile instead, so
-- match the class it actually reports.
hl.window_rule({ match = { class = "chrome-music\\.youtube\\.com__.*" }, workspace = "special:media" })

-- yazi's own ghostty window (scripts/yazi-window), floated large enough for the
-- preview pane to be worth having. Three rules rather than one: a Lua table has
-- no key order, and size/center only land once the window is already floating.
-- Pixels rather than "70% 70%" — Hyprland 0.56's Lua rule parser silently drops
-- percentage sizes. Every monitor here is 1920x1080.
hl.window_rule({ name = "yazi-float",  match = { class = "com\\.jkrebs\\.yazi" }, float  = true })
hl.window_rule({ name = "yazi-size",   match = { class = "com\\.jkrebs\\.yazi" }, size   = "1344 756" })
hl.window_rule({ name = "yazi-center", match = { class = "com\\.jkrebs\\.yazi" }, center = true })

-- satty, opened by scripts/clip-preview (SUPER+CTRL+V) to crop/annotate the
-- clipboard image.
hl.window_rule({ name = "satty-float",  match = { class = "com\\.jkrebs\\.satty" }, float  = true })
hl.window_rule({ name = "satty-size",   match = { class = "com\\.jkrebs\\.satty" }, size   = "1600 900" })
hl.window_rule({ name = "satty-center", match = { class = "com\\.jkrebs\\.satty" }, center = true })

-- Waydroid, plain or nested in cage-xtmapper (~/.local/bin/waydroid-keymapper,
-- whose window reports class "wlroots"). Android fixes its resolution to the
-- window size at session start, so float both at a set size rather than let
-- tiling resize them afterwards and strand Android in a corner.
for _, m in ipairs({ { "waydroid", { class = "[Ww]aydroid.*" } }, { "cage-xtmapper", { class = "wlroots" } } }) do
    hl.window_rule({ name = m[1] .. "-float",  match = m[2], float  = true })
    hl.window_rule({ name = m[1] .. "-size",   match = m[2], size   = "1600 900" })
    hl.window_rule({ name = m[1] .. "-center", match = m[2], center = true })
end

------------------------------
---- WORKSPACE ASSIGNMENTS ----
------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

local workspace_configs = {
    optimus = {
		-- Left (resolved connector, see the MONITORS block)
        { workspace = "1",  monitor = side.LEFT },
        { workspace = "4",  monitor = side.LEFT },

		-- Middle
        { workspace = "2",  monitor = "desc:Acer Technologies XB273 GX 0x15205CF0" },
        { workspace = "5",  monitor = "desc:Acer Technologies XB273 GX 0x15205CF0" },

		-- Right (resolved connector, see the MONITORS block)
        { workspace = "3",  monitor = side.RIGHT },
        { workspace = "6",  monitor = side.RIGHT },

		-- Bottom
        { workspace = "7",  monitor = "desc:Acer Technologies PM161Q C 25230110E4HA1" },
    },
}

if workspace_configs[hostname] then
    for _, config in ipairs(workspace_configs[hostname]) do
        -- side.LEFT/RIGHT are nil on a first-ever boot; side-monitors applies
        -- those two pairs itself once it has resolved them.
        if config.monitor then hl.workspace_rule(config) end
    end
end


-----------------------
---- KEYBINDINGS ----
-----------------------

-- See https://wiki.hypr.land/Configuring/Basics/Binds/
local mainMod = "SUPER"

-- Screenshots
hl.bind("Home",             hl.dsp.exec_cmd("/home/jkrebs/dotfiles/scripts/screenshot-region -o /home/jkrebs/Pictures"), { description = "Screenshot a region to ~/Pictures" })
hl.bind(mainMod .. " + Home", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/scripts/screenshot-region --clipboard-only"), { description = "Screenshot a region to the clipboard" })

-- SUPER+SHIFT+Home, then a workspace key, screenshots that workspace's whole
-- monitor to the clipboard. Uses the same keys as the workspace/special binds
-- below so it covers workspaces 1-10 and the special workspaces too.
local function screenshot_workspace_clipboard(workspace)
    local function shoot()
        local ws = hl.get_workspace(workspace)
        if not ws or not ws.monitor then
            hl.notification.create({ text = "Workspace '" .. tostring(workspace) .. "' doesn't exist", timeout = 3000 })
            return
        end

        local monitor_name = ws.monitor.name
        local hyprshot = "hyprshot -m output -m " .. monitor_name .. " --clipboard-only"

        if ws.visible then
            hl.exec_cmd(hyprshot)
            return
        end

        -- Workspace isn't currently shown on any monitor. Briefly switch its
        -- home monitor to it, screenshot, then switch back to what was there.
        -- The switch back runs from the shell after hyprshot, so it goes through
        -- `hyprctl dispatch`, which takes Lua dispatcher expressions.
        local special = type(workspace) == "string" and workspace:match("^special:(.+)$")
        local focused = hl.get_active_monitor()
        local previous = ws.monitor.active_workspace

        hl.dispatch(hl.dsp.focus({ monitor = monitor_name }))
        local restore = {}
        if special then
            hl.dispatch(hl.dsp.workspace.toggle_special(special))
            table.insert(restore, 'hl.dsp.workspace.toggle_special("' .. special .. '")')
        else
            hl.dispatch(hl.dsp.focus({ workspace = workspace }))
            if previous then
                table.insert(restore, "hl.dsp.focus({ workspace = " .. tostring(previous.id) .. " })")
            end
        end
        if focused and focused.name ~= monitor_name then
            table.insert(restore, 'hl.dsp.focus({ monitor = "' .. focused.name .. '" })')
        end

        local cmd = "sleep 0.15; " .. hyprshot
        for _, d in ipairs(restore) do
            cmd = cmd .. "; hyprctl dispatch '" .. d .. "'"
        end
        hl.exec_cmd(cmd)
    end

    return function()
        -- Always leave the submap, even if shoot() errors: a submap left
        -- active swallows every normal bind (SUPER+SHIFT+Home then just types
        -- "1;10H" into the terminal).
        local ok, err = pcall(shoot)
        hl.dispatch(hl.dsp.submap(""))
        if not ok then
            hl.notification.create({ text = "Screenshot failed: " .. tostring(err), timeout = 5000 })
        end
    end
end

hl.define_submap("screenshot-workspace", function()
    for i = 1, 10 do
        local key = i % 10
        hl.bind(tostring(key), screenshot_workspace_clipboard(i))
    end
    hl.bind("semicolon", screenshot_workspace_clipboard("special:logs"))
    hl.bind("period",    screenshot_workspace_clipboard("special:slack"))
    hl.bind("comma",     screenshot_workspace_clipboard("special:btop"))
    hl.bind("Escape", hl.dsp.submap(""))
    -- Any other key cancels, rather than leaving the submap stuck on
    hl.bind("catchall", hl.dsp.submap(""))
end)

hl.bind(mainMod .. " + SHIFT + Home", hl.dsp.submap("screenshot-workspace"), { description = "Screenshot a whole workspace to the clipboard (then press its key)" })

-- Apps
hl.bind(mainMod .. " + T",     hl.dsp.exec_cmd(terminal), { description = "Terminal (Ghostty)" })
hl.bind(mainMod .. " + Q",     hl.dsp.window.close())
hl.bind(mainMod .. " + E",         hl.dsp.exec_cmd(fileManager), { description = "File manager (Yazi)" })
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(dolphin), { description = "File manager (Dolphin, for sftp:// and smb://)" })
hl.bind(mainMod .. " + V",     hl.dsp.global("quickshell:clipboard"))
hl.bind(mainMod .. " + CTRL + V", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/scripts/clip-preview"), { description = "Crop/annotate the image on the clipboard (satty)" })
hl.bind(mainMod .. " + space", hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("pgadmin4"), { description = "pgAdmin" })
hl.bind(mainMod .. " + B",     hl.dsp.exec_cmd(browser), { description = "Browser (Brave, profile picker)" })
hl.bind(mainMod .. " + S",     hl.dsp.exec_cmd(slack), { description = "Slack" })
-- uwsm stop shuts the session down in order; hl.dsp.exit() pulls the
-- compositor out from under its clients and forces an unclean shutdown.
hl.bind(mainMod .. " + CTRL + Q", hl.dsp.exec_cmd("uwsm stop"))

-- Shell panels (quickshell)
hl.bind(mainMod .. " + D",         hl.dsp.global("quickshell:launcher"))
hl.bind(mainMod .. " + N",         hl.dsp.global("quickshell:notifications"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("quickshell:dismissNotifications"))
hl.bind(mainMod .. " + C",         hl.dsp.global("quickshell:control"))
hl.bind(mainMod .. " + slash",     hl.dsp.global("quickshell:cheatsheet"))
hl.bind(mainMod .. " + Escape",    hl.dsp.global("quickshell:power"))
hl.bind(mainMod .. " + W",         hl.dsp.global("quickshell:wallpapers"))
hl.bind(mainMod .. " + A",         hl.dsp.global("quickshell:jev"), { description = "artoo prompt (do or ask anything)" })
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.global("quickshell:jevHistory"), { description = "artoo conversations (inputs, answers, steps, cost)" })
hl.bind(mainMod .. " + Y",         hl.dsp.global("quickshell:homeassistant"))


-- Audio keybinds
-- Switch to the sink; if it's already the active sink, toggle mute instead.
hl.bind(mainMod .. " + CTRL + 1", hl.dsp.exec_cmd("~/dotfiles/hypr/scripts/sink-select-or-mute.sh alsa_output.usb-Razer_Razer_Nari_Essential-00.analog-stereo"), { description = "Audio to Razer headset (again: mute)" }) -- Razer headset
hl.bind(mainMod .. " + CTRL + 3", hl.dsp.exec_cmd("~/dotfiles/hypr/scripts/sink-select-or-mute.sh alsa_output.usb-Generic_USB_Audio_20210726905926-00.analog-stereo"), { description = "Audio to USB audio device (again: mute)" })
hl.bind(mainMod .. " + CTRL + 4", hl.dsp.exec_cmd("~/dotfiles/hypr/scripts/sink-select-or-mute.sh alsa_output.usb-ACTIONS_Pebble_V3-00.analog-stereo"), { description = "Audio to Pebble speakers (again: mute)" }) -- Pebble
hl.bind(mainMod .. " + CTRL + 5", hl.dsp.exec_cmd("~/dotfiles/hypr/scripts/sink-select-or-mute.sh bluez_output.04_C8_B0_2F_27_CD.1"), { description = "Audio to Pixel earbuds, connecting first (again: mute)" }) -- Pixel earbuds


-- Focus with vim keys
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left"  }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "up"    }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "down"  }))

-- Resize with vim keys
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.resize({ x = -100, y = 0,    relative = true }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.resize({ x = 100,  y = 0,    relative = true }))
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.resize({ x = 0,    y = 100,  relative = true }))
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.resize({ x = 0,    y = -100, relative = true }))

-- Maximize (fills the work area, keeps gaps and the bar)
hl.bind(mainMod .. " + f", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- Fullscreen "in place": the app thinks it is fullscreen (a browser video hides its page
-- chrome and fills the window) while Hyprland keeps the window in its tile.
hl.bind(mainMod .. " + SHIFT + f", function()
    local w = hl.get_active_window()
    if not w then return end
    local on = w.fullscreen_client == 2
    hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = on and 0 or 2 }))
end, { description = "Fullscreen inside the tile (client only)" })

-- Workspaces 1-10
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Toggle the physical monitor that a workspace key lives on off/on (DPMS),
-- so e.g. SUPER+ALT+3 blanks whichever monitor SUPER+3 would switch to.
local function toggle_monitor_dpms(workspace)
    return function ()
        local ws = hl.get_workspace(workspace)
        if not ws or not ws.monitor then
            hl.notification.create({ text = "Workspace '" .. tostring(workspace) .. "' doesn't exist", timeout = 3000 })
            return
        end

        -- Deferred: the wiki warns dispatching DPMS straight from a bind is
        -- undefined behaviour.
        local name = ws.monitor.name
        hl.timer(function()
            hl.dispatch(hl.dsp.dpms({ action = "toggle", monitor = name }))
        end, { timeout = 500, type = "oneshot" })
    end
end

for _, key in ipairs({ 1, 2, 3, 7 }) do
    hl.bind(mainMod .. " + ALT + " .. key, toggle_monitor_dpms(key))
end

-- Special workspaces
hl.bind(mainMod .. " + semicolon",        hl.dsp.workspace.toggle_special("logs"))
hl.bind(mainMod .. " + apostrophe",       hl.dsp.exec_cmd("/home/jkrebs/dotfiles/quickshell/scripts/media-scratchpad"), { description = "Toggle media scratchpad (YouTube Music)" })
hl.bind(mainMod .. " + period",           hl.dsp.workspace.toggle_special("slack"))
hl.bind(mainMod .. " + comma",         hl.dsp.workspace.toggle_special("btop"))

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Lock
hl.bind(mainMod .. " + End", hl.dsp.exec_cmd("hyprlock"), { description = "Lock screen" })

-- Dictation: press Insert to copy the most recent transcription to the clipboard
hl.bind("Insert", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/ptt-dictate/ptt_dictate.sh copy-last"), { description = "Copy last dictation to clipboard" })
-- Dictation: press Delete to start recording, press again to transcribe + type
hl.bind("Delete", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/ptt-dictate/ptt_dictate.sh toggle"), { description = "Dictate: press to start, again to type it" })
-- Dictation: SUPER+Insert opens the dictation history panel
hl.bind(mainMod .. " + Insert", hl.dsp.global("quickshell:dictationHistory"), { description = "Dictation history" })
-- Dictation: hold End, say a word, release, type its correct spelling to teach it
hl.bind("End", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/ptt-dictate/ptt_dictate.sh teach-start"), { description = "Teach dictation a word (hold, say it, release)" })
hl.bind("End", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/ptt-dictate/ptt_dictate.sh stop"), { release = true })

-- Monitors
hl.bind(mainMod .. " + CTRL + N", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/night-mode toggle"), { description = "Toggle night mode (reduce blue light on all monitors)" })

-- Swap the Left / Right monitor rules (the KVM can swap which of the two
-- identical Sceptres sits behind the EDID-reporting adapter)
hl.bind(mainMod .. " + CTRL + M", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/swap-monitors"), { description = "Swap left/right side monitors" })

-- Dwindle split control: flip the focused pair side-by-side <-> stacked, or swap its halves
hl.bind(mainMod .. " + CTRL + j", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })
hl.bind(mainMod .. " + CTRL + k", hl.dsp.layout("swapsplit"),   { description = "Swap split halves" })

-- Mouse move/resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/volume_change.sh 5 up"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("/home/jkrebs/dotfiles/hypr/scripts/volume_change.sh 5 down"), { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true, description = "Mute audio" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true, description = "Mute microphone" })

hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })
hl.bind("XF86AudioStop",  hl.dsp.exec_cmd("playerctl stop"),       { locked = true, description = "Stop playback" })

-- Screen brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e set +5%"), { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e set 5%-"), { locked = true, repeating = true, description = "Brightness down" })

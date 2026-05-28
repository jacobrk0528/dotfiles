-- Hyprland Lua configuration
-- See https://wiki.hypr.land/Configuring/Start/


--------------------
---- ENV VARS ----
--------------------

-- NVIDIA specific
hl.env("LIBVA_DRIVER_NAME",        "nvidia")
hl.env("XDG_SESSION_TYPE",         "wayland")
hl.env("GBM_BACKEND",              "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME","nvidia")

hl.env("XCURSOR_SIZE",   "24")
hl.env("HYPRCURSOR_SIZE","24")
hl.env("TZ",             "America/New_York")
hl.env("LANG",           "en_US.UTF-8")
hl.env("LC_ALL",         "en_US.UTF-8")


--------------------
---- MONITORS ----
--------------------

local hostname = io.popen("cat /etc/hostname"):read("*l")

local monitor_configs = {
    terra = function()
        hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1 }) -- bottom
    end,
    desktop = function()
        hl.monitor({ output = "DP-1", mode = "1920x1080@100", position = "1920x330",  scale = 1 }) -- right
        hl.monitor({ output = "DP-2", mode = "1920x1080@100", position = "0x0",       scale = 1 }) -- middle
        hl.monitor({ output = "DP-3", mode = "1920x1080@60",  position = "-1920x530", scale = 1 }) -- left
        hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x1080", scale = 1 }) -- bottom
    end,
}

if monitor_configs[hostname] then
    monitor_configs[hostname]()
end


-----------------------
---- MY PROGRAMS ----
-----------------------

local terminal    = "ghostty"
local fileManager = "thunar"
local menu        = "wofi --show drun --style ~/.config/wofi/style.css"
local browser     = "google-chrome-stable"
local slack       = "slack"
local btop        = "ghostty --title=btop -e bash -c 'btop'"


--------------------
---- AUTOSTART ----
--------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/launch_logs.sh")
    hl.exec_cmd(slack,                { workspace = "special:slack" })
	hl.exec_cmd(btop,                 { workspace = "special:btop" })
    hl.exec_cmd(terminal,             { workspace = "2" })
    hl.exec_cmd("sleep 2 && " .. browser, { workspace = "3" })
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("wl-clip-persist --clipboard regular")
end)


---------------------------
---- LOOK AND FEEL ----
---------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    cursor = {
        no_hardware_cursors = true,
    },

    general = {
        gaps_in  = 6,
        gaps_out = 12,

        border_size = 1,

        col = {
            active_border   = "rgba(ffffff28)",
            inactive_border = "rgba(ffffff28)",
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
            color        = 0x00000066,
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
        kb_options = "ctrl:nocaps",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = -0.4,

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

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })


---------------------------
---- LAYER RULES ----
---------------------------

-- make Waybar pretty
hl.layer_rule({ match = { namespace = "waybar" }, blur = true })

-- log windows go to special:logs
hl.window_rule({ match = { title = "bc_utils_log" }, workspace = "special:logs" })
hl.window_rule({ match = { title = "narsil_log"   }, workspace = "special:logs" })


------------------------------
---- WORKSPACE ASSIGNMENTS ----
------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

local workspace_configs = {
    desktop = {
        { workspace = "1",  monitor = "DP-3"    },
        { workspace = "2",  monitor = "DP-2"    },
        { workspace = "3",  monitor = "DP-1"    },
        { workspace = "4",  monitor = "DP-3"    },
        { workspace = "5",  monitor = "DP-2"    },
        { workspace = "6",  monitor = "DP-1"    },
        { workspace = "7",  monitor = "HDMI-A-1"},
    },
}

if workspace_configs[hostname] then
    for _, config in ipairs(workspace_configs[hostname]) do
        hl.workspace_rule(config)
    end
end


-----------------------
---- KEYBINDINGS ----
-----------------------

-- See https://wiki.hypr.land/Configuring/Basics/Binds/
local mainMod = "SUPER"

-- Screenshots
hl.bind("Home",             hl.dsp.exec_cmd("hyprshot -m region -s -o /home/jkrebs/Pictures"))
hl.bind(mainMod .. " + Home", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))

-- Apps
hl.bind(mainMod .. " + T",     hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q",     hl.dsp.window.close())
hl.bind(mainMod .. " + E",     hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V",     hl.dsp.exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("pgadmin4"))
hl.bind(mainMod .. " + B",     hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + S",     hl.dsp.exec_cmd(slack))
hl.bind(mainMod .. " + CTRL + Q", hl.dsp.exit())

-- Focus with vim keys
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left"  }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "up"    }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "down"  }))

-- Resize with vim keys
hl.bind(mainMod .. " + SHIFT + h", function () hl.dsp.window.resize_active({ x = -100, y = 0   }) end)
hl.bind(mainMod .. " + SHIFT + l", function () hl.dsp.window.resize_active({ x = 100,  y = 0   }) end)
hl.bind(mainMod .. " + SHIFT + j", function () hl.dsp.window.resize_active({ x = 0,    y = 100 }) end)
hl.bind(mainMod .. " + SHIFT + k", function () hl.dsp.window.resize_active({ x = 0,    y = -100}) end)

-- Fullscreen
hl.bind(mainMod .. " + f", hl.dsp.window.fullscreen(1))

-- Workspaces 1-10
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Special workspaces
hl.bind(mainMod .. " + semicolon",        hl.dsp.workspace.toggle_special("logs"))
hl.bind(mainMod .. " + apostrophe",       hl.dsp.workspace.toggle_special("media"))
hl.bind(mainMod .. " + period",           hl.dsp.workspace.toggle_special("slack"))
hl.bind(mainMod .. " + comma",         hl.dsp.workspace.toggle_special("btop"))

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Lock
hl.bind(mainMod .. " + End", hl.dsp.exec_cmd("hyprlock"))

-- Mouse move/resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })

-- Screen brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e set +5%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e set 5%-"), { locked = true, repeating = true })

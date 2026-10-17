-- Installed to /etc/greetd/hyprland.lua — the throwaway compositor the greeter
-- draws in. Nothing here is shared with hypr/hyprland.lua; the greeter must keep
-- working even if the real config is broken.
--
-- Monitors are left to Hyprland's defaults (preferred mode, auto position and
-- scale), which is all the old `monitor = , preferred, auto, 1` asked for.

hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("XCURSOR_SIZE", "24")

hl.config({
    general = {
        border_size = 0,
        gaps_in     = 0,
        gaps_out    = 0,
    },

    decoration = {
        blur = { enabled = false },
    },

    animations = { enabled = false },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        disable_autoreload       = true,
        -- Launched as plain `Hyprland` by greeter-session, not via
        -- start-hyprland, which is meant for a user session.
        disable_watchdog_warning = true,
    },

    input = {
        kb_layout          = "us",
        numlock_by_default = true,
        follow_mouse       = 1,
    },
})

-- Quickshell exits after Greetd.launch(..., quit: true); dispatching exit then
-- tears down this compositor so greetd can hand the VT to the real session.
hl.on("hyprland.start", function()
    hl.exec_cmd([[/usr/bin/qs -p /etc/greetd/quickshell-greeter; hyprctl dispatch 'hl.dsp.exit()']])
end)

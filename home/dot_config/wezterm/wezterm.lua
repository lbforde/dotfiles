-- ============================================================
--  WezTerm Configuration
--  ~/.config/wezterm/wezterm.lua
-- ============================================================

local wezterm  = require "wezterm"
local act      = wezterm.action
local config   = wezterm.config_builder()

-- ─── Font ──────────────────────────────────────────────────

config.font = wezterm.font_with_fallback {
    { family = "JetBrainsMono Nerd Font", weight = "Medium" },
    { family = "JetBrains Mono",          weight = "Medium" },
    "Noto Color Emoji",
}
config.font_size           = 13.0
config.line_height         = 1.15
config.cell_width          = 1.0
config.freetype_load_flags = "DEFAULT"
config.freetype_render_target = "HorizontalLcd"

-- ─── Shell ─────────────────────────────────────────────────

config.default_prog = { "pwsh", "-NoLogo" }

-- ─── Color Scheme (One Dark Pro Darker) ───────────────────
--  Derived from the "One theme for all" VS Code theme.
--  Palette reference:
--    bg         #1f2126    fg         #abb2bf
--    bg_dark    #15171a    comment    #7f848e
--    red        #e06c75    green      #98c379
--    yellow     #e5c07b    blue       #61afef
--    magenta    #c678dd    cyan       #56b6c2
--    orange     #d19a66    accent     #058fff

config.colors = {
    -- Basic palette
    foreground    = "#abb2bf",
    background    = "#1f2126",

    cursor_bg     = "#61afef",   -- blue cursor, easy to spot
    cursor_border = "#61afef",
    cursor_fg     = "#1f2126",

    selection_bg  = "#3e4451",
    selection_fg  = "#abb2bf",

    -- ANSI colours
    ansi = {
        "#3f4451",   -- black   (0)
        "#e06c75",   -- red     (1)
        "#98c379",   -- green   (2)
        "#e5c07b",   -- yellow  (3)
        "#61afef",   -- blue    (4)
        "#c678dd",   -- magenta (5)
        "#56b6c2",   -- cyan    (6)
        "#abb2bf",   -- white   (7)
    },
    brights = {
        "#7f848e",   -- bright black  / comment
        "#e06c75",   -- bright red
        "#98c379",   -- bright green
        "#d19a66",   -- bright yellow / orange
        "#058fff",   -- bright blue   / accent
        "#c678dd",   -- bright magenta
        "#56b6c2",   -- bright cyan
        "#ffffff",   -- bright white
    },

    tab_bar = {
        background = "#15171a",
        active_tab = {
            bg_color  = "#1f2126",
            fg_color  = "#abb2bf",
            intensity = "Bold",
        },
        inactive_tab = {
            bg_color = "#15171a",
            fg_color = "#5c6370",
        },
        inactive_tab_hover = {
            bg_color = "#25282e",
            fg_color = "#abb2bf",
        },
        new_tab = {
            bg_color = "#15171a",
            fg_color = "#5c6370",
        },
        new_tab_hover = {
            bg_color = "#25282e",
            fg_color = "#abb2bf",
        },
    },
}

-- ─── Window ────────────────────────────────────────────────

config.initial_cols         = 220
config.initial_rows         = 50
config.window_padding       = { left = 12, right = 12, top = 10, bottom = 10 }
config.window_decorations   = "RESIZE"           -- removes title bar, keeps resize border
config.window_background_opacity = 0.95
config.macos_window_background_blur = 20         -- no-op on Windows; kept for cross-compat
config.enable_scroll_bar    = false
config.scrollback_lines     = 10000

-- ─── Tab Bar ───────────────────────────────────────────────

config.enable_tab_bar               = true
config.use_fancy_tab_bar            = false
config.tab_bar_at_bottom            = false
config.show_tab_index_in_tab_bar    = true
config.tab_max_width                = 32
config.hide_tab_bar_if_only_one_tab = true

-- Retitle tab to show CWD basename
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
    local title = tab.active_pane.title
    -- Trim long paths to just the last segment
    local cwd = tab.active_pane.current_working_dir
    if cwd then
        local path = cwd.file_path or cwd.path or ""
        local short = path:match("([^/\\]+)[/\\]?$") or path
        title = (tab.tab_index + 1) .. ": " .. short
    end
    return wezterm.truncate_right(title, max_width)
end)

-- ─── Keys ──────────────────────────────────────────────────

config.disable_default_key_bindings = false
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1200 }

config.keys = {
    -- Pane splits
    { key = "|",  mods = "LEADER|SHIFT", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
    { key = "-",  mods = "LEADER",       action = act.SplitVertical   { domain = "CurrentPaneDomain" } },

    -- Pane navigation (Vim-style)
    { key = "h",  mods = "LEADER", action = act.ActivatePaneDirection "Left"  },
    { key = "l",  mods = "LEADER", action = act.ActivatePaneDirection "Right" },
    { key = "k",  mods = "LEADER", action = act.ActivatePaneDirection "Up"    },
    { key = "j",  mods = "LEADER", action = act.ActivatePaneDirection "Down"  },

    -- Pane resize
    { key = "H",  mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Left",  5 } },
    { key = "L",  mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Right", 5 } },
    { key = "K",  mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Up",    5 } },
    { key = "J",  mods = "LEADER|SHIFT", action = act.AdjustPaneSize { "Down",  5 } },

    -- Pane zoom (toggle full-screen for current pane)
    { key = "z",  mods = "LEADER", action = act.TogglePaneZoomState },

    -- Close pane
    { key = "x",  mods = "LEADER", action = act.CloseCurrentPane { confirm = true } },

    -- Tabs
    { key = "c",  mods = "LEADER",   action = act.SpawnTab "CurrentPaneDomain"  },
    { key = "n",  mods = "LEADER",   action = act.ActivateTabRelative(1)         },
    { key = "p",  mods = "LEADER",   action = act.ActivateTabRelative(-1)        },
    { key = "1",  mods = "LEADER",   action = act.ActivateTab(0) },
    { key = "2",  mods = "LEADER",   action = act.ActivateTab(1) },
    { key = "3",  mods = "LEADER",   action = act.ActivateTab(2) },
    { key = "4",  mods = "LEADER",   action = act.ActivateTab(3) },
    { key = "5",  mods = "LEADER",   action = act.ActivateTab(4) },

    -- Rename tab
    { key = ",", mods = "LEADER", action = act.PromptInputLine {
        description = "Rename tab:",
        action = wezterm.action_callback(function(window, pane, line)
            if line then window:active_tab():set_title(line) end
        end),
    }},

    -- Copy/paste
    { key = "c", mods = "CTRL|SHIFT", action = act.CopyTo "Clipboard" },
    { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom "Clipboard" },

    -- Font size
    { key = "=",  mods = "CTRL", action = act.IncreaseFontSize },
    { key = "-",  mods = "CTRL", action = act.DecreaseFontSize },
    { key = "0",  mods = "CTRL", action = act.ResetFontSize    },

    -- Reload config
    { key = "r", mods = "LEADER", action = act.ReloadConfiguration },

    -- Scrollback search
    { key = "f", mods = "LEADER", action = act.Search "CurrentSelectionOrEmptyString" },

    -- Activate copy mode (Vim-like)
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
}

-- Mouse
config.mouse_bindings = {
    -- Ctrl+click opens hyperlinks
    { event = { Up = { streak = 1, button = "Left" } },
      mods  = "CTRL",
      action = act.OpenLinkAtMouseCursor },
}

-- ─── Copy Mode Key Bindings (vi-like) ──────────────────────

config.key_tables = {
    copy_mode = {
        { key = "q",      mods = "NONE",  action = act.CopyMode "Close" },
        { key = "Escape", mods = "NONE",  action = act.CopyMode "Close" },
        { key = "h",      mods = "NONE",  action = act.CopyMode "MoveLeft"  },
        { key = "j",      mods = "NONE",  action = act.CopyMode "MoveDown"  },
        { key = "k",      mods = "NONE",  action = act.CopyMode "MoveUp"    },
        { key = "l",      mods = "NONE",  action = act.CopyMode "MoveRight" },
        { key = "v",      mods = "NONE",  action = act.CopyMode { SetSelectionMode = "Cell" } },
        { key = "V",      mods = "SHIFT", action = act.CopyMode { SetSelectionMode = "Line" } },
        { key = "y",      mods = "NONE",  action = act.Multiple {
            act.CopyTo "ClipboardAndPrimarySelection",
            act.CopyMode "Close",
        }},
        { key = "0",  mods = "NONE", action = act.CopyMode "MoveToStartOfLine"    },
        { key = "$",  mods = "NONE", action = act.CopyMode "MoveToEndOfLineContent" },
        { key = "g",  mods = "NONE", action = act.CopyMode "MoveToScrollbackTop"  },
        { key = "G",  mods = "SHIFT",action = act.CopyMode "MoveToScrollbackBottom"},
    },
}

-- ─── Hyperlink Rules ───────────────────────────────────────

config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- Make issue / PR numbers in git log clickable (adjust org/repo)
table.insert(config.hyperlink_rules, {
    regex = [[\b(https://github\.com/[^\s]+)\b]],
    format = "$1",
})

-- ─── Performance ───────────────────────────────────────────

config.front_end         = "WebGpu"   -- better GPU acceleration on Windows
config.max_fps           = 120
config.animation_fps     = 60
config.prefer_egl        = true

-- ─── Misc ──────────────────────────────────────────────────

config.audible_bell          = "Disabled"
config.visual_bell           = { fade_in_duration_ms = 75, fade_out_duration_ms = 75 }
config.check_for_updates     = false   -- manage updates via Scoop
config.automatically_reload_config = true

return config

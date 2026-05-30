local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

-- Appearance
config.color_scheme = 'Tokyo Night'
config.font = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
config.font_size = 13.0
config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }
config.window_decorations = 'RESIZE'
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

-- Performance
config.front_end = 'WebGpu'
config.animation_fps = 60
config.max_fps = 60

-- Scrollback
config.scrollback_lines = 10000

-- Clipboard — native Wayland
config.enable_wayland = true

-- Key bindings
config.keys = {
  -- Splits
  { key = '|', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'CTRL|SHIFT', action = act.SplitVertical   { domain = 'CurrentPaneDomain' } },
  -- Pane navigation
  { key = 'h', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left'  },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up'    },
  { key = 'j', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down'  },
  -- Pane resize
  { key = 'H', mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Left',  5 } },
  { key = 'L', mods = 'CTRL|SHIFT|ALT', action = act.AdjustPaneSize { 'Right', 5 } },
  -- Tabs
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = false } },
  -- Copy/paste
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  -- Search
  { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },
}

-- Mouse: copy on select, no need to press anything
config.mouse_bindings = {
  {
    event  = { Up = { streak = 1, button = 'Left' } },
    mods   = 'NONE',
    action = act.CompleteSelection 'ClipboardAndPrimarySelection',
  },
  {
    event  = { Up = { streak = 2, button = 'Left' } },
    mods   = 'NONE',
    action = act.CompleteSelectionOrOpenLinkAtMouseCursor 'ClipboardAndPrimarySelection',
  },
}

-- Dev layout: auto-open on gui-startup
-- Triggered when wezterm starts fresh (not when opening a new window)
local PROJECT = os.getenv('PROJECT_PATH') or (os.getenv('HOME') .. '/speaklogic-testing')

wezterm.on('gui-startup', function(cmd)
  local tab, left_pane, window = wezterm.mux.spawn_window(cmd or {})

  -- Left pane: dev server
  left_pane:send_text('cd ' .. PROJECT .. ' && npm run dev-server\n')

  -- Right pane: claude
  local right_pane = left_pane:split {
    direction = 'Right',
    size = 0.5,
  }
  right_pane:send_text('cd ' .. PROJECT .. ' && claude\n')

  -- Focus left pane
  left_pane:activate()
  window:gui_window():maximize()
end)

return config

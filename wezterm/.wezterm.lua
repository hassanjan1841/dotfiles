local wezterm = require 'wezterm'
local act     = wezterm.action
local config  = wezterm.config_builder()

-- ── Appearance ────────────────────────────────────────────────────────────────
config.color_scheme               = 'Tokyo Night'
config.font                       = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
config.font_size                  = 13.0
config.window_padding             = { left = 8, right = 8, top = 6, bottom = 6 }
config.window_decorations         = 'RESIZE'
config.enable_tab_bar             = true
config.hide_tab_bar_if_only_one_tab = false   -- always show so workspace name is visible
config.use_fancy_tab_bar          = false
config.tab_bar_at_bottom          = true

-- ── Performance ───────────────────────────────────────────────────────────────
config.front_end            = 'WebGpu'
config.animation_fps        = 60
config.max_fps              = 60
config.status_update_interval = 2000   -- refresh status bar every 2 s

-- ── Scrollback ────────────────────────────────────────────────────────────────
config.scrollback_lines = 10000

-- ── Clipboard (native Wayland) ────────────────────────────────────────────────
config.enable_wayland = true

-- ── Helpers ───────────────────────────────────────────────────────────────────
local HOME = os.getenv('HOME') or ''

local function pane_cwd(pane)
  local uri = pane:get_current_working_dir()
  if not uri then return '' end
  local path = uri.file_path or tostring(uri):gsub('^file://', ''):gsub('%?.*', '')
  return path:gsub('^' .. HOME, '~')
end

local function git_branch(cwd)
  if cwd == '' then return '' end
  local real = cwd:gsub('^~', HOME)
  local ok, out = wezterm.run_child_process {
    'git', '-C', real, 'symbolic-ref', '--short', 'HEAD'
  }
  if ok and out ~= '' then return ' ' .. out:gsub('%s+$', '') end
  return ''
end

-- ── Status bar: workspace (left) │ git branch + time (right) ─────────────────
wezterm.on('update-status', function(window, pane)
  window:set_left_status(wezterm.format {
    { Foreground = { Color = '#7aa2f7' } },
    { Text = '  ' .. window:active_workspace() .. '  ' },
  })

  local branch = git_branch(pane_cwd(pane))
  local time   = wezterm.strftime '%H:%M'

  window:set_right_status(wezterm.format {
    { Foreground = { Color = '#7aa2f7' } },
    { Text = branch ~= '' and (branch .. '   ') or '' },
    { Foreground = { Color = '#565f89' } },
    { Text = time .. '  ' },
  })
end)

-- ── Dynamic tab titles: index + current directory ────────────────────────────
wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local pane    = tab.active_pane
  local cwd_uri = pane.current_working_dir
  local label

  if cwd_uri then
    local path = (cwd_uri.file_path or tostring(cwd_uri)):gsub('^' .. HOME, '~')
    label = path:match('([^/]+)/*$') or path   -- last path component
  else
    label = pane.title
  end

  return string.format(' %d: %s ', tab.tab_index + 1, label)
end)

-- ── Key bindings ──────────────────────────────────────────────────────────────
config.keys = {
  -- Splits
  { key = '|', mods = 'CTRL|SHIFT',     action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'CTRL|SHIFT',     action = act.SplitVertical   { domain = 'CurrentPaneDomain' } },

  -- Pane navigation (vim-style)
  { key = 'h', mods = 'CTRL|SHIFT',     action = act.ActivatePaneDirection 'Left'  },
  { key = 'l', mods = 'CTRL|SHIFT',     action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL|SHIFT',     action = act.ActivatePaneDirection 'Up'    },
  { key = 'j', mods = 'CTRL|SHIFT',     action = act.ActivatePaneDirection 'Down'  },

  -- Pane resize
  { key = 'H', mods = 'CTRL|ALT',       action = act.AdjustPaneSize { 'Left',  5 } },
  { key = 'L', mods = 'CTRL|ALT',       action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'K', mods = 'CTRL|ALT',       action = act.AdjustPaneSize { 'Up',    5 } },
  { key = 'J', mods = 'CTRL|ALT',       action = act.AdjustPaneSize { 'Down',  5 } },

  -- Zoom current pane (toggle fullscreen for one pane)
  { key = 'z', mods = 'CTRL|SHIFT',     action = act.TogglePaneZoomState },

  -- Tabs
  { key = 't', mods = 'CTRL|SHIFT',     action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT',     action = act.CloseCurrentPane { confirm = false } },
  { key = '1', mods = 'CTRL',           action = act.ActivateTab(0) },
  { key = '2', mods = 'CTRL',           action = act.ActivateTab(1) },
  { key = '3', mods = 'CTRL',           action = act.ActivateTab(2) },
  { key = '4', mods = 'CTRL',           action = act.ActivateTab(3) },
  { key = '5', mods = 'CTRL',           action = act.ActivateTab(4) },

  -- Copy / paste
  { key = 'c', mods = 'CTRL|SHIFT',     action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT',     action = act.PasteFrom 'Clipboard' },

  -- Search
  { key = 'f', mods = 'CTRL|SHIFT',     action = act.Search 'CurrentSelectionOrEmptyString' },

  -- Workspaces: cycle or pick from list
  { key = 'n', mods = 'CTRL|SHIFT',     action = act.SwitchWorkspaceRelative(1)  },
  { key = 'p', mods = 'CTRL|SHIFT',     action = act.SwitchWorkspaceRelative(-1) },
  { key = '$', mods = 'CTRL|SHIFT',     action = act.ShowLauncherArgs { flags = 'WORKSPACES' } },
}

-- ── Mouse: select → copy, right-click → paste ────────────────────────────────
config.mouse_bindings = {
  { event = { Up   = { streak = 1, button = 'Left'  } }, mods = 'NONE',
    action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
  { event = { Up   = { streak = 2, button = 'Left'  } }, mods = 'NONE',
    action = act.CompleteSelectionOrOpenLinkAtMouseCursor 'ClipboardAndPrimarySelection' },
  { event = { Down = { streak = 1, button = 'Right' } }, mods = 'NONE',
    action = act.PasteFrom 'Clipboard' },
}

-- ── Dev layout on startup ─────────────────────────────────────────────────────
local PROJECT = os.getenv('PROJECT_PATH') or (HOME .. '/speaklogic-testing')

wezterm.on('gui-startup', function(cmd)
  local args = cmd or {}
  args.workspace = 'dev'
  local tab, left_pane, window = wezterm.mux.spawn_window(args)

  left_pane:send_text('cd ' .. PROJECT .. ' && npm run dev-server\n')

  local right_pane = left_pane:split { direction = 'Right', size = 0.5 }
  right_pane:send_text('cd ' .. PROJECT .. ' && claude\n')

  left_pane:activate()
  window:gui_window():maximize()
end)

return config

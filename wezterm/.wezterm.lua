local wezterm = require 'wezterm'
local act     = wezterm.action
local config  = wezterm.config_builder()

-- ── Session persistence (resurrect.wezterm) ───────────────────────────────────
local resurrect = wezterm.plugin.require('https://github.com/MLFlexer/resurrect.wezterm')

local function do_save()
  local state = resurrect.workspace_state.get_workspace_state()
  resurrect.state_manager.save_state(state)
  wezterm.GLOBAL.last_save = wezterm.strftime '%H:%M:%S'

  -- remove stale saves that no longer match any live workspace name
  local base = resurrect.state_manager.save_state_dir
  if not base then return end
  local workspace_dir = base .. 'workspace/'
  local live = {}
  for _, name in ipairs(wezterm.mux.get_workspace_names()) do
    live[name .. '.json'] = true
  end
  for _, entry in ipairs(wezterm.read_dir(workspace_dir)) do
    local file = entry:match('([^/]+)$')
    if file and file:match('%.json$') and not live[file] then
      os.remove(workspace_dir .. file)
    end
  end
end

resurrect.state_manager.periodic_save({ interval_seconds = 60 })

-- ── Appearance ────────────────────────────────────────────────────────────────
config.color_scheme               = 'Tokyo Night'
config.font                       = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
config.font_size                  = 13.0
config.window_padding             = { left = 8, right = 8, top = 6, bottom = 6 }
config.window_decorations         = 'RESIZE'
config.enable_tab_bar             = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar          = false
config.tab_bar_at_bottom          = true

-- ── Performance ───────────────────────────────────────────────────────────────
config.front_end              = 'WebGpu'
config.animation_fps          = 60
config.max_fps                = 60
config.status_update_interval = 2000

-- ── Scrollback / Wayland ──────────────────────────────────────────────────────
config.scrollback_lines = 10000
config.enable_wayland   = true

-- ── Dim inactive panes ────────────────────────────────────────────────────────
config.inactive_pane_hsb = { saturation = 0.7, brightness = 0.6 }

-- ── Bell → desktop toast ──────────────────────────────────────────────────────
config.audible_bell = 'Disabled'

wezterm.on('bell', function(window, pane)
  window:toast_notification(
    'WezTerm — ' .. window:active_workspace(),
    '✓ Done: ' .. (pane:get_title() or ''),
    nil, 4000
  )
end)

-- ── Quick Select patterns ─────────────────────────────────────────────────────
config.quick_select_patterns = {
  '[0-9a-f]{7,40}',
  '[\\w./:-]+:\\d+:\\d*',
  '\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(?::\\d+)?',
}

-- ── Hyperlink rules: file:line → open in Zed ─────────────────────────────────
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  regex   = [[[.\w/~-]+\.\w+:\d+(?::\d+)?]],
  format  = 'fileref://$0',
})

wezterm.on('open-uri', function(window, pane, uri)
  local path, line = uri:match('^fileref://(.+):(%d+)')
  if path then
    -- Expand ~ to home
    path = path:gsub('^~', os.getenv('HOME') or '')
    wezterm.run_child_process { 'zed', path .. ':' .. line }
    return false  -- prevent default handler
  end
end)

-- ── SSH domains — add your servers here ──────────────────────────────────────
config.ssh_domains = {
  -- { name = 'myserver', remote_address = 'user@hostname' },
}

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

  local branch    = git_branch(pane_cwd(pane))
  local time      = wezterm.strftime '%H:%M'
  local last_save = wezterm.GLOBAL.last_save
  local save_info = last_save and ('  saved ' .. last_save .. '  ') or ''

  window:set_right_status(wezterm.format {
    { Foreground = { Color = '#41a6b5' } },
    { Text = save_info },
    { Foreground = { Color = '#7aa2f7' } },
    { Text = branch ~= '' and (branch .. '   ') or '' },
    { Foreground = { Color = '#565f89' } },
    { Text = time .. '  ' },
  })
end)

-- ── Tab titles: active tab highlighted in blue, inactive dimmed ──────────────
wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local pane    = tab.active_pane
  local cwd_uri = pane.current_working_dir
  local label

  if cwd_uri then
    local path = (cwd_uri.file_path or tostring(cwd_uri)):gsub('^' .. HOME, '~')
    label = path:match('([^/]+)/*$') or path
  else
    label = pane.title
  end

  local exit_ok = (pane.user_vars.LAST_EXIT or '0') == '0'

  if tab.is_active then
    local fg = exit_ok and '#c0caf5' or '#f7768e'
    return {
      { Background = { Color = '#1e2952' } },
      { Foreground = { Color = fg } },
      { Attribute  = { Intensity = 'Bold' } },
      { Text = string.format(' %d: %s ', tab.tab_index + 1, label) },
      { Attribute  = { Intensity = 'Normal' } },
    }
  else
    local fg = exit_ok and '#565f89' or '#f7768e'
    return {
      { Foreground = { Color = fg } },
      { Text = string.format(' %d: %s ', tab.tab_index + 1, label) },
    }
  end
end)

-- ── Key tables: resize mode (Ctrl+Shift+R → hjkl to resize → Esc to exit) ────
config.key_tables = {
  resize_pane = {
    { key = 'LeftArrow',  action = act.AdjustPaneSize { 'Left',  3 } },
    { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 3 } },
    { key = 'UpArrow',    action = act.AdjustPaneSize { 'Up',    3 } },
    { key = 'DownArrow',  action = act.AdjustPaneSize { 'Down',  3 } },
    { key = 'Escape',     action = act.PopKeyTable },
    { key = 'Enter',      action = act.PopKeyTable },
  },
}

-- ── Key bindings ──────────────────────────────────────────────────────────────
config.keys = {
  -- Splits
  { key = '|', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'CTRL|ALT',   action = act.SplitVertical   { domain = 'CurrentPaneDomain' } },

  -- Pane navigation
  { key = 'h', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left'  },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up'    },
  { key = 'j', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down'  },

  -- Resize mode: press Ctrl+Shift+R then hjkl freely, Esc to exit
  { key = 'r', mods = 'CTRL|SHIFT', action = act.ActivateKeyTable {
      name = 'resize_pane', one_shot = false, timeout_milliseconds = 5000,
  }},

  -- Zoom pane
  { key = 'z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },

  -- Tabs
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = false } },
  { key = '1', mods = 'CTRL',       action = act.ActivateTab(0) },
  { key = '2', mods = 'CTRL',       action = act.ActivateTab(1) },
  { key = '3', mods = 'CTRL',       action = act.ActivateTab(2) },
  { key = '4', mods = 'CTRL',       action = act.ActivateTab(3) },
  { key = '5', mods = 'CTRL',       action = act.ActivateTab(4) },

  -- Copy / paste
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },

  -- Search
  { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },

  -- Quick Select
  { key = 'Space', mods = 'CTRL|SHIFT', action = act.QuickSelect },

  -- Shell integration: jump between prompts
  { key = 'UpArrow',   mods = 'CTRL|SHIFT', action = act.ScrollToPrompt(-1) },
  { key = 'DownArrow', mods = 'CTRL|SHIFT', action = act.ScrollToPrompt(1)  },

  -- Rename tab (F2)
  { key = 'F2', mods = 'NONE', action = act.PromptInputLine {
      description = 'Rename tab:',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then window:active_tab():set_title(line) end
      end),
  }},

  -- Rename workspace (Shift+F2) — spaces auto-converted to hyphens
  { key = 'F2', mods = 'SHIFT', action = act.PromptInputLine {
      description = 'Rename workspace (spaces → hyphens):',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          wezterm.mux.rename_workspace(window:active_workspace(), line:gsub('%s+', '-'))
        end
      end),
  }},

  -- Workspaces
  { key = 'n', mods = 'CTRL|SHIFT', action = act.SwitchWorkspaceRelative(1)  },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.SwitchWorkspaceRelative(-1) },
  { key = '$', mods = 'CTRL|SHIFT', action = act.ShowLauncherArgs { flags = 'WORKSPACES' } },

  -- Close current workspace (closes all its tabs then switches to next workspace)
  { key = 'q', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
      local tabs = win:mux_window():tabs()
      for _, tab in ipairs(tabs) do
        tab:activate()
        win:perform_action(act.CloseCurrentTab { confirm = false }, pane)
      end
  end) },

  -- Quit WezTerm entirely
  { key = 'q', mods = 'CTRL|SHIFT|ALT', action = act.QuitApplication },

  -- Session save/restore (resurrect.wezterm)
  { key = 's', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
      do_save()
      win:toast_notification('WezTerm', 'Session saved ✓  ' .. (wezterm.GLOBAL.last_save or ''), nil, 2000)
  end) },
  { key = 'o', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
      resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
        local type = string.match(id, '^([^/]+)')
        id = string.match(id, '([^/]+)$')
        id = string.match(id, '(.+)%..+$') or id
        if type == 'workspace' then
          local state = resurrect.state_manager.load_state(id, 'workspace')
          local workspace_name = (state and state.workspace) or id
          resurrect.workspace_state.restore_workspace(state, {
            relative           = true,
            restore_text       = false,
            spawn_in_workspace = true,
            on_pane_restore    = resurrect.tab_state.default_on_pane_restore,
          })
          win:perform_action(act.SwitchToWorkspace { name = workspace_name }, pane)
        elseif type == 'window' then
          local state = resurrect.state_manager.load_state(id, 'window')
          resurrect.window_state.restore_window(pane:window(), state, {
            relative     = true,
            restore_text = false,
          })
        end
      end)
  end) },

  -- F1: show key bindings cheatsheet in a popup pane (press q to close)
  { key = 'F1', mods = 'NONE', action = act.SplitPane {
      direction = 'Right', size = { Percent = 35 },
      command = { args = { 'zsh', '-c', [[
printf "── WezTerm Shortcuts ────────────────\n"
printf "  Ctrl+Shift+|    split left/right\n"
printf "  Ctrl+Alt+-      split top/bottom\n"
printf "  Ctrl+Shift+h/l/k/j  navigate panes\n"
printf "  Ctrl+Shift+z    zoom pane\n"
printf "  Ctrl+Shift+r    resize mode\n"
printf "  Ctrl+Shift+t    new tab\n"
printf "  Ctrl+Shift+w    close pane\n"
printf "  Ctrl+1-5        switch tab\n"
printf "  Ctrl+Shift+n/p  next/prev workspace\n"
printf "  Ctrl+Shift+\$    workspace picker\n"
printf "  Ctrl+Shift+s    save session\n"
printf "  Ctrl+Shift+o    restore session\n"
printf "  Ctrl+Shift+q    close workspace\n"
printf "  Ctrl+Shift+Alt+q  quit WezTerm\n"
printf "  F2              rename tab\n"
printf "  Shift+F2        rename workspace\n"
printf "  Ctrl+Shift+Space  quick select\n"
printf "  Ctrl+Shift+f    search\n"
printf "  Ctrl+Shift+↑/↓  jump prompts\n"
printf "  Ctrl+Shift+c/v  copy/paste\n"
printf "────────────────────────────────────\n"
printf "  press q to close\n"
read -sk1
]] } },
  }},
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
local PROJECT = os.getenv('PROJECT_PATH') or (HOME .. '/projects/speaklogic-testing')

wezterm.on('gui-startup', function(cmd)
  local args = cmd or {}
  args.workspace = 'dev'
  local tab, left_pane, window = wezterm.mux.spawn_window(args)

  left_pane:send_text('cd ' .. PROJECT .. ' && npm run dev-server\n')

  local right_pane = left_pane:split { direction = 'Right', size = 0.5 }
  right_pane:send_text('cd ' .. PROJECT .. ' && claude\n')

  left_pane:activate()
  window:gui_window():maximize()

  -- Auto-restore saved workspaces (skips 'dev' since it's created above)
  local workspace_dir = resurrect.state_manager.save_state_dir .. 'workspace/'
  local ok, entries = pcall(wezterm.read_dir, workspace_dir)
  if ok then
    for _, entry in ipairs(entries) do
      local name = entry:match('([^/]+)%.json$')
      if name and name ~= 'dev' then
        local state = resurrect.state_manager.load_state(name, 'workspace')
        if state and state.workspace then
          resurrect.workspace_state.restore_workspace(state, {
            relative           = true,
            restore_text       = false,
            spawn_in_workspace = true,
            on_pane_restore    = resurrect.tab_state.default_on_pane_restore,
          })
        end
      end
    end
  end
end)

return config

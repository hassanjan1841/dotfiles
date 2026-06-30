local wezterm = require 'wezterm'
local act     = wezterm.action
local config  = wezterm.config_builder()

-- ── Session persistence (resurrect.wezterm) ───────────────────────────────────
local resurrect = wezterm.plugin.require('https://github.com/MLFlexer/resurrect.wezterm')

-- ── Zoxide-powered fuzzy workspace switcher (smart_workspace_switcher) ─────────
local workspace_switcher = wezterm.plugin.require('https://github.com/MLFlexer/smart_workspace_switcher.wezterm')

local function do_save()
  -- Snapshot EVERY workspace, not just the active one: group all live windows
  -- by their workspace and save each as its own state file.
  local by_ws = {}
  for _, win in ipairs(wezterm.mux.all_windows()) do
    local ws = win:get_workspace()
    if not by_ws[ws] then by_ws[ws] = { workspace = ws, window_states = {} } end
    table.insert(by_ws[ws].window_states, resurrect.window_state.get_window_state(win))
  end
  for _, state in pairs(by_ws) do
    resurrect.state_manager.save_state(state)
  end
  wezterm.GLOBAL.last_save = wezterm.strftime '%H:%M:%S'

  -- remove stale saves that no longer match any live workspace name
  local base = resurrect.state_manager.save_state_dir
  if not base then return end
  local workspace_dir = base .. 'workspace/'
  local live = {}
  for _, name in ipairs(wezterm.mux.get_workspace_names()) do
    live[name .. '.json'] = true
  end
  local ok, entries = pcall(wezterm.read_dir, workspace_dir)
  if not ok then return end
  for _, entry in ipairs(entries) do
    local file = entry:match('([^/]+)$')
    if file and file:match('%.json$') and not live[file] then
      os.remove(workspace_dir .. file)
    end
  end
end

-- Auto-save all workspaces every 10 seconds. Self-rescheduling timer; pcall keeps
-- the loop alive even if one save hiccups (an error here would otherwise stop it).
local SAVE_INTERVAL = 30
local function periodic_save_all()
  pcall(do_save)
  wezterm.time.call_after(SAVE_INTERVAL, periodic_save_all)
end
wezterm.time.call_after(SAVE_INTERVAL, periodic_save_all)

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
config.front_end              = 'WebGpu'  -- Metal backend on macOS (optimal on Apple Silicon)
config.animation_fps          = 120       -- match the 120Hz ProMotion panel
config.max_fps                = 120        -- was 60 = half the display's refresh
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

-- Full path to Zed's CLI so file:line links work even when `zed` isn't on PATH
local ZED_CLI = '/Applications/Zed.app/Contents/MacOS/cli'

wezterm.on('open-uri', function(window, pane, uri)
  local path, line = uri:match('^fileref://(.+):(%d+)')
  if path then
    -- Expand ~ to home
    path = path:gsub('^~', os.getenv('HOME') or '')
    wezterm.run_child_process { ZED_CLI, path .. ':' .. line }
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

-- Cache the branch per-cwd so we don't spawn `git` on every 2s status tick.
-- Re-checks at most every BRANCH_TTL seconds (catches checkouts quickly enough).
local branch_cache = {}
local BRANCH_TTL = 10
local function git_branch(cwd)
  if cwd == '' then return '' end
  local now = os.time()
  local cached = branch_cache[cwd]
  if cached and (now - cached.ts) < BRANCH_TTL then return cached.branch end
  local real = cwd:gsub('^~', HOME)
  local ok, out = wezterm.run_child_process {
    'git', '-C', real, 'symbolic-ref', '--short', 'HEAD'
  }
  local branch = (ok and out ~= '') and (' ' .. out:gsub('%s+$', '')) or ''
  branch_cache[cwd] = { branch = branch, ts = now }
  return branch
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

  -- PaneSelect: Alt+s overlays a letter on every pane → press it to jump
  { key = 's', mods = 'ALT', action = act.PaneSelect { alphabet = 'asdfghjkl' } },

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

  -- Workspaces (all on Alt for one consistent mental model)
  { key = '[', mods = 'ALT', action = act.SwitchWorkspaceRelative(-1) },  -- prev workspace
  { key = ']', mods = 'ALT', action = act.SwitchWorkspaceRelative(1)  },  -- next workspace
  -- Fuzzy workspace picker — one hand: Alt+w, type a name, Enter
  { key = 'w', mods = 'ALT', action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },
  -- Zoxide fuzzy switcher: Alt+j — jump to a workspace at any frecent directory
  { key = 'j', mods = 'ALT', action = workspace_switcher.switch_workspace() },

  -- Direct numbered jumps: Alt + 1-9 (one modifier, no leader). Ctrl+num = tabs,
  -- Alt+num = workspaces. Creates the workspace if missing. Edit names to remap.
  { key = '1', mods = 'ALT', action = act.SwitchToWorkspace { name = 'dev' } },
  { key = '2', mods = 'ALT', action = act.SwitchToWorkspace { name = 'crm-whatsapp' } },
  { key = '3', mods = 'ALT', action = act.SwitchToWorkspace { name = 'propfix' } },
  { key = '4', mods = 'ALT', action = act.SwitchToWorkspace { name = 'gcs-work-' } },
  { key = '5', mods = 'ALT', action = act.SwitchToWorkspace { name = 'feature-tracker-' } },
  { key = '6', mods = 'ALT', action = act.SwitchToWorkspace { name = 'all-rounder' } },
  { key = '7', mods = 'ALT', action = act.SwitchToWorkspace { name = 'afri-in-vset-hub-' } },
  { key = '8', mods = 'ALT', action = act.SwitchToWorkspace { name = 'drawio-work' } },
  { key = '9', mods = 'ALT', action = act.SwitchToWorkspace { name = 'auto-market-autraloa-' } },

  -- Command palette: search every WezTerm action (restored — the old
  -- Ctrl+Shift+P workspace-prev binding used to clobber this default).
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },

  -- Focus mode: toggle a translucent + blurred background on/off
  { key = 'b', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, pane)
      local o = win:effective_config().window_background_opacity
      if o and o < 1.0 then
        win:set_config_overrides { window_background_opacity = 1.0, macos_window_background_blur = 0 }
      else
        win:set_config_overrides { window_background_opacity = 0.85, macos_window_background_blur = 30 }
      end
  end) },

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
printf "  Alt+1-9         jump to workspace\n"
printf "  Alt+w           fuzzy workspace picker\n"
printf "  Alt+j           zoxide workspace switcher\n"
printf "  Alt+s           pick pane (overlay letters)\n"
printf "  Alt+[ / Alt+]   prev/next workspace\n"
printf "  Ctrl+Shift+p    command palette\n"
printf "  Ctrl+Shift+b    toggle blur/opacity\n"
printf "  Ctrl+Shift+x    copy mode (vim keys)\n"
printf "  Ctrl+Shift+u    emoji / char picker\n"
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
  -- Ctrl+Click opens hyperlinks in browser (lost when custom mouse_bindings
  -- replaced WezTerm's defaults — custom tables don't merge with defaults)
  { event = { Up   = { streak = 1, button = 'Left'  } }, mods = 'CTRL',
    action = act.OpenLinkAtMouseCursor },
}

-- ── Startup: restore saved workspaces if they exist, otherwise a plain window ──
wezterm.on('gui-startup', function(cmd)
  local workspace_dir = resurrect.state_manager.save_state_dir .. 'workspace/'
  local ok, entries = pcall(wezterm.read_dir, workspace_dir)

  local saved_names = {}
  if ok then
    for _, entry in ipairs(entries) do
      local name = entry:match('([^/]+)%.json$')
      if name then saved_names[#saved_names + 1] = name end
    end
  end

  if #saved_names > 0 then
    -- Restore all saved workspaces exactly as they were
    local first_window = nil
    for _, name in ipairs(saved_names) do
      local state = resurrect.state_manager.load_state(name, 'workspace')
      if state and state.workspace then
        resurrect.workspace_state.restore_workspace(state, {
          relative           = true,
          restore_text       = false,
          spawn_in_workspace = true,
          on_pane_restore    = resurrect.tab_state.default_on_pane_restore,
        })
        if not first_window then
          -- Switch the initial (blank) window to the first restored workspace
          for _, w in ipairs(wezterm.mux.all_windows()) do
            first_window = w:gui_window()
            break
          end
        end
      end
    end
    if first_window then
      first_window:perform_action(
        act.SwitchToWorkspace { name = saved_names[1]:match('(.+)%.json$') or saved_names[1] },
        first_window:active_pane()
      )
      first_window:maximize()
    end
  else
    -- No saves yet — just open a plain, normal WezTerm window.
    -- (A gui-startup handler must spawn the window itself.) No splits, no
    -- forced project dir, no commands. From here on, your real layouts are
    -- saved automatically and restored on the next launch.
    local _, _, window = wezterm.mux.spawn_window(cmd or {})
    window:gui_window():maximize()
  end
end)

return config

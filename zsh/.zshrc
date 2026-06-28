# zsh profiling — enable with: ZPROF=1 zsh -i -c exit  (or: just zsh-profile)
[[ -n "$ZPROF" ]] && zmodload zsh/zprof

# Suppress p10k console-output warning (conda/brew run after instant prompt)
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# History — prevents corruption on crash
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS

# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/dotfiles/bin:$HOME/.atuin/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export NVM_DIR="$HOME/.nvm"

# Add NVM default node bin to PATH immediately so globally installed tools (vercel, etc.) work without triggering lazy load
[ -s "$NVM_DIR/alias/default" ] && export PATH="$NVM_DIR/versions/node/v$(cat $NVM_DIR/alias/default | sed 's/^v//')/bin:$PATH"

# Lazy-load nvm — defers the ~1s nvm.sh cost until first actual use
__nvm_lazy_load() {
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { unfunction nvm;  __nvm_lazy_load; nvm  "$@"; }
node() { unfunction node; __nvm_lazy_load; node "$@"; }
npm()  { unfunction npm;  __nvm_lazy_load; npm  "$@"; }
npx()  { unfunction npx;  __nvm_lazy_load; npx  "$@"; }

# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# OpenClaw Completion
[ -f "$HOME/.openclaw/completions/openclaw.zsh" ] && source "$HOME/.openclaw/completions/openclaw.zsh"
# Load secrets (API keys) — this file is never committed
[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"
[ -d "$HOME/.fly/bin" ] && export PATH="$HOME/.fly/bin:$PATH"
autoload bashcompinit
bashcompinit
[ -f "$HOME/.local/share/bash-completion/completions/appman" ] && source "$HOME/.local/share/bash-completion/completions/appman"
[ -d "$HOME/amp-superpowers/toolbox" ] && export AMP_TOOLBOX="$HOME/amp-superpowers/toolbox"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"


# Dev environment variables
[ -f "$HOME/.devrc" ] && source "$HOME/.devrc"

# Aliases
[ -f "$HOME/.aliases" ] && source "$HOME/.aliases"

# atuin (shell history sync) — init after aliases so it can override Ctrl+R
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# Show personal dashboard once per day — deferred to precmd so it runs after
# p10k instant prompt is fully initialized (avoids console-output warning)
_dashboard_once() {
  local stamp="$HOME/.cache/dashboard-last-shown"
  local today
  today=$(date +%Y-%m-%d)
  if [ ! -f "$stamp" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$today" ]; then
    echo "$today" > "$stamp"
    [ -f "$HOME/dotfiles/scripts/dashboard.sh" ] && bash "$HOME/dotfiles/scripts/dashboard.sh"
  fi
  # Remove self after first run so it only fires once per session
  precmd_functions=(${precmd_functions:#_dashboard_once})
}
[[ $- == *i* ]] && precmd_functions+=(_dashboard_once)

# fzf
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ]    && source /usr/share/doc/fzf/examples/completion.zsh

# WezTerm shell integration
# Emits OSC sequences so WezTerm can: track CWD (better tab titles + status bar),
# mark prompt zones (Ctrl+Shift+Up/Down jumps between commands in scrollback),
# and ring the bell when a long command finishes (triggers toast notification).
if [[ -n "$WEZTERM_PANE" ]]; then
  __wezterm_cwd()          { printf "\033]7;file://%s%s\033\\" "$HOST" "$PWD" }
  __wezterm_prompt_start() { printf "\033]133;A\033\\" }
  __wezterm_prompt_end()   { printf "\033]133;B\033\\" }
  __wezterm_cmd_start()    { printf "\033]133;C\033\\" }
  __wezterm_cmd_end()      {
    local e=$?
    printf "\033]133;D;%s\033\\" "$e"
    printf "\033]1337;SetUserVar=%s=%s\033\\" "LAST_EXIT" "$(printf '%s' "$e" | base64 -w0)"
  }

  precmd_functions+=(__wezterm_cmd_end __wezterm_cwd __wezterm_prompt_start)
  preexec_functions+=(__wezterm_cmd_start)
  PROMPT="${PROMPT}"$'\033]133;B\033\\'

  # alert: append "; alert" to any long command to get a toast when it finishes
  alias alert='printf "\a"'
fi

# kill process on a given port
killport() { lsof -ti :"$1" | xargs kill -9; }

# zoxide (smarter cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

[ -x "$HOME/.linuxbrew/bin/brew" ] && eval "$($HOME/.linuxbrew/bin/brew shellenv)"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
if [ -d "$HOME/anaconda3" ]; then
    __conda_setup="$("$HOME/anaconda3/bin/conda" 'shell.zsh' 'hook' 2>/dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ] && . "$HOME/anaconda3/etc/profile.d/conda.sh" \
            || export PATH="$HOME/anaconda3/bin:$PATH"
    fi
    unset __conda_setup
fi
# <<< conda initialize <<<

[[ -n "$ZPROF" ]] && zprof

. "$HOME/.atuin/bin/env"

# opencode
export PATH=/Users/hassanjan/.opencode/bin:$PATH

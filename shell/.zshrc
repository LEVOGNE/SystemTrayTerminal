# quickTerminal zsh config

# Guard: prevent infinite re-entry
[[ -n "$_QT_ZSHRC_LOADED" ]] && return
_QT_ZSHRC_LOADED=1

# Source user's original config — save/restore ZDOTDIR explicitly
# in case user's .zshrc overwrites it
if [[ -n "$HOME" && -r "$HOME/.zshrc" ]]; then
    _qt_saved_zdotdir="$ZDOTDIR"
    ZDOTDIR="$HOME" source "$HOME/.zshrc" 2>/dev/null
    ZDOTDIR="$_qt_saved_zdotdir"
    unset _qt_saved_zdotdir
fi

_qt_dir="${ZDOTDIR:-${0:a:h}}"

# Commands starting with space don't go to history
setopt HIST_IGNORE_SPACE

# Completion system — interactive menu with arrow keys
autoload -Uz compinit
compinit -d "${TMPDIR:-/tmp}/.zcompdump-qt"
zmodload zsh/complist
setopt AUTO_LIST
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END

# Menu select: shows list, navigate with arrows, enter to pick
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*:cd:*' tag-order local-directories directory-stack
zstyle ':completion:*:cd:*' ignore-parents parent pwd
zstyle ':completion:*' list-rows-first true

# Arrow keys in completion menu (normal + application mode)
bindkey -M menuselect '^[[A' up-line-or-history
bindkey -M menuselect '^[[B' down-line-or-history
bindkey -M menuselect '^[[C' forward-char
bindkey -M menuselect '^[[D' backward-char
bindkey -M menuselect '^[OA' up-line-or-history
bindkey -M menuselect '^[OB' down-line-or-history
bindkey -M menuselect '^[OC' forward-char
bindkey -M menuselect '^[OD' backward-char
bindkey -M menuselect '^M' .accept-line

# Prefix history search: type e.g. "ssh" then press ↑/↓ to cycle matching commands
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search    # normal mode ↑
bindkey '^[[B' down-line-or-beginning-search  # normal mode ↓
bindkey '^[OA' up-line-or-beginning-search    # application mode ↑
bindkey '^[OB' down-line-or-beginning-search  # application mode ↓

# Ghost text autosuggestions
source "${_qt_dir}/zsh-autosuggestions.zsh"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#555555'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Smart Tab: cd commands always show directory menu, others accept ghost first
_qt_smart_tab() {
    if [[ "$BUFFER" == cd\ * ]] || [[ "$BUFFER" == CD\ * ]] || [[ "$BUFFER" == "cd" ]]; then
        zle expand-or-complete
    elif (( ${#POSTDISPLAY} )); then
        zle autosuggest-accept
    else
        zle expand-or-complete
    fi
}
zle -N _qt_smart_tab
bindkey '\t' _qt_smart_tab
# Right arrow: accept ghost suggestion if present, otherwise move cursor right
_qt_right_arrow() {
    if (( ${#POSTDISPLAY} )); then
        zle autosuggest-accept
    else
        zle forward-char
    fi
}
zle -N _qt_right_arrow
bindkey '^[[C' _qt_right_arrow   # normal mode
bindkey '^[OC' _qt_right_arrow   # application mode

# Prompt theme (must load before syntax highlighting)
source "${_qt_dir}/themes/qt-theme-loader.sh" 2>/dev/null

# Syntax highlighting — colorful terminal like a code editor
if [[ -n "$QT_SYNTAX_HL" ]]; then
    # Colorful LS
    export LS_COLORS='di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32:bd=1;33:cd=1;33:su=37;41:sg=30;43:tw=30;42:ow=34;42'
    alias ls='ls --color=auto 2>/dev/null || ls -G'
    alias grep='grep --color=auto'
    alias diff='diff --color=auto'

    # zsh-syntax-highlighting (bundled or homebrew)
    if [[ -f "${_qt_dir}/zsh-syntax-highlighting.zsh" ]]; then
        source "${_qt_dir}/zsh-syntax-highlighting.zsh"
    elif [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    elif [[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
        source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    fi
fi

# Easter egg splash command (shared across all shells)
source "${_qt_dir}/.qt-splash.sh" 2>/dev/null

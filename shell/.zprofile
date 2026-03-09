# quickTerminal zsh profile
# Sourced after .zshenv, before .zshrc — for login shells only
# Ensures PATH and tools are available regardless of launch method
# (Finder/.app gives minimal PATH vs Terminal which inherits full environment)

# Guard: prevent infinite re-entry
[[ -n "$_QT_ZPROFILE_LOADED" ]] && return
_QT_ZPROFILE_LOADED=1

# 1. macOS path_helper — reads /etc/paths + /etc/paths.d/*
#    Works on both Apple Silicon (/opt/homebrew) and Intel (/usr/local)
if [[ -x /usr/libexec/path_helper ]]; then
    eval "$(/usr/libexec/path_helper -s)"
fi

# 2. Source user's login profile (Homebrew, pyenv, nvm, rbenv, conda, etc.)
if [[ -n "$HOME" && -r "$HOME/.zprofile" ]]; then
    _qt_saved_zdotdir="$ZDOTDIR"
    ZDOTDIR="$HOME" source "$HOME/.zprofile" 2>/dev/null
    ZDOTDIR="$_qt_saved_zdotdir"
    unset _qt_saved_zdotdir
fi

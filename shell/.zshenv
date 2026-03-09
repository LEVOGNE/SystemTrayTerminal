# quickTerminal zsh environment
# Sourced first, before .zprofile and .zshrc — for all shell types

# Guard: prevent infinite re-entry
[[ -n "$_QT_ZSHENV_LOADED" ]] && return
_QT_ZSHENV_LOADED=1

# Source user's .zshenv (env vars, tool inits that must run everywhere)
if [[ -n "$HOME" && -r "$HOME/.zshenv" ]]; then
    _qt_saved_zdotdir="$ZDOTDIR"
    ZDOTDIR="$HOME" source "$HOME/.zshenv" 2>/dev/null
    ZDOTDIR="$_qt_saved_zdotdir"
    unset _qt_saved_zdotdir
fi

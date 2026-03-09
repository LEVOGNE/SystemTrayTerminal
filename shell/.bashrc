# quickTerminal bash config

# Guard: prevent infinite re-entry
[[ -n "$_QT_BASHRC_LOADED" ]] && return
_QT_BASHRC_LOADED=1

# Ensure PATH is complete (critical for .app bundle launched from Finder)
if [[ -x /usr/libexec/path_helper ]]; then
    eval "$(/usr/libexec/path_helper -s)"
fi

# Source user's original config
if [[ -n "$HOME" && -r "$HOME/.bash_profile" ]]; then
    source "$HOME/.bash_profile"
elif [[ -n "$HOME" && -r "$HOME/.bashrc" ]]; then
    source "$HOME/.bashrc"
elif [[ -n "$HOME" && -r "$HOME/.profile" ]]; then
    source "$HOME/.profile"
fi

# Commands starting with space don't go to history
HISTCONTROL="${HISTCONTROL:+$HISTCONTROL:}ignorespace"

# Easter egg splash command (shared across all shells)
_qt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_qt_dir}/.qt-splash.sh" 2>/dev/null

# Prompt theme
source "${_qt_dir}/themes/qt-theme-loader.sh" 2>/dev/null

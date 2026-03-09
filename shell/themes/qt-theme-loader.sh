#!/bin/sh
# quickTerminal Prompt Theme Loader
# Reads QT_PROMPT_THEME env var and sources the matching theme

_qt_theme="${QT_PROMPT_THEME:-default}"

# Clean up any previous quickTerminal theme hooks
if [ -n "$ZSH_VERSION" ]; then
    precmd_functions=(${precmd_functions:#_qt_*})
elif [ -n "$BASH_VERSION" ]; then
    case "$PROMPT_COMMAND" in _qt_*) unset PROMPT_COMMAND ;; esac
fi

# Default = no override, restore user's prompt
if [ "$_qt_theme" = "default" ]; then
    if [ -n "$_qt_orig_prompt" ]; then
        if [ -n "$ZSH_VERSION" ]; then
            PROMPT="$_qt_orig_prompt"
        else
            PS1="$_qt_orig_prompt"
        fi
    fi
    # Restore user's original PROMPT_COMMAND in bash
    if [ -n "$BASH_VERSION" ] && [ -n "$_qt_orig_prompt_cmd" ]; then
        PROMPT_COMMAND="$_qt_orig_prompt_cmd"
    fi
    unset _qt_theme
    return 0 2>/dev/null || true
fi

# Save original prompt before first theme override
if [ -z "$_qt_orig_prompt" ]; then
    if [ -n "$ZSH_VERSION" ]; then
        _qt_orig_prompt="$PROMPT"
    else
        _qt_orig_prompt="$PS1"
        _qt_orig_prompt_cmd="$PROMPT_COMMAND"
    fi
fi

# Resolve themes directory
_qt_themes_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}" 2>/dev/null)" 2>/dev/null && pwd)"
# Fallback: derive from ZDOTDIR or ENV
if [ -z "$_qt_themes_dir" ] || [ "$_qt_themes_dir" = "." ]; then
    if [ -n "$ZDOTDIR" ]; then
        _qt_themes_dir="$ZDOTDIR/themes"
    elif [ -n "$ENV" ]; then
        _qt_themes_dir="$(cd "$(dirname "$ENV")" 2>/dev/null && pwd)/themes"
    fi
fi

_qt_theme_file="$_qt_themes_dir/qt-theme-${_qt_theme}.sh"

if [ -f "$_qt_theme_file" ]; then
    . "$_qt_theme_file"
fi

unset _qt_theme _qt_themes_dir _qt_theme_file

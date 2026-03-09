#!/bin/sh
# quickTerminal Theme: Minimal
# dir ❯  (git only when dirty: dir * ❯)

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

_qt_git_dirty() {
    git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && return 1
    return 0
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    _qt_minimal_precmd() {
        local dirty=""
        if _qt_git_dirty; then
            dirty=" %F{red}*%f"
        fi
        PROMPT="%F{blue}%1~%f${dirty} %F{white}❯%f "
    }
    precmd_functions+=(_qt_minimal_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_minimal_prompt() {
        local dirty=""
        if _qt_git_dirty; then
            dirty=" \[\033[31m\]*\[\033[0m\]"
        fi
        PS1="\[\033[34m\]\W\[\033[0m\]${dirty} \[\033[37m\]❯\[\033[0m\] "
    }
    PROMPT_COMMAND="_qt_minimal_prompt"
else
    PS1="\$(basename \"\$PWD\") > "
fi

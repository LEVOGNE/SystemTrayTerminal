#!/bin/sh
# quickTerminal Theme: Starship
# Two-line: ~/path on  branch [!]
#           ❯  (green/red based on exit code)

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

_qt_git_dirty() {
    git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && return 1
    return 0
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    # Early-capture function to save exit code before other precmd hooks run
    _qt_starship_save_status() { _qt_last_exit=$?; }
    _qt_starship_precmd() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            local dirty=""
            if _qt_git_dirty; then dirty=" %F{red}[!]%f"; fi
            git_info=" on %F{magenta} ${branch}%f${dirty}"
        fi
        local arrow_color="%F{green}"
        if [ "$_qt_last_exit" -ne 0 ] 2>/dev/null; then arrow_color="%F{red}"; fi
        PROMPT="%F{cyan}%~%f${git_info}"$'\n'"${arrow_color}❯%f "
    }
    # Prepend save_status so it runs first, before other precmd hooks
    precmd_functions=(_qt_starship_save_status $precmd_functions)
    precmd_functions+=(_qt_starship_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_starship_prompt() {
        local last_exit=$?
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            local dirty=""
            if _qt_git_dirty; then dirty=" \[\033[31m\][!]\[\033[0m\]"; fi
            git_info=" on \[\033[35m\] ${branch}\[\033[0m\]${dirty}"
        fi
        local arrow_color="\[\033[32m\]"
        if [ $last_exit -ne 0 ]; then arrow_color="\[\033[31m\]"; fi
        PS1="\[\033[36m\]\w\[\033[0m\]${git_info}\n${arrow_color}❯\[\033[0m\] "
    }
    PROMPT_COMMAND="_qt_starship_prompt"
else
    PS1="\$PWD
> "
fi

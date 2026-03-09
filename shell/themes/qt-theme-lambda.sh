#!/bin/sh
# quickTerminal Theme: Lambda
# λ ~/path [branch] →

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

_qt_git_dirty() {
    git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && return 1
    return 0
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    _qt_lambda_precmd() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            local color="%F{green}"
            if _qt_git_dirty; then color="%F{red}"; fi
            git_info=" ${color}[${branch}]%f"
        fi
        PROMPT="%F{magenta}λ%f %F{cyan}%~%f${git_info} %F{magenta}→%f "
    }
    precmd_functions+=(_qt_lambda_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_lambda_prompt() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            local color="\[\033[32m\]"
            if _qt_git_dirty; then color="\[\033[31m\]"; fi
            git_info=" ${color}[${branch}]\[\033[0m\]"
        fi
        PS1="\[\033[35m\]λ\[\033[0m\] \[\033[36m\]\w\[\033[0m\]${git_info} \[\033[35m\]→\[\033[0m\] "
    }
    PROMPT_COMMAND="_qt_lambda_prompt"
else
    PS1="λ \$PWD → "
fi

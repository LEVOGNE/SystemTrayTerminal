#!/bin/sh
# quickTerminal Theme: Retro
# [user@quickterm ~/path (branch)]$  (green classic)

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    _qt_retro_precmd() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            git_info=" %F{yellow}(${branch})%f"
        fi
        PROMPT="%F{green}[%n@quickterm %~${git_info}%F{green}]%f$ "
    }
    precmd_functions+=(_qt_retro_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_retro_prompt() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            git_info=" \[\033[33m\](${branch})\[\033[0m\]"
        fi
        PS1="\[\033[32m\][\u@quickterm \w${git_info}\[\033[32m\]]\[\033[0m\]$ "
    }
    PROMPT_COMMAND="_qt_retro_prompt"
else
    PS1="[$(whoami)@quickterm \$PWD]\$ "
fi

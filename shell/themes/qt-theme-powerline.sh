#!/bin/sh
# quickTerminal Theme: Powerline
# ▌user ▌~/path ▌branch ▌ (Unicode arrows, no Nerd Font needed)

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

_qt_git_dirty() {
    git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && printf '' || printf ' ●'
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    _qt_powerline_precmd() {
        local branch
        branch=$(_qt_git_branch)
        local git_seg=""
        if [ -n "$branch" ]; then
            git_seg="%K{blue}%F{white} ${branch}$(_qt_git_dirty) %f%k%F{blue}▌%f"
        fi
        PROMPT="%K{green}%F{black} %n %f%k%F{green}▌%f%K{yellow}%F{black} %~ %f%k%F{yellow}▌%f${git_seg} "
    }
    precmd_functions+=(_qt_powerline_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_powerline_prompt() {
        local branch
        branch=$(_qt_git_branch)
        local git_seg=""
        if [ -n "$branch" ]; then
            git_seg="\[\033[44;37m\] ${branch}$(_qt_git_dirty) \[\033[0;34m\]▌\[\033[0m\]"
        fi
        PS1="\[\033[42;30m\] \u \[\033[0;32m\]▌\[\033[43;30m\] \w \[\033[0;33m\]▌\[\033[0m\]${git_seg} "
    }
    PROMPT_COMMAND="_qt_powerline_prompt"
else
    PS1="▌$(whoami) ▌\$PWD ▌ "
fi

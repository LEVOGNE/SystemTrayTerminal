#!/bin/sh
# quickTerminal Theme: Cyberpunk
# ╭─ ⚡user in ~/path ‹branch ✔› ╰─❯

_qt_git_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

_qt_git_dirty() {
    git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null && printf '✔' || printf '✘'
}

if [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    _qt_cyberpunk_precmd() {
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            git_info=" %F{magenta}‹${branch} $(_qt_git_dirty)›%f"
        fi
        PROMPT=$'\n'"╭─ %F{cyan}⚡%n%f in %F{yellow}%~%f${git_info}"$'\n'"╰─%F{cyan}❯%f "
    }
    precmd_functions+=(_qt_cyberpunk_precmd)
elif [ -n "$BASH_VERSION" ]; then
    _qt_cyberpunk_prompt() {
        local exit_code=$?
        local branch
        branch=$(_qt_git_branch)
        local git_info=""
        if [ -n "$branch" ]; then
            git_info=" \[\033[35m\]‹${branch} $(_qt_git_dirty)›\[\033[0m\]"
        fi
        PS1="\n╭─ \[\033[36m\]⚡\u\[\033[0m\] in \[\033[33m\]\w\[\033[0m\]${git_info}\n╰─\[\033[36m\]❯\[\033[0m\] "
    }
    PROMPT_COMMAND="_qt_cyberpunk_prompt"
else
    PS1="
╭─ ⚡$(whoami) in \$PWD
╰─❯ "
fi

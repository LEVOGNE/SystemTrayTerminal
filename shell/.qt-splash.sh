# quickTerminal ASCII art splash — shared across all shells
# Sourced by .zshrc, .bashrc, .shrc

quickterminal() {
    _e=$(printf '\033')
    _bold="${_e}[1m"
    _reset="${_e}[0m"
    _c1="${_e}[38;5;33m"
    _c2="${_e}[38;5;39m"
    _c3="${_e}[38;5;45m"
    _c4="${_e}[38;5;49m"
    _c5="${_e}[38;5;141m"
    _c6="${_e}[38;5;207m"
    _c7="${_e}[38;5;75m"
    _c8="${_e}[38;5;255m"
    _dim="${_e}[38;5;240m"

    echo ""
    echo "${_c1}${_bold}   __ _ _  _(_)__| |_${_reset}"
    sleep 0.06
    echo "${_c2}${_bold}  / _\` | || | / _| / /${_reset}"
    sleep 0.06
    echo "${_c3}${_bold}  \\__, |\\_,_|_\\__|_\\_\\${_reset}"
    sleep 0.06
    echo "${_c4}${_bold}     |_|${_reset}"
    sleep 0.06
    echo "${_c5}${_bold} _____ ___ ___ __  __ ___ _  _   _   _${_reset}"
    sleep 0.06
    echo "${_c6}${_bold}|_   _| __| _ \\  \\/  |_ _| \\| | /_\\ | |${_reset}"
    sleep 0.06
    echo "${_c7}${_bold}  | | | _||   / |\\/| || || .\` |/ _ \\| |__${_reset}"
    sleep 0.06
    echo "${_c8}${_bold}  |_| |___|_|_\\_|  |_|___|_|\\_/_/ \\_\\____|${_reset}"
    echo ""
    echo "  ${_dim}─── ${_c3}⚡ fast. minimal. yours. ⚡ ${_dim}───${_reset}"
    echo ""
}

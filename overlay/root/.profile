alias grep="grep --color=always"
alias screen="screen -d -RR -S main_scr_session"

# nice ls
alias ls='eza \
  --changed \
  --classify \
  --color=always \
  --dereference \
  --git \
  --group \
  --group-directories-first \
  --hyperlink \
  --links \
  --icons \
  --long \
  --octal-permissions \
  --time-style=long-iso \
'

alias la='ls -la'

is_alphanum() {
    local num="$1"
    [[ "$num" =~ ^[0-9]+$ ]]
}

# expected format is GPIO<bank>_<group><pin>
# bank = 0,1,2,3,...
# group = A/a,B/b,C/c,...
# pin = 0,1,2,3,...
parse_gpio() {
    local gpio="${1-$(cat)}"
    local bank group pin

    # Extract bank, group, and pin using sed
    bank=$(echo "$gpio" | sed -n 's/[Gg][Pp][Ii][Oo]\([0-9]\+\)_\?\([A-Za-z]\).*/\1/p')
    group=$(echo "$gpio" | sed -n 's/[Gg][Pp][Ii][Oo][0-9]\+_\?\([A-Za-z]\).*/\1/p')
    pin=$(echo "$gpio" | sed -n 's/.*_\?\([A-Za-z]\)\([0-9]\+\)/\2/p')

    echo "$bank" "$group" "$pin"
}

calc_gpio() {
    local bank="$1"
    local group="$2"    # A/a,B/b,C/c,...
    local pin="$3"

    if ! is_alphanum "$bank" || ! is_alphanum "$pin"; then
        echo "Bank and pin must be numeric." >&2
        return 1
    fi

    group="${group^^}"

    case "$group" in
        "A") group="0" ;;
        "B") group=1 ;;
        "C") group=2 ;;
        "D") group=3 ;;
        "E") group=4 ;;
        "F") group=5 ;;
        "G") group=6 ;;
        "H") group=7 ;;
        "I") group=8 ;;
        "J") group=9 ;;
        "K") group=10 ;;
        "L") group=11 ;;
        "M") group=12 ;;
        "N") group=13 ;;
        "O") group=14 ;;
        "P") group=15 ;;
        "Q") group=16 ;;
        "R") group=17 ;;
        "S") group=18 ;;
        "T") group=19 ;;
        "U") group=20 ;;
        "V") group=21 ;;
        "W") group=22 ;;
        "X") group=23 ;;
        "Y") group=24 ;;
        "Z") group=25 ;;
        *) group=0 ;;
    esac

    echo "$((bank * 32 + (group * 8 + pin)))"
}

get_gpio() {
    local gpio="${1-$(cat)}"
    echo "$gpio" > /sys/class/gpio/export
    echo in > "/sys/class/gpio/gpio$gpio/direction"
    cat "/sys/class/gpio/gpio$gpio/value"
}

set_gpio() {
    local gpio="${1-$(cat)}"
    local value="${2-${1}}"

    echo "$gpio" > /sys/class/gpio/export
    echo out > "/sys/class/gpio/gpio$gpio/direction"
    echo "$value" > "/sys/class/gpio/gpio$gpio/value"
}

toggle_gpio() {
    local gpio="${1-$(cat)}"
    local value

    value="$(get_gpio "$gpio")"
    [[ "$value" == "0" ]] && value=1 || value=0

    set_gpio "$gpio" "$value"
}

sync_time() {
    ntpd -dqn
}

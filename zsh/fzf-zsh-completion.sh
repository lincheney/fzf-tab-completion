# set ft=zsh

_FZF_COMPLETION_SEP=$'\x7f'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l o 1 2 C )

fzf_completion() {
    local value code
    local __compadd_args=() __comparguments_args=()

    eval "$(
        set -o pipefail
        # hacks
        comparguments() { _fzf_completion_comparguments "$@"; }
        compadd() { _fzf_completion_compadd "$@"; }

        exec {__evaled}>&1
        value="$(
            (
                local __comp_index=0 __comparguments_replay=
                _main_complete || true
            ) | grep . | awk -F"$_FZF_COMPLETION_SEP" '!x[$2]++' | _fzf_completion_selector
        )"
        code="$?"
        exec {__evaled}>&-

        printf 'value=%q\n' "$value"
        printf 'code=%q\n' "$code"
    )"

    if [ "$code" = 0 ]; then
        local opts index
        while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
            index="${value[1]}"
            opts="${__compadd_args[$index]}"
            eval "${__comparguments_args[$index]}"
            eval "compadd $opts -- ${(q)value[2]}"
        done <<<"$value"
        # insert everything added by fzf
        compstate[insert]=all
    fi
    tput cuu "$(( BUFFERLINES ))" # move back up
    zle -I
}

_fzf_completion_selector() {
    read -r first || return 1 # no input
    if ! read -r second; then
        echo "$first" && return # only one input
    fi

    tput cud1 >/dev/tty # fzf clears the line on exit so move down one
    cat <(printf %s\\n "$first" "$second") - | \
        FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
            fzf --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 3.. --nth 2 -m
    code="$?"
    tput cuu1 >/dev/tty
    return "$code"
}

# comparguments hack
# seems to be function local so its hard to hijack
# so we record all calls to comparguments and replay them every time
_fzf_completion_comparguments() {
    if [ "$1" = -i ]; then
        # reset
        __comparguments_replay=
    fi
    __comparguments_replay+="; builtin comparguments $(printf '%q ' "$@")"
    eval "$__comparguments_replay"
    return "$?"
}

_fzf_completion_compadd() {
    local __flags=()
    local __OAD=()
    local __disp __hits
    zparseopts -D -E -a __opts -A __optskv -- "${^_FZF_COMPLETION_FLAGS[@]}+=__flags" F+: P+: S+: p+: s+: i+: I+: W+: d+:=__disp J+: V+: X+: x+: r+: R+: D+: O+: A+: E+: M+:
    local __filenames="${__flags[(r)-f]}"

    if [ -n "${__optskv[(i)-A]}${__optskv[(i)-O]}${__optskv[(i)-D]}" ]; then
        # handle -O -A -D
        builtin compadd "${__OAD[@]}" "${__flags[@]}" "${__opts[@]}" "$@"
        return "$?"
    fi

    if [ "${__disp[2]:0:1}" = '(' ]; then
        eval "__disp=${__disp[2]}"
    else
        __disp=( "${(@P)__disp[2]}" )
    fi

    eval "$__comparguments_replay"
    printf '__comparguments_args+=( %q )\n' "${__comparguments_replay+builtin comparguments -i '' -s :; $__comparguments_replay}" >&"${__evaled}"

    builtin compadd -A __hits -D __disp "${__flags[@]}" "${__opts[@]}" "$@"
    local code="$?"
    __flags="${(j..)__flags//[ak-]}"
    printf '__compadd_args+=( %q )\n' "$(printf '%q ' ${__flags:+-$__flags} "${__opts[@]}")" >&"${__evaled}"
    (( __comp_index++ ))

    local prefix="${__optskv[-W]:-.}"
    __disp=( "${__hits[@]}" ) # display strings not handled for now
    for ((i = 1; i <= $#__hits; i++)); do
        if [ -n "$__filenames" -a "${__disp[$i]:-${__hits[$i]}}" = "${__hits[$i]}" -a -d "${prefix}/${__hits[$i]}" ]; then
            __disp[$i]="${__hits[$i]}/"
        elif [[ "${__disp[$i]}" == "${__hits[$i]}"* ]]; then
            __disp[$i]="${__hits[$i]}${_FZF_COMPLETION_SEP}${__disp[$i]:${#__hits[$i]}}"
        fi

        __disp[$i]="${__disp[$i]:-${__hits[$i]}}"
        if [[ "${__disp[$i]}" == "$PREFIX"* ]]; then
            __disp[$i]="${PREFIX}${_FZF_COMPLETION_SEP}${__disp[$i]:${#PREFIX}}"
        else
            __disp[$i]="${_FZF_COMPLETION_SEP}${__disp[$i]}"
        fi

        # index, value, prefix, display
        echo "${__comp_index}${_FZF_COMPLETION_SEP}${__hits[$i]}${_FZF_COMPLETION_SEP}${__disp[$i]}"
    done
    return "$code"
}

zle -C fzf_completion complete-word fzf_completion
fzf_default_completion=fzf_completion

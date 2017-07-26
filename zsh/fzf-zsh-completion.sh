# set ft=zsh

_FZF_COMPLETION_SEP=$'\x7f'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l o 1 2 C )

fzf_completion_widget() {
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
                local __comp_index=1 __comparguments_replay=
                _main_complete || true
            ) | grep . | awk -F"$_FZF_COMPLETION_SEP" '!x[$2]++' |
            FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
            fzf -1 -0 --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 3.. --nth 1 -m
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
    zparseopts -D -E -A __opts -- "${^_FZF_COMPLETION_FLAGS[@]}+=__flags" F: P: S: p: s: i: I: W: d: J: V: X: x: r: R: D: O: A: E: M:
    local __filenames="${__opts[(i)-f]}"
    unset "__opts[-${^_FZF_COMPLETION_FLAGS[@]}]"

    if [ -n "${__opts[(i)-A]}${__opts[(i)-O]}${__opts[(i)-D]}" ]; then
        # handle -O -A -D
        builtin compadd "${__flags[@]}" "${(kv)__opts[@]}" "$@"
        return "$?"
    fi

    local __disp __hits
    if [ "${__opts[-d]:0:1}" = '(' ]; then
        eval "__disp=${__opts[-d]}"
    else
        __disp=( "${(@P)__opts[-d]}" )
    fi

    eval "$__comparguments_replay"
    printf '__comparguments_args+=( %q )\n' "${__comparguments_replay+builtin comparguments -i '' -s :; $__comparguments_replay}" >&"${__evaled}"

    builtin compadd "${__flags[@]}" "${(kv)__opts[@]}" -A __hits -D __disp "$@"
    local code="$?"
    __flags="${(j..)__flags//[ak-]}"
    unset '__opts[-d]'
    printf '__compadd_args+=( %q )\n' "$(printf '%q ' ${__flags:+-$__flags} "${(kv)__opts[@]}")" >&"${__evaled}"
    (( __comp_index++ ))

    local prefix="${__opts[-W]:-.}"
    local __disp=( "${__hits[@]}" ) # display strings not handled for now
    for ((i = 1; i <= $#__hits; i++)); do
        if [ -n "$__filenames" -a "${__disp[$i]:-${__hits[$i]}}" = "${__hits[$i]}" -a -d "${prefix}/${__hits[$i]}" ]; then
            __disp[$i]="${__hits[$i]}/"
        elif [[ "${__disp[$i]}" == "${__hits[$i]}"* ]]; then
            __disp[$i]="${__hits[$i]}${_FZF_COMPLETION_SEP}${__disp[$i]:${#__hits[$i]}}"
        fi
        # index, value, description
        echo "${__comp_index}${_FZF_COMPLETION_SEP}${__hits[$i]}${_FZF_COMPLETION_SEP}${__disp[$i]:-${__hits[$i]}}"
    done
    return "$code"
}

fzf_completion() {
    zle fzf_completion_widget
    zle redisplay
}

zle -C fzf_completion_widget complete-word fzf_completion_widget
zle -N fzf_completion

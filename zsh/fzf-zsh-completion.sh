# set ft=zsh

_FZF_COMPLETION_SEP=$'\x7f'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l o 1 2 C )

fzf_completion() {
    local value code
    local __compadd_args=()

    eval "$(
        set -o pipefail
        # hacks
        compadd() { _fzf_completion_compadd "$@"; }

        exec {__evaled}>&1
        value="$(
            (
                local __comp_index=0
                _main_complete || true
            ) | awk -F"$_FZF_COMPLETION_SEP" '$2 && !x[$2]++' | _fzf_completion_selector
        )"
        code="$?"
        exec {__evaled}>&-

        printf 'value=%q\n' "$value"
        printf 'code=%q\n' "$code"
    )"

    case "$code" in
        0)
            local opts index
            while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
                index="${value[1]}"
                opts="${__compadd_args[$index]}"
                eval "$opts -- ${(q)value[2]}"
            done <<<"$value"
            # insert everything added by fzf
            compstate[insert]=all
            ;;
        1)
            # run all compadds with no matches, in case any messages to display
            eval "${(j.;.)__compadd_args} --"
            ;;
    esac
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
            fzf --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 3.. --nth 2
    code="$?"
    tput cuu1 >/dev/tty
    return "$code"
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

    builtin compadd -A __hits -D __disp "${__flags[@]}" "${__opts[@]}" "$@"
    local code="$?"
    __flags="${(j..)__flags//[ak-]}"
    printf '__compadd_args+=( %q )\n' "$(printf '%q ' PREFIX="$PREFIX" IPREFIX="$IPREFIX" SUFFIX="$SUFFIX" ISUFFIX="$ISUFFIX" compadd ${__flags:+-$__flags} "${__opts[@]}")" >&"${__evaled}"
    (( __comp_index++ ))

    local prefix="${__optskv[-W]:-.}"
    local __disp_str __hit_str
    __disp=( "${__hits[@]}" ) # display strings not handled for now
    for ((i = 1; i <= $#__hits; i++)); do
        __hit_str="${__hits[$i]}"
        __disp_str="${__disp[$i]:-$__hit_str}"

        if [ -n "$__filenames" -a "$__disp_str" = "$__hit_str" -a -d "${prefix}/$__hit_str" ]; then
            __disp_str+=/
        fi

        if [[ "$__disp_str" == "$PREFIX"* ]]; then
            __disp_str="${PREFIX}${_FZF_COMPLETION_SEP}${__disp_str:${#PREFIX}}"
        else
            __disp_str="${_FZF_COMPLETION_SEP}$__disp_str"
        fi

        # index, value, prefix, display
        echo "${__comp_index}${_FZF_COMPLETION_SEP}${__hit_str}${_FZF_COMPLETION_SEP}$__disp_str"
    done
    return "$code"
}

zle -C fzf_completion complete-word fzf_completion
fzf_default_completion=fzf_completion

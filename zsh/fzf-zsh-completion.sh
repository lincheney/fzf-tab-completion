# set ft=zsh

_FZF_COMPLETION_SEP=$'\x7f'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l o 1 2 C )

fzf_completion() {
    local value code stderr
    local __compadd_args=()

    if zstyle -t ':completion:' show-completer; then
        zle -R 'Loading matches ...'
    fi

    eval "$(
        # set -o pipefail
        # hacks
        override_compadd() { compadd() { _fzf_completion_compadd "$@"; }; }
        override_compadd

        # massive hack
        # _approximate also overrides _compadd, so we have to override their one
        override_approximate() {
            functions[_approximate]="unfunction compadd; { ${functions[_approximate]//builtin compadd /_fzf_completion_compadd } } always { override_compadd }"
        }

        if [[ "$functions[approximate]" == 'builtin autoload'* ]]; then
            _approximate() {
                builtin autoload +X _approximate
                override_approximate
                _approximate "$@"
            }
        else
            override_approximate
        fi

        # do not allow grouping, it stuffs up display strings
        zstyle ":completion:*:*" list-grouped no

        exec {__evaled}>&1
        value="$(
            (
                local __comp_index=0
                exec {stdout}>&1
                stderr="$(_main_complete 2>&1 1>&"${stdout}")" || true
                printf 'stderr=%q\n' "$stderr" >&"${__evaled}"
            ) | awk -F"$_FZF_COMPLETION_SEP" '$2!="" && !x[$2]++' | _fzf_completion_selector
            printf 'code=%q\n' "$?" >&"${__evaled}"
        )"
        exec {__evaled}>&-

        printf 'value=%q\n' "$value"
    )"

    case "$code" in
        0)
            local opts index
            while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
                index="${value[1]}"
                opts="${__compadd_args[$index]}"
                eval "$opts -- ${value[2]}"
            done <<<"$value"
            # insert everything added by fzf
            compstate[insert]=all
            ;;
        1)
            # run all compadds with no matches, in case any messages to display
            eval "${(j.;.)__compadd_args:-true} --"
            if [ "${#__compadd_args[@]}" = 0 ] && zstyle -s :completion:::::warnings format msg; then
                compadd -x "$msg"
            fi
            ;;
    esac

    if [ -n "$stderr" ]; then
        zle -M "$stderr"
    else
        zle -R ' '
    fi
}

_fzf_completion_selector() {
    read -r first || return 1 # no input
    if ! read -r second; then
        printf %s "$first" && return # only one input
    fi

    tput cud1 >/dev/tty # fzf clears the line on exit so move down one
    cat <(printf %s\\n "$first" "$second") - | \
        FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
            fzf --ansi --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 3..5 --nth 2
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

    builtin compadd -Q -A __hits -D __disp "${__flags[@]}" "${__opts[@]}" "$@"
    local code="$?"
    __flags="${(j..)__flags//[ak-]}"
    printf '__compadd_args+=( %q )\n' "$(printf '%q ' PREFIX="$PREFIX" IPREFIX="$IPREFIX" SUFFIX="$SUFFIX" ISUFFIX="$ISUFFIX" compadd ${__flags:+-$__flags} "${__opts[@]}")" >&"${__evaled}"
    (( __comp_index++ ))

    local prefix="${__optskv[-W]:-.}"
    local __disp_str __hit_str

    for ((i = 1; i <= $#__hits; i++)); do
        __hit_str="${__hits[$i]}"
        # display strings not handled for now
        __disp_str="${__disp[$i]:-}"
        __show_str="${(Q)__hit_str}"

        if [[ "$__disp_str" == "$__hit_str"* ]]; then
            __disp_str="${__disp_str:${#__hit_str}}"
        fi
        __disp_str=$'\x1b[37m'"$__disp_str"$'\x1b[0m'

        if [ -n "$__filenames" -a "$__show_str" = "$__hit_str" -a -d "${prefix}/$__hit_str" ]; then
            __show_str+=/
        fi
        if [[ "$__show_str" =~ '[^ -~]' ]]; then
            printf -v __show_str %q "$__show_str"
        fi

        if [[ "$__show_str" == "$PREFIX"* ]]; then
            __show_str="${PREFIX}${_FZF_COMPLETION_SEP}${__show_str:${#PREFIX}}"
        else
            __show_str="${_FZF_COMPLETION_SEP}$__show_str"
        fi

        # index, value, prefix, show, display
        printf %s\\n "${__comp_index}${_FZF_COMPLETION_SEP}${(q)__hit_str}${_FZF_COMPLETION_SEP}${__show_str}${_FZF_COMPLETION_SEP}${__disp_str}"
    done
    return "$code"
}

zle -C fzf_completion complete-word fzf_completion
fzf_default_completion=fzf_completion

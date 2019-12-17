# set ft=zsh

_FZF_COMPLETION_SEP=$'\x7f'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l o 1 2 C )

zmodload zsh/zselect
zmodload zsh/system

fzf_completion() {
    emulate -LR zsh
    setopt interactivecomments
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

        if [[ "$functions[_approximate]" == 'builtin autoload'* ]]; then
            _approximate() {
                unfunction _approximate
                printf %s\\n "builtin autoload +XUz _approximate" >&"${__evaled}"
                builtin autoload +XUz _approximate
                override_approximate
                _approximate "$@"
            }
        else
            override_approximate
        fi

        local autoloads="$(functions -u +)"

        # do not allow grouping, it stuffs up display strings
        zstyle ":completion:*:*" list-grouped no

        set -o monitor +o notify
        exec {__evaled}>&1
        coproc (
            (
                local __comp_index=0 __autoloaded=()
                exec {__stdout}>&1
                stderr="$(
                    _main_complete 2>&1 1>&"${__stdout}"
                    <<<"$autoloads" fgrep -xv "$(functions -u +)" | sed 's/^/builtin autoload +XUz /' >&"${__evaled}"
                )"
                printf %s\\n "stderr=${(q)stderr}" >&"${__evaled}"
            ) | awk -F"$_FZF_COMPLETION_SEP" '$2!="" && !x[$2]++ { print $0; system("") }'
        )
        coproc_pid="$!"
        value="$(_fzf_completion_selector <&p)"
        code="$?"
        kill -- -"$coproc_pid" 2>/dev/null && wait "$coproc_pid"

        printf 'code=%q; value=%q' "$code" "$value"
    )" 2>/dev/null

    case "$code" in
        0)
            local opts index
            while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
                index="${value[1]}"
                opts="${__compadd_args[$index]}"
                value=( "${(Q)value[2]}" )
                eval "$opts -a value"
            done <<<"$value"
            # insert everything added by fzf
            compstate[insert]=all
            ;;
        1)
            # run all compadds with no matches, in case any messages to display
            eval "${(j.;.)__compadd_args:-true} --"
            if (( ! ${#__compadd_args[@]} )) && zstyle -s :completion:::::warnings format msg; then
                compadd -x "$msg"
                compadd -x "$stderr"
                stderr=
            fi
            ;;
    esac

    if [ -n "$stderr" ]; then
        zle -M -- "$stderr"
    else
        zle -R ' ' ' '
    fi
}

_fzf_completion_selector() {
    local lines=() reply REPLY
    exec {tty}</dev/tty
    while (( ${#lines[@]} < 2 )); do
        zselect -r 0 "$tty"
        if (( reply[2] == 0 )); then
            if read -r; then
                lines+=( "$REPLY" )
            elif (( ${#lines[@]} == 1 )); then # only one input
                printf %s\\n "${lines[1]}" && return
            else # no input
                return 1
            fi
        else
            sysread -c 5 -t0.05 <&"$tty"
            [ "$REPLY" = $'\x1b' ] && return 130 # escape pressed
        fi
    done

    local context field=2
    context="${compstate[context]//-/-}"
    context="${context:=-$context-}"
    if zstyle -t ":completion:${context:-*}:*:${words[1]}" fzf-search-display; then
        field=2..5
    fi

    tput cud1 >/dev/tty # fzf clears the line on exit so move down one
    FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        fzf --ansi --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 3..5 --nth "$field" \
        < <(printf %s\\n "${lines[@]}"; cat)
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
    local __disp_str __hit_str __show_str

    for ((i = 1; i <= $#__hits; i++)); do
        __hit_str="${__hits[$i]}"
        __disp_str="${__disp[$i]:-"${__hit_str}"}"
        __show_str=

        if [[ "$__disp_str" == "$__hit_str"* ]]; then
            __show_str="${(Q)__hit_str}"
            __disp_str="${__disp_str:${#__hit_str}}"
            __disp_str=$'\x1b[37m'"$__disp_str"$'\x1b[0m'
        fi

        if [ -n "$__filenames" -a "$__show_str" = "$__hit_str" -a -d "${prefix}/$__hit_str" ]; then
            __show_str+=/
        fi
        if [[ "$__show_str" =~ '[^ -~]' ]]; then
            __show_str="${(q)__show_str}"
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

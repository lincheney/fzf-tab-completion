# set ft=zsh

_FZF_COMPLETION_SEP=$'\x01'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l 1 2 C )

zmodload zsh/zselect
zmodload zsh/system

_fzf_bash_completion_awk="$( { which gawk || echo awk; } 2>/dev/null)"

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

        # all except autoload functions
        local full_functions="$(functions + | fgrep -vx "$(functions -u +)")"

        # do not allow grouping, it stuffs up display strings
        zstyle ":completion:*:*" list-grouped no

        set -o monitor +o notify
        exec {__evaled}>&1
        trap '' INT
        coproc (
            (
                local __comp_index=0 __autoloaded=()
                exec {__stdout}>&1
                stderr="$(
                    _fzf_completion_preexit() {
                        echo set -A _comps "${(qkv)_comps[@]}" >&"${__evaled}"
                        functions + | fgrep -vx -e "$(functions -u +)" -e "$full_functions" | while read -r f; do which -- "$f"; done >&"${__evaled}"
                    }
                    trap _fzf_completion_preexit EXIT TERM
                    _main_complete 2>&1
                )"
                printf "stderr='%s'\\n" "${stderr//'/'\''}" >&"${__evaled}"
            # need to get awk to be unbuffered either by using -W interactive or system("")
            ) | "$_fzf_bash_completion_awk" -W interactive -F"$_FZF_COMPLETION_SEP" '$1!="" && !x[$1]++ { print $0; system("") }' 2>/dev/null
        )
        coproc_pid="$!"
        value="$(_fzf_completion_selector <&p)"
        code="$?"
        kill -- -"$coproc_pid" 2>/dev/null && wait "$coproc_pid"

        printf "code='%s'; value='%s'\\n" "${code//'/'\''}" "${value//'/'\''}"
    )" 2>/dev/null

    compstate[insert]=unambiguous
    case "$code" in
        0)
            local opts index
            while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
                index="${value[3]}"
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

    # reset-prompt doesn't work in completion widgets
    # so call it after this function returns
    eval "TRAPEXIT() {
        zle reset-prompt
        _fzf_completion_post ${(q)stderr} ${(q)code}
    }"
}

_fzf_completion_post() {
    local stderr="$1" code="$2"
    if [ -n "$stderr" ]; then
        zle -M -- "$stderr"
    elif (( code == 1 )); then
        zle -R ' '
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
            if IFS= read -r; then
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
    context="${compstate[context]//_/-}"
    context="${context:+-$context-}"
    if [ "$context" = -command- -a "$CURRENT" -gt 1 ]; then
        context="${words[1]}"
    fi
    context=":completion::complete:${context:-*}::${(j-,-)words[@]}"

    if zstyle -t "$context" fzf-search-display; then
        field=2..5
    fi

    local flags=()
    zstyle -a "$context" fzf-completion-opts flags

    tput cud1 >/dev/tty # fzf clears the line on exit so move down one
    FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        $(__fzfcmd 2>/dev/null || echo fzf) --ansi --prompt "> $PREFIX" -d "$_FZF_COMPLETION_SEP" --with-nth 4..6 --nth "$field" "${flags[@]}" \
        < <(printf %s\\n "${lines[@]}"; cat)
    code="$?"
    tput cuu1 >/dev/tty
    return "$code"
}

_fzf_completion_compadd() {
    local __flags=()
    local __OAD=()
    local __disp __hits __ipre __apre __hpre __hsuf __asuf __isuf __opts __optskv
    zparseopts -D -E -a __opts -A __optskv -- "${^_FZF_COMPLETION_FLAGS[@]}+=__flags" F+: P:=__apre S:=__asuf o+: p:=__hpre s:=__hsuf i:=__ipre I:=__isuf W+: d:=__disp J+: V+: X+: x+: r+: R+: D+: O+: A+: E+: M+:
    local __filenames="${__flags[(r)-f]}"
    local __noquote="${__flags[(r)-Q]}"
    local __is_param="${__flags[(r)-e]}"

    if [ -n "${__optskv[(i)-A]}${__optskv[(i)-O]}${__optskv[(i)-D]}" ]; then
        # handle -O -A -D
        builtin compadd "${__flags[@]}" "${__opts[@]}" "${__ipre[@]}" "$@"
        return "$?"
    fi

    if [[ "${__disp[2]}" =~ '^\(((\\.|[^)])*)\)' ]]; then
        IFS=$' \t\n\0' read -A __disp <<<"${match[1]}"
    else
        __disp=( "${(@P)__disp[2]}" )
    fi

    builtin compadd -Q -A __hits -D __disp "${__flags[@]}" "${__opts[@]}" "${__ipre[@]}" "${__apre[@]}" "${__hpre[@]}" "${__hsuf[@]}" "${__asuf[@]}" "${__isuf[@]}" "$@"
    local code="$?"
    __flags="${(j..)__flags//[ak-]}"
    if [ -z "${__optskv[(i)-U]}" ]; then
        # -U ignores $IPREFIX so add it to -i
        __ipre[2]="${IPREFIX}${__ipre[2]}"
        __ipre=( -i "${__ipre[2]}" )
        IPREFIX=
    fi
    local compadd_args="$(printf '%q ' PREFIX="$PREFIX" IPREFIX="$IPREFIX" SUFFIX="$SUFFIX" ISUFFIX="$ISUFFIX" compadd ${__flags:+-$__flags} "${__opts[@]}" "${__ipre[@]}" "${__apre[@]}" "${__hpre[@]}" "${__hsuf[@]}" "${__asuf[@]}" "${__isuf[@]}" -U)"
    printf "__compadd_args+=( '%s' )\n" "${compadd_args//'/'\''}" >&"${__evaled}"
    (( __comp_index++ ))

    local file_prefix="${__optskv[-W]:-.}"
    local __disp_str __hit_str __show_str __real_str __suffix
    local padding="$(printf %s\\n "${__disp[@]}" | "$_fzf_bash_completion_awk" '{print length}' | sort -nr | head -n1)"
    padding="$(( padding==0 ? 0 : padding>COLUMNS ? padding : COLUMNS ))"

    local prefix="${IPREFIX}${__ipre[2]}${__apre[2]}${__hpre[2]}"
    local suffix="${__hsuf[2]}${__asuf[2]}${__isuf[2]}"
    if [ -n "$__is_param" -a "$prefix" = '${' -a -z "$suffix" ]; then
        suffix+=}
    fi

    local i
    for ((i = 1; i <= $#__hits; i++)); do
        # actual match
        __hit_str="${__hits[$i]}"
        # full display string
        __disp_str="${__disp[$i]}"
        __suffix="$suffix"

        # part of display string containing match
        if [ -n "$__noquote" ]; then
            __show_str="${(Q)__hit_str}"
        else
            __show_str="${__hit_str}"
        fi
        __real_str="${__show_str}"

        if [[ -n "$__filenames" && -n "$__show_str" && -d "${file_prefix}/${__show_str}" ]]; then
            __show_str+=/
            __suffix+=/
        fi

        if [[ -z "$__disp_str" || "$__disp_str" == "$__show_str"* ]]; then
            # remove prefix from display string
            __disp_str="${__disp_str:${#__show_str}}"
        else
            # display string does not match, clear it
            __show_str=
        fi

        if [[ "$__show_str" =~ [^[:print:]] ]]; then
            __show_str="${(q)__show_str}"
        fi
        if [[ "$__disp_str" =~ [^[:print:]] ]]; then
            __disp_str="${(q)__disp_str}"
        fi
        __disp_str=$'\x1b[37m'"$__disp_str"$'\x1b[0m'
        # use display as fallback
        if [[ -z "$__show_str" ]]; then
            __show_str="$__disp_str"
            __disp_str=
        fi

        # pad out so that e.g. short flags with long display strings are not penalised
        printf -v __disp_str "%-${padding}s" "$__disp_str"

        if [[ "$__show_str" == "$PREFIX"* ]]; then
            __show_str="${PREFIX}${_FZF_COMPLETION_SEP}${__show_str:${#PREFIX}}"
        else
            __show_str="${_FZF_COMPLETION_SEP}$__show_str"
        fi

        # fullvalue, value, index, prefix, show, display
        printf %s\\n "${(q)prefix}${(q)__real_str}${(q)__suffix}${_FZF_COMPLETION_SEP}${(q)__hit_str}${_FZF_COMPLETION_SEP}${__comp_index}${_FZF_COMPLETION_SEP}${__show_str}${_FZF_COMPLETION_SEP}${__disp_str}" >&"${__stdout}"
    done
    return "$code"
}

zle -C fzf_completion complete-word fzf_completion
fzf_default_completion=fzf_completion

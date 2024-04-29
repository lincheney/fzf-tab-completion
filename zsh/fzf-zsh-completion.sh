# set ft=zsh

# use a whitespace char or anchors don't work
_FZF_COMPLETION_SEP=$'\u00a0'
_FZF_COMPLETION_SPACE_SEP=$'\v'
_FZF_COMPLETION_NONSPACE=$'\u00ad'
_FZF_COMPLETION_FLAGS=( a k f q Q e n U l 1 2 C )
_FZF_COMPLETION_KEYBINDINGS=50

zmodload zsh/zselect
zmodload zsh/system

_fzf_bash_completion_awk="$( builtin command -v gawk &>/dev/null && echo gawk || echo awk )"
_fzf_bash_completion_grep="$( builtin command -v ggrep &>/dev/null && echo ggrep || echo grep )"

repeat-fzf-completion() {
    __repeat=1
    __query="$1"
}

fzf_completion() {
    local __repeat=1 __code= __action= __query=
    while (( __repeat )); do
        __code=
        __repeat=0
        __action=
        # run the actual completion widget
        zle _fzf_completion

        if [[ -n "$__action" ]]; then
            eval "$__action"
            zle reset-prompt
        fi
    done
}

_fzf_completion() {
    emulate -LR zsh +o ALIASES
    setopt interactivecomments
    local __value= __stderr=
    local __compadd_args=()

    __code=
    __stderr=
    if zstyle -t ':completion:' show-completer; then
        zle -R 'Loading matches ...'
    fi

    eval "$(
    local _fzf_sentinel1=b5a0da60-3378-4afd-ba00-bc1c269bef68
    local _fzf_sentinel2=257539ae-7100-4cd8-b822-a1ef35335e88
    (
        # set -o pipefail
        # hacks
        __override_compadd() { compadd() { _fzf_completion_compadd "$@"; }; }
        __override_compadd
        # some completions change zstyle so need to propagate that out
        zstyle() { _fzf_completion_zstyle "$@"; }

        # massive hack
        # _approximate also overrides _compadd, so we have to override their one
        __override_approximate() {
            functions[_approximate]="unfunction compadd; { ${functions[_approximate]//builtin compadd /_fzf_completion_compadd } } always { __override_compadd }"
        }

        if [[ "$functions[_approximate]" == 'builtin autoload'* ]]; then
            _approximate() {
                unfunction _approximate
                printf %s\\n "builtin autoload +XUz _approximate" >&"${__evaled}"
                builtin autoload +XUz _approximate
                __override_approximate
                _approximate "$@"
            }
        else
            __override_approximate
        fi

        # all except autoload functions
        local __full_variables="$(typeset -p)"
        local __full_functions="$(functions + | "$_fzf_bash_completion_grep" -F -vx -e "$(functions -u +)")"
        local __autoload_variables="$(typeset + | "$_fzf_bash_completion_grep" -F -e 'undefined ' | "$_fzf_bash_completion_awk" '{print $NF}')"

        # do not allow grouping, it stuffs up display strings
        builtin zstyle ":completion:*:*" list-grouped no

        local curcontext="${curcontext:-}"
        local _FZF_COMPLETION_CONTEXT
        _FZF_COMPLETION_CONTEXT="${compstate[context]//_/-}"
        _FZF_COMPLETION_CONTEXT="${_FZF_COMPLETION_CONTEXT:+-$_FZF_COMPLETION_CONTEXT-}"

        if [[ "$_FZF_COMPLETION_CONTEXT" = -value- ]]; then
            _FZF_COMPLETION_CONTEXT="${_FZF_COMPLETION_CONTEXT:-*}:${compstate[parameter]}:"
        else
            if [[ "$_FZF_COMPLETION_CONTEXT" == -command- && "$CURRENT" > 1 ]]; then
                _FZF_COMPLETION_CONTEXT="${words[1]}"
            fi
            _FZF_COMPLETION_CONTEXT="${_FZF_COMPLETION_CONTEXT:-*}::${(j-,-)words[@]}"
        fi
        _FZF_COMPLETION_CONTEXT=":completion:${curcontext}:complete:$_FZF_COMPLETION_CONTEXT"

        local _FZF_COMPLETION_SEARCH_DISPLAY=0
        if builtin zstyle -t "$_FZF_COMPLETION_CONTEXT" fzf-search-display; then
            _FZF_COMPLETION_SEARCH_DISPLAY=1
        fi

        set -o monitor +o notify
        exec {__evaled}>&1
        trap '' INT
        coproc (
            (
                local __comp_index=0 __autoloaded=()
                exec {__stdout}>&1
                __stderr="$(
                    _fzf_completion_preexit() {
                        trap -
                        functions + | "$_fzf_bash_completion_grep"  -F -vx -e "$(functions -u +)" -e "$__full_functions" | while read -r f; do which -- "$f"; done >&"${__evaled}"
                        # skip local and autoload vars
                        { typeset -p -- $(typeset + | "$_fzf_bash_completion_grep" -vF -e 'local ' -e 'undefined ' | "$_fzf_bash_completion_awk" '{print $NF}' | "$_fzf_bash_completion_grep" -vFx -e "$__autoload_variables") | "$_fzf_bash_completion_grep" -xvFf <(printf %s "$__full_variables") >&"${__evaled}" } 2>/dev/null
                    }
                    trap _fzf_completion_preexit EXIT TERM

                    # Attempt shell expansion on the current word.  If that fails, attempt completion.
                    if [[ -z "${words[CURRENT]}" ]] || (
                        # produce only one big expansion (instead of individual entries)
                        builtin zstyle ':completion:*' tag-order all-expansions
                        # manually invoke _expand here
                        _expand 2>&1
                        (( compstate[nmatches] == 0 ))
                    ); then
                        _main_complete 2>&1
                    fi

                )"
                printf "__stderr='%s'\\n" "${__stderr//'/'\''}" >&"${__evaled}"
                # if a process forks and it holds onto the stdout handles, we may end up blocking waiting for it to close it
                # instead, the sed q below will quit as soon as it gets a blank line without waiting
                printf '%s\n' "$_FZF_COMPLETION_SEP$_fzf_sentinel1$_fzf_sentinel2"
            # need to get awk to be unbuffered either by using -W interactive or system("")
            ) | sed -un "/$_fzf_sentinel1$_fzf_sentinel2/q; p" \
              | "$_fzf_bash_completion_awk" -W interactive -F"$_FZF_COMPLETION_SEP" '/^$/{exit}; $1!="" && !x[$1]++ { print $0; system("") }' 2>/dev/null
        )
        coproc_pid="$!"
        __value="$(_fzf_completion_selector "$__code" <&p)"
        __code="$?"
        kill -- -"$coproc_pid" 2>/dev/null && wait "$coproc_pid"

        printf "__code='%s'; __value='%s'\\n" "${__code//'/'\''}" "${__value//'/'\''}"
        printf '%s\n' ": $_fzf_sentinel1$_fzf_sentinel2"
    ) | sed -un "/$_fzf_sentinel1$_fzf_sentinel2/q; p"
    )" 2>/dev/null

    compstate[insert]=unambiguous
    case "$__code" in
        $_FZF_COMPLETION_KEYBINDINGS)
            if (( __code == _FZF_COMPLETION_KEYBINDINGS )); then
                __action="$(head -n1 <<<"$__value")"
                if [[ "$__action" == accept:* ]]; then
                    __action="${__action#accept:}"
                    __code=0
                fi
            fi
            ;|
        0|$_FZF_COMPLETION_KEYBINDINGS)
            local opts= index= value
            while IFS="$_FZF_COMPLETION_SEP" read -r -A value; do
                if (( !__code && ${#value[@]} >= 3 )); then
                    index="${value[3]}"
                    opts="${__compadd_args[$index]}"
                    value=( "${(Q)value[2]}" )
                    eval "$opts -a value"
                fi
            done <<<"$__value"
            # insert everything added by fzf
            compstate[insert]=all
            ;;
        1)
            # run all compadds with no matches, in case any messages to display
            eval "${(j.;.)__compadd_args:-true} --"
            if (( ! ${#__compadd_args[@]} )) && zstyle -s :completion:::::warnings format msg; then
                compadd -x "$msg"
            fi
            compadd -x "$__stderr"
            __stderr=
            ;;
    esac

    # reset-prompt doesn't work in completion widgets
    # so call it after this function returns
    eval "TRAPEXIT() {
        zle reset-prompt
        _fzf_completion_post ${(q)__stderr} ${(q)__code}
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
            __query+="$REPLY"
        fi
    done

    local field=2
    if (( _FZF_COMPLETION_SEARCH_DISPLAY )); then
        field=2,3
    fi

    local flags=() keybinds=()
    zstyle -a "$_FZF_COMPLETION_CONTEXT" fzf-completion-opts flags
    zstyle -a "$_FZF_COMPLETION_CONTEXT" fzf-completion-keybindings keybinds
    while IFS=: read -r key action; do
        flags+=( --bind "$key:become:printf %s%q\\\\n ${(q)action}\\  {q} {+}; exit $_FZF_COMPLETION_KEYBINDINGS" )
    done < <( (( ${#keybinds[@]} )) && printf %s\\n "${keybinds[@]}")
    if [[ -n "$__query" ]]; then
        flags+=( --query="$__query" )
    fi

    tput cud1 >/dev/tty # fzf clears the line on exit so move down one
    # fullvalue, value, index, display, show, prefix
    FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        $(__fzfcmd 2>/dev/null || echo fzf) --ansi --prompt "> $PREFIX" -d "[${_FZF_COMPLETION_SEP}${_FZF_COMPLETION_SPACE_SEP}]" --with-nth 6,5,4 --nth "$field" "${flags[@]}" \
        < <( (( ${#lines[@]} )) && printf %s\\n "${lines[@]}"; cat)
    code="$?"
    tput cuu1 >/dev/tty
    return "$code"
}

_fzf_completion_zstyle() {
    if [[ "$1" != -* ]]; then
        { printf 'zstyle %q ' "$@"; printf \\n } >&"${__evaled}"
    fi
    builtin zstyle "$@"
}

_fzf_completion_compadd() {
    local __flags=()
    local __OAD=()
    local __disp __hits __ipre __apre __hpre __hsuf __asuf __isuf __opts __optskv
    zparseopts -D -a __opts -A __optskv -- "${^_FZF_COMPLETION_FLAGS[@]}+=__flags" F+: P:=__apre S:=__asuf o+:: p:=__hpre s:=__hsuf i:=__ipre I:=__isuf W+: d:=__disp J+: V+: X+: x+: r+: R+: D+: O+: A+: E+: M+:
    local __filenames="${__flags[(r)-f]}"
    local __noquote="${__flags[(r)-Q]}"
    local __is_param="${__flags[(r)-e]}"
    local __no_matching="${__flags[(r)-U]}"

    if [ -n "${__optskv[(i)-A]}${__optskv[(i)-O]}${__optskv[(i)-D]}" ]; then
        # handle -O -A -D
        builtin compadd "${__flags[@]}" "${__opts[@]}" "${__ipre[@]}" "${__hpre[@]}" -- "$@"
        return "$?"
    fi

    if [[ "${__disp[2]}" =~ '^\(((\\.|[^)])*)\)' ]]; then
        IFS=$' \t\n\0' read -A __disp <<<"${match[1]}"
    else
        __disp=( "${(@P)__disp[2]}" )
    fi

    builtin compadd -Q -A __hits -D __disp "${__flags[@]}" "${__opts[@]}" "${__ipre[@]}" "${__apre[@]}" "${__hpre[@]}" "${__hsuf[@]}" "${__asuf[@]}" "${__isuf[@]}" -- "$@"
    # have to run it for real as some completion functions check compstate[nmatches]
    builtin compadd $__no_matching -a __hits
    local __code="$?"
    __flags="${(j..)__flags//[ak-]}"
    if [ -z "${__optskv[(i)-U]}" ]; then
        # -U ignores $IPREFIX so add it to -i
        __ipre[2]="${IPREFIX}${__ipre[2]}"
        __ipre=( -i "${__ipre[2]}" )
        IPREFIX=
    fi
    local compadd_args="$(printf '%q ' PREFIX="$PREFIX" IPREFIX="$IPREFIX" SUFFIX="$SUFFIX" ISUFFIX="$ISUFFIX" compadd ${__flags:+-$__flags} "${__opts[@]}" "${__ipre[@]}" "${__apre[@]}" "${__hpre[@]}" "${__hsuf[@]}" "${__asuf[@]}" "${__isuf[@]}" -U)"
    printf "__compadd_args+=( '%s' )\n" "${compadd_args//'/'\\''}" >&"${__evaled}"
    (( __comp_index++ ))

    local file_prefix="${__optskv[-W]:-.}"
    local __disp_str __hit_str __show_str __real_str __suffix

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
        # use display as fallback
        if [[ -z "$__show_str" ]]; then
            __show_str="$__disp_str"
            __disp_str=
        elif (( ! _FZF_COMPLETION_SEARCH_DISPLAY )); then
            __disp_str=$'\x1b[37m'"$__disp_str"$'\x1b[0m'
        fi

        if [[ "$__show_str" == "$PREFIX"* ]]; then
            __show_str="${__show_str:${#PREFIX}}${_FZF_COMPLETION_SPACE_SEP}"$'\x1b[37m'"${PREFIX}"$'\x1b[0m'
        else
            __show_str+="${_FZF_COMPLETION_SEP}"
        fi

        # fullvalue, value, index, display, show, prefix
        printf %s\\n "${(q)prefix}${(q)__real_str}${(q)__suffix}${_FZF_COMPLETION_SEP}${(q)__hit_str}${_FZF_COMPLETION_SEP}${__comp_index}${_FZF_COMPLETION_SEP}${__disp_str}${_FZF_COMPLETION_SEP}${__show_str}${_FZF_COMPLETION_SPACE_SEP}" >&"${__stdout}"
    done
    return "$__code"
}

zle -C _fzf_completion complete-word _fzf_completion
zle -N fzf_completion
fzf_default_completion=fzf_completion

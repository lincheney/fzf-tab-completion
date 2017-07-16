_fzf_bash_completion_dir="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

_fzf_bash_completion_sed_escape() {
    sed 's/[.[\*^$\/]/\\&/g' <<<"$1"
}

_fzf_bash_completion_getpos() {
    printf '\e[6n' > /dev/tty
    IFS=';' read -r -d R -a pos
    echo "$(( ${pos[0]/#*[/} )) $(( pos[1] ))"
}

fzf_bash_completion() {
    # draw first to minimise flicker
    local READLINE_FULL_LINE="$( (echo "${PS1@P}") 2>/dev/null )${READLINE_LINE}"
    printf '\e[s%s' "$READLINE_FULL_LINE"
    local postprint=( $(_fzf_bash_completion_getpos) )
    printf '\e[u'
    local initial=( $(_fzf_bash_completion_getpos) )
    printf '\e[%i;%iH' "${postprint[@]}" >/dev/tty

    local find_cmd="${_fzf_bash_completion_dir}/find-cmd/target/release/find-cmd"
    read start end rest < <("$find_cmd")
    local point="$(( READLINE_POINT - start ))"
    local line="${READLINE_LINE:$start:$end-$start}"
    local first=( ${line::$point} )
    local COMP_WORDS=( $line )
    if [[ "$point" = 0 || "${line:$point-1:1}" = ' ' ]]; then
        first+=( '' )
    fi
    local COMP_CWORD="$(( ${#first[@]}-1 ))"
    local COMP_POINT="$point"
    local COMP_LINE="$line"

    _fzf_bash_completion_expand_alias "${COMP_WORDS[0]}"
    local cmd="${COMP_WORDS[0]}"
    local prev
    if [ "$COMP_CWORD" = 0 ]; then
        prev=
    else
        prev="${COMP_WORDS[$COMP_CWORD-1]}"
    fi
    local cur="${COMP_WORDS[$COMP_CWORD]}"
    local COMP_WORD_START="${first[-1]}"
    local COMP_WORD_END="${cur:${#cur_start}}"

    local COMPREPLY=
    fzf_bash_completer "$cmd" "$COMP_WORD_START" "$prev"
    if [ -n "$COMPREPLY" ]; then
        READLINE_LINE="${READLINE_LINE::$READLINE_POINT-${#COMP_WORD_START}}${COMPREPLY}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT="$(( $READLINE_POINT+${#COMPREPLY}-${#COMP_WORD_START} ))"
    fi

    # restore initial cursor position
    if [ "$((postprint[0]-initial[0]))" != 0 ]; then
        printf '\e[%iA' "$((postprint[0]-initial[0]))"
    fi
    printf '\r'
}

fzf_bash_completer() {
    _fzf_bash_completion_default "$@"
}

fzf_bash_completion_selector() {
    local input="$(sed -r "s/^.{${#2}}/&\x7f/")"
    _fzf_bash_completion_fzf "$@" | tr -d $'\x7f'
}

_fzf_bash_completion_fzf() {
    # print to tmpfile if there is only one option left
    exec {tmp}>&1
    local command='[ "$(<<<"$input" fzf -f {q} | wc -l)" = 1 ] && (echo {} >&"$tmp"; kill $PPID)'

    <<<"$input" \
    input="$input" tmp="$tmp" \
    FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS -d '\x7f' --nth 2" \
        fzf -1 -0 --bind=tab:execute-silent"@$command@" --prompt "> $2" >&"$tmp"
}

_fzf_bash_completion_expand_alias() {
    if alias "$1" &>/dev/null; then
        value=( ${BASH_ALIASES[$1]} )
        if [ -n "${value[*]}" -a "${value[0]}" != "$1" ]; then
            COMP_WORDS=( "${value[@]}" "${COMP_WORDS[@]:1}" )
            COMP_CWORD="$(( COMP_CWORD + ${#value[@]} - 1 ))"
            COMP_LINE="$(<<<"$COMP_LINE" sed "s/^$(_fzf_bash_completion_sed_escape "$1")/$(_fzf_bash_completion_sed_escape "${BASH_ALIASES[$1]}")/")"
            COMP_POINT="$(( COMP_POINT + ${#BASH_ALIASES[$1]} - ${#1} ))"
        fi
    fi
}

_fzf_bash_completion_get_results() {
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        local brace="${BASH_REMATCH[1]}"
        local filter="${BASH_REMATCH[2]}"
        if [ -n "$filter" ]; then
            local prefix="${2:: -${#filter}}"
        else
            local prefix="$2"
        fi
        COMPREPLY="$(compgen -v -P "$prefix" -S "${brace:+\}}" -- "$filter")"
    elif [ "$COMP_CWORD" == 0 ]; then
        COMPREPLY="$(compgen -abc -- "$2")"
    else
        _fzf_bash_completion_complete "$@"
    fi
}

_fzf_bash_completion_default() {
    local results
    local compl_bashdefault compl_default compl_dirnames compl_filenames compl_noquote compl_nosort compl_nospace compl_plusdirs

    # hack: hijack compopt
    compopt() { _fzf_bash_completion_compopt "$@"; }
    _fzf_bash_completion_get_results "$@"
    while [ "$?" = 124 ]; do
        _fzf_bash_completion_get_results "$@"
    done
    # remove compopt hack
    unset compopt

    if [ -z "$COMPREPLY" ]; then
        local compgen_opts=()
        [ "$compl_bashdefault" = 1 ] && compgen_opts+=( -o bashdefault )
        [ "$compl_default" = 1 ] && compgen_opts+=( -o default )
        [ "$compl_dirnames" = 1 ] && compgen_opts+=( -o dirnames )
        if [ -n "${compgen_opts[*]}" ]; then
            COMPREPLY="$(compgen "${compgen_opts[@]}" -- "$2")"
        fi
    fi

    if [ "$compl_plusdirs" = 1 ]; then
        COMPREPLY+="${COMPREPLY:+$'\n'}$(compgen -o dirnames -- "$2")"
    fi

    compl_filenames="${compl_filenames}${compl_plusdirs}${compl_dirnames}"
    if [[ "$compl_filenames" == *1* ]]; then
        local dir_marker="${_fzf_bash_completion_dir}/dir-marker/target/release/dir-marker"
        COMPREPLY="$("$dir_marker" <<<"$COMPREPLY")"
    fi

    COMPREPLY="$(<<<"$COMPREPLY" sort -u | fzf_bash_completion_selector "$1" "${2#[\"\']}" "$3" )"
    [ -z "$COMPREPLY" ] && return
    if [ "$compl_noquote" != 1 -a "$compl_filenames" = 1 ]; then
        if [ "${COMPREPLY::1}" = '~' -a -z "$quotes" ]; then
            # don't quote the tilde
            printf -v COMPREPLY '~%q' "${COMPREPLY:1}"
        else
            printf -v COMPREPLY %q "${COMPREPLY:${#quotes}}"
        fi
    fi
    [ "$compl_nospace" != 1 ] && COMPREPLY="$COMPREPLY "
    [[ "$compl_filenames" == *1* ]] && COMPREPLY="${COMPREPLY/%\/ //}"
}

_fzf_bash_completion_complete() {
    local compgen_actions=()
    local compspec="$(complete -p "$1" 2>/dev/null)"

    if [ -z "$compspec" ]; then
        _completion_loader "$@"
        compspec="$(complete -p "$1" 2>/dev/null || complete -p '')"
    fi

    set -- $compspec "$@"
    shift
    while [ "$#" -gt 4 ]; do
        if [ "$1" = -F ]; then
            local compl_function="$2"
            shift
        elif [ "$1" = -C ]; then
            local compl_command="$(eval "echo $2")"
            shift
        elif [ "$1" = -G ]; then
            local compl_globpat="$2"
            shift
        elif [ "$1" = -W ]; then
            local compl_wordlist="$2"
            shift
        elif [ "$1" = -X ]; then
            local compl_xfilter="$2"
            shift
        elif [ "$1" = -o ]; then
            _fzf_bash_completion_compopt -o "$2"
            shift
        elif [ "$1" = -A ] ; then
            local compgen_opts+=( "$1" "$2" )
            shift
        elif [ "$1" = -P ]; then
            local compl_prefix="$(_fzf_bash_completion_sed_escape "$2")"
            shift
        elif [ "$1" = -S ]; then
            local compl_suffix="$(_fzf_bash_completion_sed_escape "$2")"
            shift
        elif [[ "$1" =~ -[a-z] ]]; then
            compgen_actions+=( "$1" )
        fi
        shift
    done
    shift

    COMPREPLY=()
    if [ -n "$compl_function" ]; then
        "$compl_function" "$@" >/dev/null
        if [ "$?" = 124 ]; then
            local newcompspec="$(complete -p "$1" 2>/dev/null || complete -p '')"
            if [ "$newcompspec" != "$compspec" ]; then
                return 124
            fi
        fi
    fi

    COMPREPLY="$(
        (
            if [ -n "${compgen_actions[*]}" ]; then
                compgen "${compgen_opts[@]}" -- "$2"
            fi

            if [ -n "$compl_globpat" ]; then
                printf %s\\n "$compl_globpat"
            fi

            if [ -n "$compl_wordlist" ]; then
                eval "printf '%s\\n' $compl_wordlist"
            fi

            if [ -n "${COMPREPLY[*]}" ]; then
                printf %s\\n "${COMPREPLY[@]}"
            fi

            if [ -n "$compl_command" ]; then
                COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" COMP_KEY="$COMP_KEY" COMP_TYPE="$COMP_TYPE" \
                    $compl_command "$@"
            fi
        ) | _fzf_bash_completion_apply_xfilter "$compl_xfilter" \
          | sed "s/.*/${compl_prefix}&${compl_suffix}/"
    )"
}

_fzf_bash_completion_apply_xfilter() {
    local pattern line
    if [ "${1::1}" = ! ]; then
        pattern="$(sed -r 's/((^|[^\])(\\\\)*)&/\1x/g' <<<"${1:1}")"
        while IFS= read -r line; do [[ "$line" != $pattern ]] && echo "$line"; done
    elif [ -n "$1" ]; then
        pattern="$(sed -r 's/((^|[^\])(\\\\)*)&/\1x/g' <<<"$1")"
        while IFS= read -r line; do [[ "$line" == $pattern ]] && echo "$line"; done
    else
        cat
    fi
}

_fzf_bash_completion_compopt() {
    while [ "$#" -gt 0 ]; do
        local val
        if [ "$1" = -o ]; then
            val=1
        elif [ "$1" = +o ]; then
            val=0
        else
            break
        fi

        if [[ "$2" =~ bashdefault|default|dirnames|filenames|noquote|nosort|nospace|plusdirs ]]; then
            eval "compl_$2=$val"
        fi
        shift 2
    done
}

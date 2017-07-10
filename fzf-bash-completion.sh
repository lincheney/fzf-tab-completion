# TODO: aliases, completion loading

_fzf_bash_completion_sed_escape() {
    sed 's/[.[\*^$\/]/\\&/g' <<<"$1"
}

_fzf_bash_completion_getpos() {
    printf '\e[6n' > /dev/tty
    IFS=';' read -r -d R -a pos
    echo "$(( ${pos[0]:2} )) $(( pos[1] ))"
}

fzf_bash_completion() {
    # draw first to minimise flicker
    printf '\e[s%s' "${PS1@P}$READLINE_LINE"
    local postprint=( $(_fzf_bash_completion_getpos) )
    printf '\e[u'
    local initial=( $(_fzf_bash_completion_getpos) )
    printf '\e[%i;%iH' "${postprint[@]}"

    local find_cmd="$(dirname "${BASH_SOURCE[0]}")/find-cmd/target/release/find-cmd"
    read start end rest < <("$find_cmd")
    local point="$(( READLINE_POINT - start ))"
    local line="${READLINE_LINE:$start:$end-$start}"
    local first=( ${line::$point} )
    local COMP_WORDS=( $line )
    if [ "$point" = 0 -o "${line:$point-1:1}" = ' ' ]; then
        first+=( '' )
    fi
    local COMP_CWORD="$(( ${#first[@]}-1 ))"
    local COMP_POINT="$point"
    local COMP_LINE="$line"
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
    fzf_bash_completer "$cmd" "$cur" "$prev"
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
    sed -r "s/^.{${#COMP_WORD_START}}/&\x7f/" | \
        FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" fzf -1 -0 --bind=space:accept +e --prompt "> $COMP_WORD_START" -d '\x7f' --nth 2 | \
        tr -d $'\x7f'
}

_fzf_bash_completion_get_results() {
    if [[ "$COMP_WORD_START" =~ .*\$\{?([A-Za-z0-9_]*)$ ]]; then
        local filter="${BASH_REMATCH[1]}"
        if [ -n "$filter" ]; then
            local prefix="${COMP_WORD_START:: -${#filter}}"
        else
            local prefix="$COMP_WORD_START"
        fi
        readarray -t COMPREPLY < <(compgen -v -P "$prefix" -- "$filter")
    elif [ "$COMP_CWORD" == 0 ]; then
        readarray -t COMPREPLY < <(compgen -abc -- "$2")
    else
        _fzf_bash_completion_complete "$@"
    fi
}

_fzf_bash_completion_default() {
    local results

    # hack: hijack compopt
    compopt() { _fzf_bash_completion_compopt "$@"; }

    _fzf_bash_completion_get_results "$@"

    # remove compopt hack
    unset compopt

    COMPREPLY="$(printf %s\\n "${COMPREPLY[@]}")"
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
        COMPREPLY+=$'\n'"$(compgen -o dirnames -- "$2")"
    fi

    compl_filenames="${compl_filenames}${compl_plusdirs}${compl_dirnames}"
    if [[ "$compl_filenames" == *1* ]]; then
        COMPREPLY="$(
            while IFS= read line; do
                [ -d "$line" ] && line="$line/"
                echo "$line"
            done <<<"$COMPREPLY"
        )"
    fi

    COMPREPLY="$(<<<"$COMPREPLY" sort -u | fzf_bash_completion_selector "$@")"
    [ -z "$COMPREPLY" ] && return
    [ "$compl_noquote" != 1 -a "$compl_filenames" = 1 ] && choice="$(printf %q "$choice")"
    [ "$compl_nospace" != 1 ] && choice="$choice "
    [[ "$compl_filenames" == *1* ]] && choice="${choice/%\/ //}"
}

_fzf_bash_completion_complete() {
    local compgen_actions=()
    local compspec="$(complete -p "$1" 2>/dev/null || complete -p '')"
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
            if [[ "$2" =~ bashdefault|default|dirnames|filenames|noquote|nosort|nospace|plusdirs ]]; then
                eval "local compl_$2=1"
            fi
        elif [ "$1" = -A ] ; then
            local compgen_opts+=( "$1" "$2" )
            shift
        elif [ "$1" = -P ]; then
            local compl_prefix="$(_sed_escape "$2")"
            shift
        elif [ "$1" = -S ]; then
            local compl_suffix="$(_sed_escape "$2")"
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

            printf %s\\n "${COMPREPLY[@]}"

            if [ -n "$compl_command" ]; then
                COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" COMP_KEY="$COMP_KEY" COMP_TYPE="$COMP_TYPE" \
                    $compl_command "$@"
            fi
        ) | _fzf_bash_completion_apply_xfilter "$compl_xfilter" \
          | sed "s/.*/${compl_prefix}&${compl_suffix}/"
    )"
    readarray -t COMPREPLY <<<"$COMPREPLY"
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

_FZF_COMPLETION_SEP=$'\x7f'

_fzf_bash_completion_sed_escape() {
    sed 's/[.[\*^$\/]/\\&/g' <<<"$1"
}

# shell parsing stuff
_fzf_bash_completion_egrep="$(command -v rg || command -v ag || echo egrep)"

_fzf_bash_completion_shell_split() {
    "$_fzf_bash_completion_egrep" -o -e ';|\(|\)|\{|\}' -e "(\\\\.|[^\"'[:space:];(){}])+" -e "\\\$'(\\\\.|[^'])*('|$)" -e "'[^']*('|$)" -e "\"(\\\\.|\\\$(\$|[^(])|[^\"\$])*(\"|\$)" -e '".*' -e .
}

_fzf_bash_completion_flatten_subshells() {
    (
        local count=0 buffer=
        tac | while IFS= read -r line; do
            case "$line" in
                \(|\{) (( count -- )) ;;
                \)|\}) (( count ++ )) ;;
            esac

            if (( count < 0 )); then
                return
            elif (( count > 0 )); then
                buffer="$line$buffer"
            else
                echo "$line$buffer"
                buffer=
            fi
        done
        echo -n "$buffer"
    ) | tac
}

_fzf_bash_completion_find_matching_bracket() {
    local count=0
    while IFS=: read num bracket; do
        if [ "$bracket" = "$1" ]; then
            (( count++ ))
            if (( count > 0 )); then
                echo "$num"
                return 0
            fi
        else
            (( count -- ))
        fi
    done < <(fgrep $'(\n)' -n)
    return 1
}

_fzf_bash_completion_parse_dq() {
    local words="$(cat)"
    local last="$(<<<"$words" tail -n1)"

    if [[ "$last" == \"* ]]; then
        local shell="${last:1}" _shell joined
        local word=
        while true; do
            # we are in a double quoted string
            _shell="$(<<<"$shell" sed -r 's/^(\\.|[^"$])*\$\(//')"
            echo "$_shell" >/dev/tty

            if [ "$shell" = "$_shell" ]; then
                # no subshells
                break
            fi

            word+="${shell:0:-${#_shell}-2}"
            shell="$_shell"

            # found a subshell
            split="$(<<<"$shell" shell_split)"
            if ! split="$(parse_dq "$split")"; then
                # bubble up
                echo "$split"
                return 1
            fi
            if ! num="$(find_matching_bracket ')' <<<"$split")"; then
                # subshell not closed, this is it
                echo "$split"
                return 1
            fi
            # subshell closed
            joined="$(<<<"$split" head -n "$num" | tr -d \\n)"
            word+=$'\n'"\$($joined"$'\n'
            shell="${shell:${#joined}}"
        done
    fi
    echo "$words"
}

_fzf_bash_completion_parse_line() {
    _fzf_bash_completion_shell_split \
        | _fzf_bash_completion_parse_dq \
        | _fzf_bash_completion_flatten_subshells \
        | tr \\n \\0 | sed -r 's/\x00\s*\x00/\n/g; s/\x00(\S|$)/\1/g; s/\x00(\s*)$/\n\1/' \
        | tr \\n \\0 | sed -r "s/^(.*\\x00)?(\\[\\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while|;|&&|\\|[|&]?)\\x00//" \
        | sed -r 's/^(\s*\x00|\w+=[^\x00]*\x00)*//' \
        | tr \\0 \\n
}

fzf_bash_completion() {
    local COMP_WORDS COMP_CWORD COMP_POINT COMP_LINE
    local line="${READLINE_LINE:0:READLINE_POINT}"
    readarray -t COMP_WORDS < <(_fzf_bash_completion_parse_line <<<"$line")

    if [[ "${#COMP_WORDS[@]}" = 0 || "$line" =~ .*[[:space:]]$ ]]; then
        COMP_WORDS+=( '' )
    fi
    COMP_CWORD="${#COMP_WORDS[@]}"
    (( COMP_CWORD-- ))

    COMP_LINE="${COMP_WORDS[*]}"
    COMP_POINT="${#COMP_LINE}"

    _fzf_bash_completion_expand_alias "${COMP_WORDS[0]}"
    local cmd="${COMP_WORDS[0]}"
    local prev
    if [ "$COMP_CWORD" = 0 ]; then
        prev=
    else
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    local cur="${COMP_WORDS[COMP_CWORD]}"

    local COMPREPLY=
    fzf_bash_completer "$cmd" "$cur" "$prev"
    if [ -n "$COMPREPLY" ]; then
        if [ -n "$cur" ]; then
            line="${line::-${#cur}}"
        fi
        READLINE_LINE="${line}${COMPREPLY}${READLINE_LINE:$READLINE_POINT}"
        (( READLINE_POINT+=${#COMPREPLY} - ${#cur} ))
    fi

    printf '\r'
}

_fzf_bash_completion_selector() {
    sed -r "s/^.{${#2}}/&$_FZF_COMPLETION_SEP/" \
    | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        fzf -1 -0 --prompt "> $line" --nth 2 -d "$_FZF_COMPLETION_SEP" \
    | tr -d "$_FZF_COMPLETION_SEP"
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
    local trigger="${FZF_COMPLETION_TRIGGER-**}"
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        # environment variables
        local brace="${BASH_REMATCH[1]}"
        local filter="${BASH_REMATCH[2]}"
        if [ -n "$filter" ]; then
            local prefix="${2:: -${#filter}}"
        else
            local prefix="$2"
        fi
        compgen -v -P "$prefix" -S "${brace:+\}}" -- "$filter"
    elif [ "$COMP_CWORD" == 0 ]; then
        # commands
        echo compl_filenames=1 >&"${__evaled}"
        compgen -abc -- "$2" | _fzf_bash_completion_dir_marker
    elif [[ "$2" == *"$trigger" ]]; then
        # replicate fzf ** trigger completion
        local suffix="${2##*/}"
        local prefix="${2::-${#suffix}}"
        suffix="${suffix::-${#trigger}}"

        local flags=()
        if [[ "$1" =~ cd|pushd|rmdir ]]; then
            flags=( -type d )
        fi

        if [[ ! "$prefix" =~ (.?/).* ]]; then
            prefix="./$prefix"
        elif [ "${prefix::2}" = '~/' ]; then
            prefix="${HOME}/${prefix:2}"
        fi

        # smart case
        if [ "${suffix,,}" = "${suffix}" ]; then
            flags+=( -ipath "$prefix$suffix*" )
        else
            flags+=( -path "$prefix$suffix*" )
        fi

        echo compl_filenames=1 >&"${__evaled}"
        find -L "$prefix" -mindepth 1 "${flags[@]}" \( -type d -printf "%p/\n" , -type f -print \) 2>/dev/null | sed 's,^\./,,'
    else
        _fzf_bash_completion_complete "$@"
    fi
}

fzf_bash_completer() {
    local value code
    local compl_bashdefault compl_default compl_dirnames compl_filenames compl_noquote compl_nosort compl_nospace compl_plusdirs

    # preload completions in top shell
    { complete -p "$1" || __load_completion "$1"; } &>/dev/null

    eval "$(
        set -o pipefail

        # hack: hijack compopt
        compopt() { _fzf_bash_completion_compopt "$@"; }

        exec {__evaled}>&1
        value="$(
            (
                _fzf_bash_completion_get_results "$@"
                while [ "$?" = 124 ]; do
                    _fzf_bash_completion_get_results "$@"
                done
            ) | awk '!x[$0]++' | _fzf_bash_completion_selector "$1" "${2#[\"\']}" "$3"
        )"
        code="$?"
        exec {__evaled}>&-

        printf 'COMPREPLY=%q\n' "$value"
        printf 'code=%q\n' "$code"
    )"

    if [ "$code" = 0 ]; then
        readarray -t COMPREPLY < <(
            if [ "$compl_noquote" != 1 -a "$compl_filenames" = 1 ]; then
                while read -r line; do
                    if [ "$line" = "$2" ]; then
                        echo "$line"
                    # never quote the prefix
                    elif [ "${line::${#2}}" = "$2" ]; then
                        printf '%s%q\n' "$2" "${line:${#2}}"
                    elif [ "${line::1}" = '~' ]; then
                        printf '~%q\n' "${line:1}"
                    else
                        printf '%q\n' "$line"
                    fi
                done
            else
                cat
            fi <<<"$COMPREPLY"
        )
        COMPREPLY="${COMPREPLY[*]}"
        [ "$compl_nospace" != 1 ] && COMPREPLY="$COMPREPLY "
        [[ "$compl_filenames" == *1* ]] && COMPREPLY="${COMPREPLY/%\/ //}"
    fi
}

_fzf_bash_completion_complete() {
    local compgen_actions=()
    local compspec="$(complete -p "$1" 2>/dev/null || complete -p '')"

    set -- $compspec "$@"
    shift
    while [ "$#" -gt 4 ]; do
        case "$1" in
        -F)
            local compl_function="$2"
            shift ;;
        -C)
            local compl_command="$(eval "echo $2")"
            shift ;;
        -G)
            local compl_globpat="$2"
            shift ;;
        -W)
            local compl_wordlist="$2"
            shift ;;
        -X)
            local compl_xfilter="$2"
            shift ;;
        -o)
            _fzf_bash_completion_compopt -o "$2"
            shift ;;
        -A)
            local compgen_opts+=( "$1" "$2" )
            shift ;;
        -P)
            local compl_prefix="$(_fzf_bash_completion_sed_escape "$2")"
            shift ;;
        -S)
            local compl_suffix="$(_fzf_bash_completion_sed_escape "$2")"
            shift ;;
        -[a-z])
            compgen_actions+=( "$1" )
            ;;
        esac
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
            "$compl_function" "$@" >/dev/null
        fi
    fi

    compl_filenames="${compl_filenames}${compl_plusdirs}${compl_dirnames}"
    if [[ "$compl_filenames" == *1* ]]; then
        local dir_marker=_fzf_bash_completion_dir_marker
    else
        local dir_marker=cat
    fi

    printf 'compl_filenames=%q\n' "$compl_filenames" >&"${__evaled}"
    printf 'compl_noquote=%q\n' "$compl_noquote" >&"${__evaled}"
    printf 'compl_nospace=%q\n' "$compl_nospace" >&"${__evaled}"

    (
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

            echo
        ) | _fzf_bash_completion_apply_xfilter "$compl_xfilter" \
          | sed "s/.*/${compl_prefix}&${compl_suffix}/; /./!d" \
          | if read -r line; then
                echo "$line"; cat
            else
                local compgen_opts=()
                [ "$compl_bashdefault" = 1 ] && compgen_opts+=( -o bashdefault )
                [ "$compl_default" = 1 ] && compgen_opts+=( -o default )
                [ "$compl_dirnames" = 1 ] && compgen_opts+=( -o dirnames )
                if [ -n "${compgen_opts[*]}" ]; then
                    compgen "${compgen_opts[@]}" -- "$2"
                fi
            fi

        if [ "$compl_plusdirs" = 1 ]; then
            compgen -o dirnames -- "$2"
        fi
    ) \
    | sed "s/^$(_fzf_bash_completion_sed_escape "$2")/$(_fzf_bash_completion_sed_escape "$(sed -r 's/\\(.)/\1/g' <<<"$2")")/" \
    | "$dir_marker"
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

_fzf_bash_completion_dir_marker() {
    while read -r line; do
        # adapted from __expand_tilde_by_ref
        if [[ "$line" == \~*/* ]]; then
            eval expanded="${line/%\/*}"/'${line#*/}';
        elif [[ "$line" == \~* ]]; then
            eval expanded="$line";
        fi
        [ -d "${expanded:-$line}" ] && line="$line/"
        echo "$line"
    done
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

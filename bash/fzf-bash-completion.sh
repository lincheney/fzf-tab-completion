_FZF_COMPLETION_SEP=$'\x01'

# shell parsing stuff
_fzf_bash_completion_awk="$( { which gawk || echo awk; } 2>/dev/null)"
_fzf_bash_completion_sed="$( { which gsed || echo sed; } 2>/dev/null)"

_fzf_bash_completion_awk_escape() {
    "$_fzf_bash_completion_sed" 's/\\/\\\\\\\\/g; s/[[*^$.]/\\\\&/g' <<<"$1"
}

_fzf_bash_completion_shell_split() {
    command grep -E -o \
        -e '[;(){}&\|:]' \
        -e '\|+|&+' \
        -e "(\\\\.|[^\"'[:space:];:(){}&\\|])+" \
        -e "\\\$'(\\\\.|[^'])*('|$)" \
        -e "'[^']*('|$)" \
        -e '"(\\.|\$($|[^(])|[^"$])*("|$)' \
        -e '".*' -e .
}

_fzf_bash_completion_unbuffered_awk() {
    # need to get awk to be unbuffered either by using -W interactive or system("")
    "$_fzf_bash_completion_awk" -W interactive "${@:3}" "$1 { $2; print \$0; system(\"\") }" 2>/dev/null
}

_fzf_bash_completion_flatten_subshells() {
    (
        local count=0 buffer=
        while IFS= read -r line; do
            case "$line" in
                \(|\{) (( count -- )) ;;
                \)|\}) (( count ++ )) ;;
            esac

            if (( count < 0 )); then
                return
            elif (( count > 0 )); then
                buffer="$line$buffer"
            else
                printf '%s\n' "$line$buffer"
                buffer=
            fi
        done < <(tac)
        printf '%s\n' "$buffer"
    ) | tac
}

_fzf_bash_completion_find_matching_bracket() {
    local count=0
    while IFS=: read -r num bracket; do
        if [ "$bracket" = "$1" ]; then
            (( count++ ))
            if (( count > 0 )); then
                printf '%s\n' "$num"
                return 0
            fi
        else
            (( count -- ))
        fi
    done < <(command grep -F -e '(' -e ')' -n)
    return 1
}

_fzf_bash_completion_parse_dq() {
    local words="$(cat)"
    local last="$(<<<"$words" tail -n1)"

    if [[ "$last" == \"* ]]; then
        local line="${last:1}" shell_start string_end joined num
        local word=
        while true; do
            # we are in a double quoted string

            shell_start="$(<<<"$line" command grep -E -o '^(\\.|\$[^(]|[^$])*\$\(')"
            string_end="$(<<<"$line" command grep -E -o '^(\\.|[^"])*"')"

            if (( ${#string_end} && ( ! ${#shell_start} || ${#string_end} < ${#shell_start} )  )); then
                # found end of string
                line="${line:${#string_end}}"
                printf '%s\n' "${words:0:-${#line}}"
                _fzf_bash_completion_parse_line <<<"$line"
                return

            elif (( ${#shell_start} && ( ! ${#string_end} || ${#shell_start} < ${#string_end} )  )); then
                # found a subshell

                word+="${shell_start:0:-2}"
                line="${line:${#shell_start}}"

                split="$(<<<"$line" _fzf_bash_completion_shell_split)"
                if ! split="$(_fzf_bash_completion_parse_dq <<<"$split")"; then
                    # bubble up
                    printf '%s\n' "$split"
                    return 1
                fi
                if ! num="$(_fzf_bash_completion_find_matching_bracket ')' <<<"$split")"; then
                    # subshell not closed, this is it
                    printf '%s\n' "$split"
                    return 1
                fi
                # subshell closed
                joined="$(<<<"$split" head -n "$num" | tr -d \\n)"
                word+=$'\n$('"$joined"$'\n'
                line="${line:${#joined}}"

            else
                # the whole line is an incomplete string
                break
            fi
        done
    fi
    printf '%s\n' "$words"
}

_fzf_bash_completion_parse_line() {
    _fzf_bash_completion_shell_split \
        | _fzf_bash_completion_parse_dq \
        | _fzf_bash_completion_flatten_subshells \
        | tr \\n \\0 \
        | "$_fzf_bash_completion_sed" -r "$(cat <<'EOF'
s/\x00\s*\x00/\n/g;
s/\x00(\s*)$/\n\1/;
s/([^&\n\x00])&([^&\n\x00])/\1\n\&\n\2/g;
s/([\n\x00\z])([<>]+)([^\n\x00])/\1\2\n\3/g;
s/([<>][\n\x00])$/\1\n/;
s/^(.*[\x00\n])?(\[\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while|&|;|&&|\|[|&]?)[\x00\n]//;
s/^(\s*[\n\x00]|\w+=[^\n\x00]*[\n\x00])*//
EOF
)" \
        | tr \\0 \\n
}

_fzf_bash_completion_compspec() {
    if [[ "$COMP_CWORD" == 0 && -z "$2" ]]; then
        complete -p -E || printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -E'
    elif [[ "$COMP_CWORD" == 0 ]]; then
        complete -p -I || printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -I'
    else
        complete -p -- "$1" || complete -p -D || printf '%s\n' 'complete -o filenames -F _fzf_bash_completion_fallback_completer'
    fi
}

_fzf_bash_completion_fallback_completer() {
    # fallback completion in case no compspecs loaded
    if [[ "$1" == \~* && "$1" != */* ]]; then
        # complete ~user directories
        readarray -t COMPREPLY < <(compgen -P '~' -u -- "${1#\~}")
    else
        # complete files
        readarray -t COMPREPLY < <(compgen -f -- "$1")
    fi
}

_fzf_bash_completion_complete_commands() {
    # commands
    compopt -o filenames
    readarray -t COMPREPLY < <(compgen -abc -- "$2")
}

_fzf_bash_completion_loading_msg() {
    echo 'Loading matches ...'
}

fzf_bash_completion() {
    printf '\r'
    command tput sc 2>/dev/null || echo -ne "\0337"
    printf '%s' "$(_fzf_bash_completion_loading_msg)"
    command tput rc 2>/dev/null || echo -ne "\0338"

    local COMP_WORDS COMP_CWORD COMP_POINT COMP_LINE
    local line="${READLINE_LINE:0:READLINE_POINT}"
    readarray -t COMP_WORDS < <(_fzf_bash_completion_parse_line <<<"$line")

    if [[ "${#COMP_WORDS[@]}" = 0 || "$line" =~ .*[[:space:]]$ ]]; then
        COMP_WORDS+=( '' )
    fi
    COMP_CWORD="${#COMP_WORDS[@]}"
    (( COMP_CWORD-- ))

    if [[ ${#COMP_WORDS[@]} -gt 1 ]]; then
        _fzf_bash_completion_expand_alias "${COMP_WORDS[0]}"
    fi
    COMP_LINE="${COMP_WORDS[*]}"
    COMP_POINT="${#COMP_LINE}"

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
    command tput el 2>/dev/null || echo -ne "\033[K"
}

_fzf_bash_completion_selector() {
    FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        $(__fzfcmd 2>/dev/null || echo fzf) -1 -0 --prompt "> $line" --nth 2 -d "$_FZF_COMPLETION_SEP" --ansi \
    | tr -d "$_FZF_COMPLETION_SEP"
}

_fzf_bash_completion_expand_alias() {
    if alias "$1" &>/dev/null; then
        value=( ${BASH_ALIASES[$1]} )
        if [ -n "${value[*]}" -a "${value[0]}" != "$1" ]; then
            COMP_WORDS=( "${value[@]}" "${COMP_WORDS[@]:1}" )
            COMP_CWORD="$(( COMP_CWORD + ${#value[@]} - 1 ))"
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
    elif [[ "$2" == *"$trigger" ]]; then
        # replicate fzf ** trigger completion
        local suffix="${2##*/}"
        local prefix="${2::${#2}-${#suffix}}"
        suffix="${suffix::${#suffix}-${#trigger}}"

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

        printf '%s\n' compl_filenames=1 >&"${__evaled}"
        find -L "$prefix" -mindepth 1 "${flags[@]}" \( -type d -printf "%p/\n" , -type f -print \) 2>/dev/null | "$_fzf_bash_completion_sed" 's,^\./,,'
    else
        _fzf_bash_completion_complete "$@"
    fi
}

_fzf_bash_completion_auto_common_prefix() {
    if [ "$FZF_COMPLETION_AUTO_COMMON_PREFIX" = true ]; then
        local prefix item items prefix_len prefix_is_full input_len i
        read -r prefix && items=("$prefix") || return
        prefix_len="${#prefix}"
        prefix_is_full=1 # prefix == item

        input_len="$(( ${#1} + ${#_FZF_COMPLETION_SEP} ))"

        while [ "$prefix_len" != "$input_len" ] && read -r item && items+=("$item"); do
            for ((i=$input_len; i<$prefix_len; i++)); do
                if [[ "${item:i:1}" != "${prefix:i:1}" ]]; then
                    prefix_len="$i"
                    unset prefix_is_full
                    break
                fi
            done

            if [ -z "$prefix_is_full" ] && [ -z "${item:i:1}" ]; then
                prefix_is_full=1
            fi
        done

        if [ "$prefix_len" != "$input_len" ]; then
            if [ "$FZF_COMPLETION_AUTO_COMMON_PREFIX_PART" == true ] || [ "$prefix_is_full" == 1 ]; then
                [ "${items[1]}" ] && printf 'compl_nospace=1\n'>&"${__evaled}" # no space if not only one
                tr -d "$_FZF_COMPLETION_SEP" <<< "${prefix:0:prefix_len}"
                return
            fi
        fi

        printf %s\\n "${items[@]}"
    fi

    cat
}

fzf_bash_completer() {
    local value code
    local compl_bashdefault compl_default compl_dirnames compl_filenames compl_noquote compl_nosort compl_nospace compl_plusdirs

    # preload completions in top shell
    { complete -p -- "$1" || __load_completion "$1"; } &>/dev/null

    eval "$(
        set -o pipefail

        # hack: hijack compopt
        compopt() { _fzf_bash_completion_compopt "$@"; }

        local __unquoted="${2#[\"\']}"
        exec {__evaled}>&1
        coproc (
            (
                _fzf_bash_completion_get_results "$@"
                while (( $? == 124 )); do
                    _fzf_bash_completion_get_results "$@"
                done
            ) | _fzf_bash_completion_unbuffered_awk '$0!="" && !x[$0]++' '$0 = "\x1b[37m" substr($0, 1, len) "\x1b[0m" sep substr($0, len+1)' -vlen="${#__unquoted}" -vsep="$_FZF_COMPLETION_SEP" \
              | _fzf_bash_completion_auto_common_prefix "$__unquoted"
        )
        value="$(_fzf_bash_completion_selector "$1" "$__unquoted" "$3" <&"${COPROC[0]}")"
        code="$?"
        value="$(<<<"$value" tr \\n \ )"
        value="${value% }"

        printf 'COMPREPLY=%q\n' "$value"
        printf 'code=%q\n' "$code"
        kill 0
    )"

    if [ "$code" = 0 ]; then
        COMPREPLY="${COMPREPLY[*]}"
        [ "$compl_nospace" != 1 ] && COMPREPLY="$COMPREPLY "
        [[ "$compl_filenames" == *1* ]] && COMPREPLY="${COMPREPLY/%\/ //}"
    fi
}

_fzf_bash_completion_complete() {
    local compgen_actions=()
    local compspec="$(_fzf_bash_completion_compspec "$1" 2>/dev/null)"

    eval "compspec=( $compspec )"
    set -- "${compspec[@]}" "$@"
    shift
    while [ "$#" -gt 4 ]; do
        case "$1" in
        -F)
            local compl_function="$2"
            shift ;;
        -C)
            local compl_command="$2"
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
            local compl_prefix="$(_fzf_bash_completion_awk_escape "$2")"
            shift ;;
        -S)
            local compl_suffix="$(_fzf_bash_completion_awk_escape "$2")"
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
            local newcompspec="$(_fzf_bash_completion_compspec "$1" 2>/dev/null)"
            if [ "$newcompspec" != "$compspec" ]; then
                return 124
            fi
            "$compl_function" "$@" >/dev/null
        fi
    fi

    if [[ "$compl_filenames" == 1 ]]; then
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
                (
                    unset COMP_WORDS COMP_CWORD
                    export COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" COMP_KEY="$COMP_KEY" COMP_TYPE="$COMP_TYPE"
                    eval "$compl_command"
                )
            fi

            printf '\n'
        ) | _fzf_bash_completion_apply_xfilter "$compl_xfilter" \
          | _fzf_bash_completion_unbuffered_awk '$0!=""' 'sub(find, replace)' -vfind='.*' -vreplace="$(printf %s "$compl_prefix" | "$_fzf_bash_completion_sed" 's/[&\]/\\&/g')&$(printf %s "$compl_suffix" | "$_fzf_bash_completion_sed" 's/[&\]/\\&/g')" \
          | if IFS= read -r line; then
                (printf '%s\n' "$line"; cat) | _fzf_bash_completion_quote_filenames "$@"
            else
                # got no results
                local compgen_opts=()
                [ "$compl_bashdefault" = 1 ] && compgen_opts+=( -o bashdefault )
                [ "$compl_default" = 1 ] && compgen_opts+=( -o default )
                [ "$compl_dirnames" = 1 ] && compgen_opts+=( -o dirnames )
                if [ -n "${compgen_opts[*]}" ]; then
                    compgen "${compgen_opts[@]}" -- "$2" \
                    | _fzf_bash_completion_dir_marker \
                    | compl_filenames=1 _fzf_bash_completion_quote_filenames "$@"
                fi
            fi

        if [ "$compl_plusdirs" = 1 ]; then
            compgen -o dirnames -- "$2" \
            | _fzf_bash_completion_dir_marker \
            | compl_filenames=1 _fzf_bash_completion_quote_filenames "$@"
        fi
    ) \
    | _fzf_bash_completion_unbuffered_awk '' 'sub(find, replace)' -vfind="^$(_fzf_bash_completion_awk_escape "$2")" -vreplace="$("$_fzf_bash_completion_sed" -r 's/\\(.)/\1/g; s/[&\]/\\&/g' <<<"$2")" \
    | "$dir_marker"
}

_fzf_bash_completion_apply_xfilter() {
    if [ -z "$1" ]; then
        cat
        return
    fi

    local pattern line word="$cur"
    word="${word//\//\\/}"
    word="${word//&/\\&}"
    # replace any unescaped & with the word being completed
    pattern="$("$_fzf_bash_completion_sed" 's/\(\(^\|[^\]\)\(\\\\\)*\)&/\1'"$word"'/g' <<<"${1:1}")"

    if [ "${1::1}" = ! ]; then
        while IFS= read -r line; do [[ "$line" == $pattern ]] && printf '%s\n' "$line"; done
    elif [ -n "$1" ]; then
        while IFS= read -r line; do [[ "$line" != $pattern ]] && printf '%s\n' "$line"; done
    fi
}

_fzf_bash_completion_dir_marker() {
    local line
    while IFS= read -r line; do
        # adapted from __expand_tilde_by_ref
        if [[ "$line" == \~* ]]; then
            eval "$(printf expanded=~%q "${line:1}")"
        fi
        [ -d "${expanded-"$line"}" ] && line="${line%/}/"
        printf '%s\n' "$line"
    done
}

_fzf_bash_completion_quote_filenames() {
    if [ "$compl_noquote" != 1 -a "$compl_filenames" = 1 ]; then
        local IFS line
        while IFS= read -r line; do
            if [ "$line" = "$2" ]; then
                printf '%s\n' "$line"
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

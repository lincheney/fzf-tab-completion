_FZF_COMPLETION_SEP=$'\x01'

# shell parsing stuff
_fzf_bash_completion_awk="$( builtin command -v gawk &>/dev/null && echo gawk || echo awk )"
_fzf_bash_completion_sed="$( builtin command -v gsed &>/dev/null && echo gsed || echo sed )"
_fzf_bash_completion_grep="$( builtin command -v ggrep &>/dev/null && echo ggrep || echo builtin command grep )"

_fzf_bash_completion_awk_escape() {
    "$_fzf_bash_completion_sed" 's/\\/\\\\\\\\/g; s/[[*^$.]/\\\\&/g' <<<"$1"
}

_fzf_bash_completion_shell_split() {
    $_fzf_bash_completion_grep -E -o \
        -e '\|+|&+|<+|>+' \
        -e '[;(){}&\|]' \
        -e '(\\.|\$[-[:alnum:]_*@#?$!]|(\$\{[^}]*(\}|$))|[^$\|"[:space:];(){}&<>'"'${wordbreaks}])+" \
        -e "\\\$'(\\\\.|[^'])*('|$)" \
        -e "'[^']*('|$)" \
        -e '"(\\.|\$($|[^(])|[^"$])*("|$)' \
        -e '".*' \
        -e '[[:space:]]+' \
        -e .
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
    done < <($_fzf_bash_completion_grep -F -e '(' -e ')' -n)
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

            shell_start="$(<<<"$line" $_fzf_bash_completion_grep -E -o '^(\\.|\$[^(]|[^$])*\$\(')"
            string_end="$(<<<"$line" $_fzf_bash_completion_grep -E -o '^(\\.|[^"])*"')"

            if (( ${#string_end} && ( ! ${#shell_start} || ${#string_end} < ${#shell_start} )  )); then
                # found end of string
                line="${line:${#string_end}}"
                if (( ${#line} )); then
                    printf '%s\n' "${words:0:-${#line}}"
                    _fzf_bash_completion_parse_line <<<"$line"
                else
                    printf '%s\n' "$words"
                fi
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
# collapse newlines
s/\x00\x00/\x00/g;
# leave trailing space
s/\x00(\s*)$/\n\1/;
# A & B -> (A, &, B)
s/([^&\n\x00])&([^&\n\x00])/\1\n\&\n\2/g;
# > B -> (>, B)
s/([\n\x00\z])([<>]+)([^\n\x00])/\1\2\n\3/g;
s/([<>][\n\x00])$/\1\n/;
# clear up until the a keyword starting a new command
# except the last line isn't a keyword, it may be the start of a command
s/^(.*[\x00\n])?(\[\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while|&|;|&&|\|[|&]?)\x00//;
# remove ENVVAR=VALUE
s/^(\s*[\n\x00]|\w+=[^\n\x00]*[\n\x00])*//
EOF
)" \
        | tr \\0 \\n
}

_fzf_bash_completion_compspec() {
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        printf '%s\n' 'complete -F _fzf_bash_completion_complete_variables'
    elif [[ "$COMP_CWORD" == 0 && -z "$2" ]]; then
        # If the command word is the empty string (completion attempted at the beginning of an empty line), any compspec defined with the -E option to complete is used.
        complete -p -E || { ! shopt -q no_empty_cmd_completion && printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -E'; }
    elif [[ "$COMP_CWORD" == 0 ]]; then
        complete -p -I || printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -I'
    else
       # If the command word is a full pathname, a compspec for the full pathname is searched for first.  If no compspec is found for the full pathname, an attempt is made to find a compspec for the portion following the final slash.  If those searches do not result in a compspec, any compspec defined with the -D option to complete is used as the default
        complete -p -- "$1" || complete -p -- "${1##*/}" || complete -p -D || printf '%s\n' 'complete -o filenames -F _fzf_bash_completion_fallback_completer'
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

_fzf_bash_completion_complete_variables() {
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        # environment variables
        local brace="${BASH_REMATCH[1]}"
        local filter="${BASH_REMATCH[2]}"
        if [ -n "$filter" ]; then
            local prefix="${2:: -${#filter}}"
        else
            local prefix="$2"
        fi
        readarray -t COMPREPLY < <(compgen -v -P "$prefix" -S "${brace:+\}}" -- "$filter")
    fi
}

_fzf_bash_completion_loading_msg() {
    echo 'Loading matches ...'
}

fzf_bash_completion() {
    # bail early if no_empty_cmd_completion
    if ! [[ "$READLINE_LINE" =~ [^[:space:]] ]] && shopt -q no_empty_cmd_completion; then
        return 1
    fi

    printf '\r'
    command tput sc 2>/dev/null || echo -ne "\0337"
    printf '%s' "$(_fzf_bash_completion_loading_msg)"
    command tput rc 2>/dev/null || echo -ne "\0338"

    local COMP_WORDS=() COMP_CWORD COMP_POINT COMP_LINE
    local COMP_TYPE=37 # % == indicates menu completion
    local line="${READLINE_LINE:0:READLINE_POINT}"
    local wordbreaks="$COMP_WORDBREAKS"
    wordbreaks="${wordbreaks//[]^]/\\&}"
    wordbreaks="${wordbreaks//[[:space:]]/}"
    if [[ "$line" =~ [^[:space:]] ]]; then
        readarray -t COMP_WORDS < <(_fzf_bash_completion_parse_line <<<"$line")
    fi

    if [[ ${#COMP_WORDS[@]} -gt 1 ]]; then
        _fzf_bash_completion_expand_alias "${COMP_WORDS[0]}"
    fi

    printf -v COMP_LINE '%s' "${COMP_WORDS[@]}"
    COMP_POINT="${#COMP_LINE}"
    # remove the ones that just spaces
    local i
    # iterate in reverse
    for (( i = ${#COMP_WORDS[@]}-1; i >= 0; i --)); do
        if ! [[ "${COMP_WORDS[i]}" =~ [^[:space:]] ]]; then
            COMP_WORDS=( "${COMP_WORDS[@]:0:i}" "${COMP_WORDS[@]:i+1}" )
        fi
    done
    if [[ "${#COMP_WORDS[@]}" = 0 || "$line" =~ .*[[:space:]]$ ]]; then
        COMP_WORDS+=( '' )
    fi
    COMP_CWORD="${#COMP_WORDS[@]}"
    (( COMP_CWORD-- ))

    local cmd="${COMP_WORDS[0]}"
    local prev
    if [ "$COMP_CWORD" = 0 ]; then
        prev=
    else
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ "$cur" =~ ^[$wordbreaks]$ ]]; then
        cur=
    fi

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
        fi
    fi
}

_fzf_bash_completion_auto_common_prefix() {
    if [ "$FZF_COMPLETION_AUTO_COMMON_PREFIX" = true ]; then
        local prefix item items prefix_len prefix_is_full input_len i
        read -r prefix && items=("$prefix") || return
        prefix_len="${#prefix}"
        prefix_is_full=1 # prefix == item

        input_len="$(( ${#1} ))"

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
                printf %s\\n "${prefix:0:prefix_len}"
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
    local compspec
    if ! compspec="$(_fzf_bash_completion_compspec "$@" 2>/dev/null)"; then
        return
    fi

    eval "$(
    local _fzf_sentinel1=b5a0da60-3378-4afd-ba00-bc1c269bef68
    local _fzf_sentinel2=257539ae-7100-4cd8-b822-a1ef35335e88
    (
        set -o pipefail

        # hack: hijack compopt
        compopt() { _fzf_bash_completion_compopt "$@"; }

        local __unquoted="${2#[\"\']}"
        exec {__evaled}>&1
        coproc (
            (
                count=0
                _fzf_bash_completion_complete "$@"
                while (( $? == 124 )); do
                    (( count ++ ))
                    if (( count > 32 )); then
                        echo "$1: possible retry loop" >/dev/tty
                        break
                    fi
                    _fzf_bash_completion_complete "$@"
                done
                printf '%s\n' "$_FZF_COMPLETION_SEP$_fzf_sentinel1$_fzf_sentinel2"
            ) | $_fzf_bash_completion_sed -un "/$_fzf_sentinel1$_fzf_sentinel2/q; p" \
              | _fzf_bash_completion_auto_common_prefix "$__unquoted" \
              | _fzf_bash_completion_unbuffered_awk '$0!="" && !x[$0]++' '$0 = "\x1b[37m" substr($0, 1, len) "\x1b[0m" sep substr($0, len+1)' -vlen="${#__unquoted}" -vsep="$_FZF_COMPLETION_SEP"
        )
        local coproc_pid="$COPROC_PID"
        value="$(_fzf_bash_completion_selector "$1" "$__unquoted" "$3" <&"${COPROC[0]}")"
        code="$?"
        value="$(<<<"$value" tr \\n \ )"
        value="${value% }"

        printf 'COMPREPLY=%q\n' "$value"
        printf 'code=%q\n' "$code"

        # kill descendant processes of coproc
        descend_process () {
            printf '%s\n' "$1"
            for pid in $(pgrep -P "$1"); do
                descend_process "$pid"
            done
        }
        kill -- $(descend_process "$coproc_pid") 2>/dev/null

        printf '%s\n' ": $_fzf_sentinel1$_fzf_sentinel2"
    ) | $_fzf_bash_completion_sed -un "/$_fzf_sentinel1$_fzf_sentinel2/q; p"
    )" 2>/dev/null

    if [ "$code" = 0 ]; then
        COMPREPLY="${COMPREPLY[*]}"
        [ "$compl_nospace" != 1 ] && COMPREPLY="$COMPREPLY "
        [[ "$compl_filenames" == *1* ]] && COMPREPLY="${COMPREPLY/%\/ //}"
    fi
}

_fzf_bash_completion_complete() {
    local compgen_actions=() compspec=
    if ! compspec="$(_fzf_bash_completion_compspec "$@" 2>/dev/null)"; then
        return
    fi

    local args=( "$@" )
    eval "compspec=( $compspec )"
    set -- "${compspec[@]}"
    shift # remove the complete command
    while (( $# > 1 )); do
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
    set -- "${args[@]}"

    COMPREPLY=()
    if [ -n "$compl_function" ]; then
        "$compl_function" "$@" >/dev/null
        if [ "$?" = 124 ]; then
            local newcompspec
            if ! newcompspec="$(_fzf_bash_completion_compspec "$@" 2>/dev/null)"; then
                return
            elif [ "$newcompspec" != "$compspec" ]; then
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
                compgen "${compgen_actions[@]}" -- "$2"
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
                # don't double invoke fzf
                if [ -n "${compgen_opts[*]}" ]; then
                    # these are all filenames
                    printf 'compl_filenames=1\n'>&"${__evaled}"
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

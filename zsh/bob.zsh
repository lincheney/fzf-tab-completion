stuff() {
    local _flags=( a k f q Q e n U l o 1 2 C )
    local _sep=$'\x7f'

    # zmodload zsh/zutil

    # comparguments hack
    # seems to be function local so its hard to hijack
    # so we record all calls to comparguments and replay them every time
    comparguments() {
        if [ "$1" = -i ]; then
            # reset
            comparguments_replay=
        fi
        comparguments_replay+="; builtin comparguments $(printf '%q ' "$@")"
        eval "$comparguments_replay"
        return "$?"
    }

    compadd() {
        local words=() flags=()
        zparseopts -D -E -A opts -- "${^_flags[@]}+=flags" F: P: S: p: s: i: I: W: d: J: V: X: x: r: R: D: O: A: E: M:
        local filenames="${opts[(i)-f]}"
        unset "opts[-${^_flags[@]}]"

        if [ -n "${opts[(i)-A]}${opts[(i)-O]}${opts[(i)-D]}" ]; then
            # handle -O -A -D
            builtin compadd "${flags[@]}" "${(kv)opts[@]}" "$@"
            return "$?"
        fi

        local disp hits
        if [ "${opts[-d]:0:1}" = '(' ]; then
            eval "disp=${opts[-d]}"
        else
            disp=( "${(@P)opts[-d]}" )
        fi

        eval "$comparguments_replay"
        printf 'comparguments+=( %q )\n' "${comparguments_replay+builtin comparguments -i '' -s :; $comparguments_replay}" >&"${compopts}"

        builtin compadd "${flags[@]}" "${(kv)opts[@]}" -A hits -D disp "$@"
        local code="$?"
        flags="${(j..)flags//[ak-]}"
        unset 'opts[-d]'
        printf 'compopts+=( %q )\n' "$(printf '%q ' ${flags:+-$flags} "${(kv)opts[@]}")" >&"${compopts}"
        (( compopts_index++ ))

        local prefix="${opts[-W]:-.}"
        local disp=( "${hits[@]}" ) # display strings not handled for now
        for ((i = 1; i <= $#hits; i++)); do
            if [ -n "$filenames" -a "${disp[$i]:-${hits[$i]}}" = "${hits[$i]}" -a -d "${prefix}/${hits[$i]}" ]; then
                disp[$i]="${hits[$i]}/"
            elif [[ "${disp[$i]}" == "${hits[$i]}"* ]]; then
                disp[$i]="${hits[$i]}${_sep}${disp[$i]:${#hits[$i]}}"
            fi
            # index, value, description
            echo "${compopts_index}${_sep}${hits[$i]}${_sep}${disp[$i]:-${hits[$i]}}"
        done
        return "$code"
    }

    local value code
    local compopts=() comparguments=()
    eval "$(
        exec {compopts}>&1
        set -o pipefail
        value="$(
            (
                local compopts_index=1 comparguments_replay=
                _main_complete || true
            ) | grep . | awk -F"$_sep" '!x[$2]++' |
            FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
            fzf -1 -0 --prompt "> $PREFIX" -d "$_sep" --with-nth 3.. --nth 1 -m
        )"
        exec {compopts}>&-
        code="$?"
        printf 'value=%q\n' "$value"
        printf 'code=%q\n' "$code"
    )"
    unset -f compadd comparguments
    # tput cuu1
    # zle -I

    if [ "$code" = 0 ]; then
        local opts= index
        while IFS="$_sep" read -r -A value; do
            index="${value[1]}"
            opts="${compopts[$index]}"
            words+=( "${(q)value[2]}" )
            eval "${comparguments[$index]}"
            eval "compadd $opts -- ${(q)value[2]}"
        done <<<"$value"
        compstate[insert]=all
        # zle -R
        # zle -U $'\t'
    fi
}

jeff() {
    zle stuff
    zle redisplay
}

autoload compinit
compinit
zle -N jeff
zle -C stuff complete-word stuff
bindkey '\t' jeff

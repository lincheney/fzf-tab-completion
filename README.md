# fzf-tab-completion

Tab completion using fzf in zsh, bash, GNU readline apps (e.g. `python`, `php -a` etc.)

This is distinct from
[fzf's own implementation for completion](https://github.com/junegunn/fzf#fuzzy-completion-for-bash-and-zsh),
in that it works _with_ the existing completion mechanisms
rather than [creating a new mechanism](https://github.com/junegunn/fzf/wiki/Examples-(completion)).

## Example
<details><summary>Click here to show screencast</summary>

![Example](./example.svg)
</details>

## Installation

1. You need to [install fzf](https://github.com/junegunn/fzf#installation) first.
1. On OSX, you also need to GNU awk, e.g. `brew install gawk`
1. Clone this repository: `git clone https://github.com/lincheney/fzf-tab-completion ...`
    * you can also choose to download only the scripts you need, up to you.
1. Follow instructions on how to set up for:
    * [zsh](#zsh)
    * [bash](#bash)
    * [readline](#readline)
1. The following environment variables are supported, just as in fzf's "vanilla" completion.
    * `$FZF_TMUX_HEIGHT`
    * `$FZF_COMPLETION_OPTS`
    * `$FZF_DEFAULT_OPTS`

    See also <https://github.com/junegunn/fzf#settings>

    Avoid changing these `fzf` flags: `-n`, `--nth`, `--with-nth`, `-d`

## zsh

Add to your `~/.zshrc`:
```bash
source /path/to/fzf-tab-completion/zsh/fzf-zsh-completion.sh
bindkey '^I' fzf_completion
```
If you have also enabled fzf's zsh completion, then the `bindkey` line is optional.

Note that this does not provide `**`-style triggers,
you will need to enable fzf's zsh completion _as well_.

#### tmux

`$FZF_TMUX_OPTS` is respected same as in [fzf](https://github.com/junegunn/fzf#key-bindings-for-command-line)
however you must have fzf's keybindings enabled as well.

#### Searching display strings

By default, display strings are shown but cannot be searched in fzf.
This is configurable via `zstyle`:
```bash
# only for git
zstyle ':completion:*:*:git:*' fzf-search-display true
# or for everything
zstyle ':completion:*' fzf-search-display true
```

#### Specifying custom fzf options

You can specify custom `fzf` options with the `fzf-completion-opts` style.
This allows you to have different options based on the command being completed
(as opposed to the `$FZF_DEFAULT_OPTS` etc environment variables which are global).

This is most useful for changing the `--preview` option.
Use `{1}` for the selected text (or `{+1}` if using multi-select).
Note `{1}` or `{+1}` will come through "shell-escaped", so you will need to unescape it, e.g. using `eval` or `printf %b`

```bash
# basic file preview for ls (you can replace with something more sophisticated than head)
zstyle ':completion::*:ls::*' fzf-completion-opts --preview='eval head {1}'

# preview when completing env vars (note: only works for exported variables)
# eval twice, first to unescape the string, second to expand the $variable
zstyle ':completion::*:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-completion-opts --preview='eval eval echo {1}'

# preview a `git status` when completing git add
zstyle ':completion::*:git::git,add,*' fzf-completion-opts --preview='git -c color.status=always status --short'

# if other subcommand to git is given, show a git diff or git log
zstyle ':completion::*:git::*,[a-z]*' fzf-completion-opts --preview='
eval set -- {+1}
for arg in "$@"; do
    { git diff --color=always -- "$arg" | git log --color=always "$arg" } 2>/dev/null
done'
```

## bash

Add to your `~/.bashrc`:
```bash
source /path/to/fzf-tab-completion/bash/fzf-bash-completion.sh
bind -x '"\t": fzf_bash_completion'
```

If you are using a `bash` that is dynamically linked against readline (`LD_PRELOAD= ldd $(which bash)`)
you may prefer (or not!) to use the [readline](#readline) method instead.

#### tmux

`$FZF_TMUX_OPTS` is respected same as in [fzf](https://github.com/junegunn/fzf#key-bindings-for-command-line)
however you must have fzf's keybindings enabled as well.

#### Custom loading message

`bash` clears the prompt and input line before running the completion,
so a loading message is printed instead.

You can customise the message by overriding the `_fzf_bash_completion_loading_msg()` function.

For example the following "re-prints" the prompt and input line
to make this less jarring
(note this may or may not work, there's no detection of `$PS2` and there is always some unavoidable flicker):
```bash
_fzf_bash_completion_loading_msg() { echo "${PS1@P}${READLINE_LINE}" | tail -n1; }
```

## readline

NOTE: This uses a `LD_PRELOAD` hack, is only supported on Linux and only for GNU readline
(*not* e.g. libedit or other readline alternatives).

1. Run: `cd /path/to/fzf-tab-completion/readline/ && cargo build --release`
1. Copy/symlink `/path/to/fzf-tab-completion/readline/bin/rl_custom_complete` into your `$PATH`
1. Add to your `~/.inputrc`:
   ```
   $include function rl_custom_complete /path/to/fzf-tab-completion/readline/target/release/librl_custom_complete.so
   "\t": rl_custom_complete
   ```
1. Build https://github.com/lincheney/rl_custom_function/
   * this should produce a file `librl_custom_function.so` which you will use with `LD_PRELOAD` in the next step.
1. Run something interactive that uses readline, e.g. python:
   ```bash
   LD_PRELOAD=/path/to/librl_custom_function.so python
   ```
1. To apply this all applications more permanently,
   you will need to set `LD_PRELOAD` somewhere like `/etc/environment` or `~/.pam_environment`.
   * NOTE: if you set `LD_PRELOAD` in your `.bashrc`, or similar, it will affect applications run _from_ `bash`
      but not the parent `bash` process itself.
   * See also: [link](https://wiki.archlinux.org/index.php/Environment_variables#Per_user)

These are the applications that I have seen working:
* `python2`, `python3`
* `php -a`
* `R`
* `lftp`
* `irb --legacy` (the new `irb` in ruby 2.7 uses `ruby-reline` instead of readline)
* `gdb`
* `sqlite3`
* `bash` (only when not statically but dynamically linked to libreadline)

## Related projects

* <https://github.com/rockandska/fzf-obc> (fzf tab completion in bash)
* <https://github.com/Aloxaf/fzf-tab> (fzf tab completion in zsh)
* <https://github.com/lincheney/rl_custom_isearch> (fzf for history search in all readline applications)

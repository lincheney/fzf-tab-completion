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
1. On OSX, you also need GNU `awk` and GNU `grep`, e.g. `brew install gawk grep`
1. Clone this repository: `git clone https://github.com/lincheney/fzf-tab-completion ...`
    * you can also choose to download only the scripts you need, up to you.
1. Follow instructions on how to set up for:
    * [zsh](#zsh)
    * [bash](#bash)
    * [readline](#readline)
    * [nodejs](#nodejs-repl)
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

#### --tiebreak=chunk

The default `fzf` tiebreak setting is line: `Prefers line with shorter length`.
The length of the zsh display strings may skew the ordering of the results even though they are not part of the match.
You may find that adding the `fzf` flag `--tiebreak=chunk` to the environment variable `$FZF_COMPLETION_OPTS` provides better behaviour.

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

#### Specifying keybindings

You can specify `fzf` keybindings to execute shell commands *after* `fzf` has closed.
This is configurable via the `fzf-completion-keybindings` zstyle.

Keybinds look like: `KEY:SCRIPT`
When `KEY` is pressed, `fzf` will *exit* and the zsh `SCRIPT` will run.
If the keybind is given in the form `KEY:accept:SCRIPT` then the selected matches will also be completed before `SCRIPT` is run.
`KEY` is any valid `fzf` key.

There is an additional function `repeat-fzf-completion` that can be called in the `SCRIPT` to retrigger `fzf` completion.

No keybinds are configured by default.

```bash
# press ctrl-r to repeat completion *without* accepting i.e. reload the completion
# press right to accept the completion and retrigger it
# press alt-enter to accept the completion and run it
keys=(
    ctrl-r:'repeat-fzf-completion'
    right:accept:'repeat-fzf-completion'
    alt-enter:accept:'zle accept-line'
)

zstyle ':completion:*' fzf-completion-keybindings "${keys[@]}"
# also accept and retrigger completion when pressing / when completing cd
zstyle ':completion::*:cd:*' fzf-completion-keybindings "${keys[@]}" /:accept:'repeat-fzf-completion'
```

Note that you can still specify the normal `--bind ...` options in e.g. `$FZF_COMPLETION_OPTS`
if you need to perform `fzf` specific actions or don't need to run zsh commands.

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

Note that this does not provide `**`-style triggers,
you will need to enable fzf's bash completion _as well_.

If you are using a `bash` that is dynamically linked against readline (`LD_PRELOAD= ldd $(which bash)`)
you may prefer (or not!) to use the [readline](#readline) method instead.

#### Autocomplete common prefix

By default, fzf is always shown whenever there are at least 2 matches.
You can change this to a more "vanilla" tab completion experience where
it attempts to complete the longest common prefix *before* showing matches in fzf.

This is controlled by the variables
* `FZF_COMPLETION_AUTO_COMMON_PREFIX=true` - completes the common prefix if it is also a match
* `FZF_COMPLETION_AUTO_COMMON_PREFIX_PART=true` - with the above variable, completes the common prefix even if it is not a match

For example, if we have following files in a directory:
```
abcdef-1234
abcdef-5678
abc
other
```

With `FZF_COMPLETION_AUTO_COMMON_PREFIX=true`:
* when completing `ls <tab>`, it will display fzf with all 4 files (as normal)
* when completing `ls a<tab>`, it will automatically complete to `ls abc`. 
    Pressing tab again will show fzf with the first 3 files.
* when completing `ls abcd<tab>` it will show fzf with the first 2 files (as normal)
* With `FZF_COMPLETION_AUTO_COMMON_PREFIX_PART=true` set as well:
    * when completing `ls abcd<tab>`, it will automatically complete to `ls abcdef-`.
        Pressing tab again will show fzf with the first 2 files.

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

## nodejs repl

1. Copy/symlink `/path/to/fzf-tab-completion/readline/bin/rl_custom_complete` into your `$PATH`
1. Then run `node -r /path/to/fzf-tab-completion.git/node/fzf-node-completion.js`
    * You may wish to add a shell alias to your `zshrc`/`bashrc` to avoid typing out the full command each time, e.g.:
        `alias node='node -r /path/to/fzf-tab-completion.git/node/fzf-node-completion.js`

## Related projects

* <https://github.com/rockandska/fzf-obc> (fzf tab completion in bash)
* <https://github.com/Aloxaf/fzf-tab> (fzf tab completion in zsh)
* <https://github.com/lincheney/rl_custom_isearch> (fzf for history search in all readline applications)

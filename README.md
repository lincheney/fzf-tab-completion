# fzf-tab-completion

Tab completion using fzf in zsh, bash, GNU readline apps (e.g. `python`, `php -a` etc.)

This is distinct from
[fzf's own implementation for completion](https://github.com/junegunn/fzf#fuzzy-completion-for-bash-and-zsh),
in that it works _with_ the existing completion mechanisms
rather than [creating a new mechanism](https://github.com/junegunn/fzf/wiki/Examples-(completion)).

![Example](./example.svg)

## Installation

1. You need to [install fzf](https://github.com/junegunn/fzf#installation) first.
1. Clone this repository: `git clone https://github.com/lincheney/fzf-tab-completon ...`
    * you can also choose to download only the scripts you need, up to you.
1. Follow instructions on how to set up for:
    * [zsh](#zsh)
    * [bash](#bash)
    * [readline](#readline)

#### zsh

Add to your `~/.zshrc`:
```bash
source /path/to/fzf-tab-completion/zsh/fzf-zsh-completion.sh
bindkey '^I' fzf_completion
```
If you have also enabled fzf's zsh completion, then the `bindkey` line is optional.

> Note that this does not provide `**`-style triggers,
you need to enable fzf's zsh completion _as well_.

#### bash

Add to your `~/.bashrc`:
```bash
source /path/to/fzf-tab-completion/bash/fzf-bash-completion.sh
bind -x '"\t": fzf_bash_completion'
```

> If you are using a `bash` that is dynamically linked against readline (`LD_PRELOAD= ldd $(which bash)`)
you may prefer (or not!) to use the [readline](#readline) method instead.

#### readline

> This uses a `LD_PRELOAD` hack and *only* works on Linux.

1. Install https://github.com/lincheney/rl_custom_function/
    * consider adding `export LD_PRELOAD=/path/to/librl_custom_function.so` to your `~/.zshrc` or `~/.bashrc`
1. Run: `cd /path/to/fzf-tab-completion/readline/ && cargo build --release`
1. Add to your `~/.inputrc`:
```
$include function rl_custom_complete /path/to/fzf-tab-completion/readline/target/release/librl_custom_complete.so
"\t": rl_custom_complete
```

## Configuration

The following environment variables are supported, just as in fzf's "vanilla" completion.
* `$FZF_TMUX_HEIGHT`
* `$FZF_COMPLETION_OPTS`
* `$FZF_DEFAULT_OPTS`

See <https://github.com/junegunn/fzf#settings>

## Related projects

* <https://github.com/rockandska/fzf-obc> (fzf tab completion in bash)
* <https://github.com/Aloxaf/fzf-tab> (fzf tab completion in zsh)

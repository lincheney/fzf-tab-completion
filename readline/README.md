# rl_custom_complete

Hack to customise readline tab completion.

Completion is delegated to a script instead,
which receives possible completions on stdin
and outputs selected completions to stdout.

This relies on https://github.com/lincheney/rl_custom_function

## How to use

Build the library:
```bash
cargo build --release
```

You should now have a .so at `./target/release/librl_custom_complete.so`

Copy [src/rl_custom_complete](src/rl_custom_complete)
in to your `$PATH` (or write your own).
The provided script requires [fzf](https://github.com/junegunn/fzf)

Add to your `~/.inpurc`:
```
$include function rl_custom_complete /path/to/librl_custom_complete.so
"\t": rl_custom_complete
```

Run:
```bash
LD_PRELOAD=/path/to/librl_custom_function.so python
```

Type `str.` and press the tab key.

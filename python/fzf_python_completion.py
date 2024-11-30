def init():
    import readline
    import rlcompleter
    import inspect
    import functools
    import itertools
    import subprocess
    import re
    import os
    import sys
    import warnings
    import __main__

    #  @functools.lru_cache(1)
    def make_completer(completer, pre=None, post=None):
        if completer is None:
            return None

        if pre is None:
            def pre():
                # doesn't seem to be a good way to redraw the prompt after fzf is done
                # so start fzf on the next line and get the cursor column so we can restore the cursor position at least
                # this probably doesn't work if the command is multiline/wraps
                # can't just use sc/rc as fzf also uses that
                print('\x1b[6n\r\n', flush=True, end='', file=sys.__stderr__)
                buf = b''
                while not (match := re.search(rb'\x1b\[\d+;(\d+)R', buf)) and len(buf) < 100:
                    buf += os.read(0, 1)
                return int(match.group(1)) if match else 1

        if post is None:
            def post(column):
                print(f'\x1b[A\r\x1b[{column - 1}C', flush=True, end='', file=sys.__stderr__)

        @functools.wraps(completer)
        def fn(text, state):
            if state != 0:
                return

            matches = [m for m in itertools.takewhile(bool, (completer(text, i) for i in itertools.count())) if m != text]
            # don't need fzf if only 1 match
            if len(matches) == 1:
                return matches[0]
            if not matches:
                return

            docs = [''] * len(matches)
            width = max(map(len, matches))

            namespace = __main__.__dict__
            if inspect.ismethod(completer) and isinstance(completer.__self__, rlcompleter.Completer) and (completer.__self__.use_main_ns or completer.__self__.namespace is namespace):
                with warnings.catch_warnings(action='ignore'):
                    for i, m in enumerate(matches):
                        if match := re.fullmatch(r'(\w([\w.]*\w)?)(\(\)?)?', m):
                            # rlcompleter uses eval too?
                            # https://github.com/python/cpython/blob/bb98a0afd8598ce80f0e6d3f768b128eab68f40a/Lib/rlcompleter.py#L157
                            try:
                                value = eval(match.group(1), namespace)
                            except Exception:
                                pass
                            else:
                                doc = repr(value)
                                if callable(value) or inspect.ismodule(value):
                                    doc = getattr(value, '__doc__', doc)
                                docs[i] = doc.strip().partition('\n')[0].strip() if isinstance(doc, str) else ''

            sep = '\x01'
            docs = [' ' * (width - len(m)) + f'\t\x1b[2m-- {d}\x1b[0m' if d else '' for m, d in zip(matches, docs)]
            input = '\n'.join(m + sep + d + sep + m for m, d in zip(matches, docs))
            args = ['rl_custom_complete', text, '--with-nth=1,2', '-d(^'+re.escape(text)+')|'+sep]

            state = pre()
            try:
                return subprocess.check_output(args, input=input, text=True).strip('\n').rpartition(sep)[-1]
            except subprocess.CalledProcessError:
                return
            finally:
                post(state)

        return fn

    old_set_completer = readline.set_completer
    def new_set_completer(completer):
        return old_set_completer(make_completer(completer))
    readline.set_completer = functools.update_wrapper(new_set_completer, old_set_completer)

    # return the original completer
    old_get_completer = readline.get_completer
    def new_get_completer():
        fn = old_get_completer()
        return getattr(fn, '__wrapped__', fn)
    readline.get_completer = functools.update_wrapper(new_get_completer, old_get_completer)

    # hijack the readline completer
    readline.set_completer(readline.get_completer())

    # hijack the new python 3.13+ completer
    try:
        import _pyrepl.readline
    except ImportError:
        pass
    else:
        reader = _pyrepl.readline._wrapper.get_reader()
        old_get_completions = reader.get_completions
        def new_get_completions(stem):
            old_completer = reader.config.readline_completer
            try:
                reader.config.readline_completer = make_completer(
                    old_completer,
                    pre=lambda: setattr(reader, 'dirty', True),
                    post=lambda x: reader.console.repaint()
                )
                return old_get_completions(stem)
            finally:
                reader.config.readline_completer = old_completer
        reader.get_completions = functools.update_wrapper(new_get_completions, old_get_completions)

init()
del init

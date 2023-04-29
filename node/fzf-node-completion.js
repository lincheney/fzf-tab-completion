// vi: ft=javascript

const child_process = require('node:child_process');
const repl = require('node:repl');

process.stdin.on('keypress', function(str, key) {
    if (!repl.repl) {
        return;
    }

    if (key.sequence == '\t') {
        // sabotage the key so the repl doesn't get it
        key.name = '';
        key.ctrl = 1;
        key.sequence = '';

        repl.repl.completer(repl.repl.line.slice(0, repl.repl.cursor), function(error, [completions, prefix]) {
            if (completions.length == 0) {
                return;
            }
            let stdout = prefix;
            const input = completions.filter(x => x !== '').join('\n');
            try {
                stdout = child_process.execFileSync('rl_custom_complete', [prefix], {input, stdio: ['pipe', 'pipe', 'inherit']}).toString().trim('\n');
            } catch(e) {
            }
            repl.repl.line = repl.repl.line.slice(0, repl.repl.cursor - prefix.length) + stdout + repl.repl.line.slice(repl.repl.cursor);
            repl.repl.cursor += stdout.length - prefix.length;
            // fzf will have destroyed the prompt, so fix it
            repl.repl._refreshLine();
        });
    }
})

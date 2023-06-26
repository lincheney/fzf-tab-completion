// vi: ft=javascript

const child_process = require('node:child_process');
const repl = require('node:repl');

const start = repl.start;
repl.start = function(...args) {
    const replServer = start(...args);
    replServer.input.on('keypress', function(str, key) {
        if (key.sequence == '\t') {
            // sabotage the key so the repl doesn't get it
            key.name = '';
            key.ctrl = 1;
            key.sequence = '';

            replServer.completer(replServer.line.slice(0, replServer.cursor), function(error, [completions, prefix]) {
                if (completions.length == 0) {
                    return;
                }
                let stdout = prefix;
                const input = completions.filter(x => x !== '').join('\n');
                try {
                    stdout = child_process.execFileSync('rl_custom_complete', [prefix], {input, stdio: ['pipe', 'pipe', 'inherit']}).toString().trim('\n');
                } catch(e) {
                }
                replServer.line = replServer.line.slice(0, replServer.cursor - prefix.length) + stdout + replServer.line.slice(replServer.cursor);
                replServer.cursor += stdout.length - prefix.length;
                // fzf will have destroyed the prompt, so fix it
                replServer._refreshLine();
            });
        }
    });
    return replServer;
};

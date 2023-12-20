const cp = require('child_process');
const process = require('process');
const slackifyMarkdown = require('slackify-markdown');

exports.startGithubWebhook = async function(repo, url) {
    console.log(`running gh webhook forward --repo=${repo} --events=release --url=${url}`);
    const webhook = cp.spawn('gh', [
        'webhook',
        'forward',
        `--repo=${repo}`,
        '--events=release',
        `--url=${url}`
    ]);
    webhook.stdout.on('data', (data) => {
        console.log(`gh stdout: ${data}`);
    });
    webhook.stderr.on('data', (data) => {
        console.log(`gh stderr: ${data}`);
    });
    webhook.on('close', (code) => {
        console.log(`gh process exited with code ${code}`);
    });
}

exports.slackifyMarkdown = function(text) {
    return slackifyMarkdown(text);
}

exports.debug = function(message) {
    process.stderr.write(`DEBUG: ${message}\n`);
}

export default interface extern {
  debug: (msg: string) => Promise<void>,
  slackifyMarkdown: (text: string) => Promise<string>,
  startGithubWebhook: (repo: string, endpoint: string) => Promise<void>,
}

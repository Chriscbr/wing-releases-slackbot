// for local testing:
// - install GH CLI (https://cli.github.com/) and authenticate with `gh auth login`
// - install GH CLI webhook extension (https://docs.github.com/en/webhooks-and-events/webhooks/receiving-webhooks-with-the-github-cli)
// to deploy this app to the cloud, set the GITHUB_TOKEN environment variable
// in order to deploy the GitHub webhook. eg:
// > export GITHUB_TOKEN=$(gh auth token)

// --------------------------------
// Config

let SLACK_CHANNEL_ALL_RELEASES = "#rybickic-test";
let SLACK_CHANNEL_BREAKING_CHANGES = "#rybickic-test2";
let GITHUB_OWNER = "Chriscbr";
let GITHUB_REPO = "local-sim-test";

// let SLACK_CHANNEL_ALL_RELEASES = "#releases";
// let SLACK_CHANNEL_BREAKING_CHANGES = "#breaking-changes";
// let GITHUB_OWNER = "winglang";
// let GITHUB_REPO = "wing";

// --------------------------------
// Utils

bring cloud;
bring http;
bring util;

let GITHUB_REPO_FULL = "{GITHUB_OWNER}/{GITHUB_REPO}";

struct HttpRequestOptions {
  method: str?;
  headers: Map<str>?;
  body: str;
}

class Utils {
  pub extern "./utils.js" inflight static startGithubWebhook(repo: str, endpoint: str);
  pub extern "./utils.js" inflight static slackifyMarkdown(text: str): str;

  // unlike "log", this prints immediately to CLI during `wing test`
  pub extern "./utils.js" inflight static debug(msg: str);
}

// ------------------------------------------------------------------------------------------------
// Slack

struct SlackProps {
  token: cloud.Secret;
}

struct PostMessageArgs {
  channel: str;
  text: str?;
  blocks: Array<Json>?;
}

class SlackClient {
  token: cloud.Secret;

  new(props: SlackProps) {
    this.token = props.token;
  }

  pub inflight post_message(args: PostMessageArgs) {
    let token = this.token.value();

    let blocks: Json = args.blocks ?? Array<Json> [];
    let res = http.fetch(
      "https://slack.com/api/chat.postMessage",
      method: http.HttpMethod.POST,
      headers: {
        "Authorization": "Bearer {token}",
        "Content-Type": "application/json"
      },
      body: Json.stringify(Json {
        channel: args.channel,
        text: args.text ?? "",
        blocks: blocks,
      })
    );

    log(Json.stringify(res));
  }  
}

// -------------------------------
// Github

struct GithubRelease {
  title: str;
  author: str;
  tag: str;
  body: str;
  url: str;
}

interface IOnGitHubRelease {
  inflight handle(release: GithubRelease);
}

struct SlackPublisherProps {
  slack: SlackClient;
  allReleasesChannel: str;
  breakingChangesChannel: str;
}

class SlackPublisher impl IOnGitHubRelease {
  slack: SlackClient;
  allReleasesChannel: str;
  breakingChangesChannel: str;

  new(props: SlackPublisherProps) {
    this.slack = props.slack;
    this.allReleasesChannel = props.allReleasesChannel;
    this.breakingChangesChannel = props.breakingChangesChannel;
  }

  pub inflight handle(release: GithubRelease) {
    let blocks = MutArray<Json>[];
    blocks.push(Json { 
      type: "header", 
      text: Json { 
        type: "plain_text", 
        text: "Wing {release.tag} has been released! :rocket:"
      } 
    });

    // currently, new minor version releases are considered breaking changes
    let isBreakingChange = release.tag.endsWith(".0");

    let var description = release.body;
    // strip everything after "### SHA-1 Checksums"
    description = description.split("### SHA-1 Checksums").at(0);
    // convert to slack markdown format
    description = Utils.slackifyMarkdown(description);

    blocks.push(Json {
      type: "section",
      text: Json {
        type: "mrkdwn",
        text: "{description}\n\nLearn more: <{release.url}>",
      }
    });

    Utils.debug("posting slack message: {Json.stringify(blocks)}");

    this.slack.post_message(channel: this.allReleasesChannel, blocks: blocks.copy());
    if isBreakingChange {
      this.slack.post_message(channel: this.breakingChangesChannel, blocks: blocks.copy());
    }
  }
}

class GithubScanner {
  api: cloud.Api;
  pub url: str;
  releases: cloud.Topic;
  new() {
    this.api = new cloud.Api();
    this.releases = new cloud.Topic();
    this.url = this.api.url;

    this.api.post("/payload", inflight (req: cloud.ApiRequest): cloud.ApiResponse => {
      let body = Json.parse(req.body ?? "\{\}");

      let eventAction = str.fromJson(body.get("action"));
      if eventAction != "released" {
        let message = "skipping event type with type '{eventAction}'";
        Utils.debug(message);
        return cloud.ApiResponse {
          status: 200,
          body: message, 
        };
      }

      let repo = str.fromJson(body.get("repository").get("full_name"));
      if repo != GITHUB_REPO_FULL {
        let message = "skipping release for repo '{repo}'";
        Utils.debug(message);
        return cloud.ApiResponse {
          status: 200,
          body: message,
        };
      }

      this.releases.publish(Json.stringify(body));
      let releaseTag = str.fromJson(body.get("release").get("tag_name"));
      Utils.debug("published release {releaseTag} to topic");

      return cloud.ApiResponse {
        status: 200,
        body: "published release event",
      };
    });
  }

  pub onRelease(handler: IOnGitHubRelease): cloud.Function {
    return this.releases.onMessage(inflight (message: str) => {
      let event = Json.parse(message);
      let release = GithubRelease {
        title: str.fromJson(event.get("release").get("name")),
        author: str.fromJson(event.get("release").get("author").get("login")),
        tag: str.fromJson(event.get("release").get("tag_name")),
        body: str.fromJson(event.get("release").get("body")),
        url: str.fromJson(event.get("release").get("html_url")),
      };
      handler.handle(release);
    });
  }
}

// --------------------------------
// Main

let slackToken = new cloud.Secret(name: "slack-token") as "Slack Token";
let slack = new SlackClient(token: slackToken);

let scanner = new GithubScanner();
let slackPublisher = new SlackPublisher(
  slack: slack,
  allReleasesChannel: SLACK_CHANNEL_ALL_RELEASES,
  breakingChangesChannel: SLACK_CHANNEL_BREAKING_CHANGES
);
scanner.onRelease(slackPublisher);

new cloud.Endpoint(scanner.url);

// --------------------------------
// Local testing (these functions won't work in the cloud)

// test "start webhook" {
//   let url = scanner.url;
//   let payloadUrl = "{url}/payload";
  
//   Utils.debug("webhook created at: {url}");
//   Utils.debug("starting event forwarding...");
  
//   // If we start forwarding events too soon after our API endpoint is created,
//   // it's possible to get a "websocket: bad handshake" error.
//   util.sleep(2s);
  
//   Utils.startGithubWebhook(GITHUB_REPO_FULL, payloadUrl);
//   util.sleep(15m);
  
//   Utils.debug("event forwarding started, waiting for events...");
//   log("stopping function for now");
// }

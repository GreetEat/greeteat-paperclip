---
title: "Paperclip on Google Cloud Run — Operations Guide"
subtitle: "Deployment, board operations, and 3rd party integrations"
author: "GreetEat Corp (OTC: GEAT)"
date: "April 2026"
---

\newpage

# About this guide

This guide covers deploying and operating [Paperclip](https://github.com/paperclipai/paperclip) — the open-source AI agent orchestration platform — on Google Cloud Run with Vertex AI Claude.

**Version**: written for Paperclip commit `ac664df` (between `v2026.403.0` and `v2026.410.0`). Paperclip is evolving rapidly — features, API endpoints, and UI may change between versions.

**Audience**: board members, platform operators, and anyone running Paperclip in a cloud environment.

**Published by**: GreetEat Corp — [greeteat.com](https://greeteat.com) | OTC: GEAT

\newpage

# Part 1: Cloud Deployment Guide

Paperclip was designed for local developer use. Deploying it to stateless compute (Cloud Run) requires workarounds for the local-first assumptions. This section covers the 7 categories of workarounds we discovered and how we solved them.

## The core mismatch

| Paperclip assumes | Cloud Run provides |
|---|---|
| Persistent Docker volume at `/paperclip` | Per-instance ephemeral tmpfs |
| Single user (the developer) | Multiple instances, no shared state |
| `~/.paperclip/` persists between runs | Fresh filesystem on every scale event |
| `paperclipai` CLI is on PATH | CLI is a pnpm script, not a binary |
| Terminal access to the running process | No exec, no SSH, no TTY |
| `disableSignUp=false` is fine | Open signup = published RCE exploit chain |

## Workaround 1: GCS FUSE mount at `/paperclip`

Without this, agents lose instructions, memory, and workspace files on every instance recycle. Cloud Run v2 supports GCS FUSE volumes natively:

```hcl
volumes {
  name = "paperclip-state"
  gcs { bucket = "your-state-bucket"; read_only = false }
}
containers {
  volume_mounts { name = "paperclip-state"; mount_path = "/paperclip" }
}
```

Runtime SA needs `roles/storage.objectUser` on the bucket.

## Workaround 2: DATABASE_URL needs `?sslmode=require`

postgres.js does NOT auto-negotiate TLS. Cloud SQL with `ssl_mode=ENCRYPTED_ONLY` rejects cleartext:

```
PostgresError: pg_hba.conf rejects connection for host "10.8.0.x",
  user "paperclip", database "paperclip", no encryption
```

## Workaround 3: Bootstrap-ceo CLI wrapper

The CLI bails if `/paperclip/instances/default/config.json` is missing. Fix: a wrapper script materializes a minimal config from env vars before running the CLI.

`paperclipai` is NOT a binary — it's a pnpm script. The actual invocation is `node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts`. Don't override the Docker ENTRYPOINT.

## Workaround 4: The bootstrap dance

`PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` blocks both the RCE exploit chain AND the first user creation. The bootstrap-ceo invite promotes a signed-in user — it doesn't create one.

**Recipe**: temporarily flip the env var → sign up → accept invite → flip back. Same dance for every new user.

## Workaround 5: No UI for human invites

The dashboard only has invite-creation UI for agents. For human board users, call the API from browser dev tools:

```js
fetch("/api/companies/COMPANY_ID/invites", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ allowedJoinTypes: "human" }),
}).then(r => r.json()).then(j => prompt("Invite URL:", location.origin + j.inviteUrl));
```

**Note**: company invites expire in 10 minutes. Create them when the invitee is ready to click.

## Workaround 6: Managed instructions are disk-only

Agent instructions written at creation time are lost when containers recycle. The GCS FUSE mount (Workaround 1) fixes this going forward. For agents created before the mount, restore from upstream templates at `server/src/onboarding-assets/`.

## Workaround 7: Vertex web_search org policy

If your GCP org enforces `denyAll` on `constraints/vertexai.allowedPartnerModelFeatures`, set a project-level override via `gcloud org-policies set-policy`. Requires `roles/orgpolicy.policyAdmin` at the org level.

## Architecture

```
Internet → Cloud Run service (paperclip, min_instances=2)
             ├─ VPC connector → Cloud SQL (PG17, private IP, HA)
             ├─ GCS FUSE mount → persistent agent state (/paperclip)
             ├─ Secrets from Secret Manager (5 mounted env vars)
             └─ Vertex AI Claude (Opus 4.6 / Sonnet 4.6 / Haiku 4.5)

Cloud Run Job (bootstrap-ceo) — seed operator bootstrap
GitHub Actions (build-image.yml) — WIF auth, upstream Dockerfile
```

\newpage

# Part 2: Board Operations Guide

For board members who interact with Paperclip through the dashboard. No terminal or infrastructure knowledge required.

## Understanding the hierarchy

```
Board members (humans) — sign in, create goals, assign work, approve hires
  └─ Goals (strategy) — what you want to achieve
      └─ Projects (organization) — group related work
          └─ Issues (work items) — specific tasks
              └─ Agents (workers) — AI agents that do the work
```

**Key concept**: agents only work on issues that are assigned to them. They don't pick up work on their own.

## Creating goals

1. Dashboard → **Goals** → **New Goal**
2. Title: clear, outcome-oriented (e.g., "Grow GreetEat user base to 10K MAU")
3. Level: `company`, `team`, `agent`, or `task`
4. Status: `planned` or `active`

Goals organize work — they don't trigger agent activity. Create issues linked to goals to make things happen.

## Assigning work to agents

1. Dashboard → **New Issue**
2. Fill in title, description (be specific about deliverables), assignee, priority, goal
3. Click **Create**

### Writing good briefs

**Good**: "Research the top 5 competitors to GreetEat. Deliverables: competitive matrix, gap analysis, opportunity list. Focus on B2B-oriented competitors."

**Bad**: "Look into our competitors."

### The CEO delegation pattern

Assign to the **CEO** for cross-functional work. The CEO reads the issue, identifies which department owns it, creates a subtask for the right agent (CMO for marketing, Head of Research for analysis), and comments explaining the delegation.

## Watching agents work

- **Live Runs**: real-time view of active heartbeats
- **Agent → Runs tab**: completed runs with transcripts, cost, outcome
- **Issue comments**: agents post status updates as they work

## Hiring new agents

Create an issue for the CEO: "Hire a [role] for [purpose]." The CEO uses the `paperclip-create-agent` skill. If board approval is required, you'll see a pending Approval to review.

### Agent instructions

Every agent has instruction files (AGENTS.md, HEARTBEAT.md, SOUL.md, TOOLS.md). New hires get a generic default — customize via the Instructions tab on the agent page.

## Inviting new board members

> **Current limitation**: the dashboard doesn't have a UI for human invites.

1. Ask your platform operator to temporarily enable sign-up
2. Create an invite via browser dev tools:
   ```js
   fetch("/api/companies/COMPANY_ID/invites", {
     method: "POST",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({ allowedJoinTypes: "human" }),
   }).then(r => r.json()).then(j => prompt("Copy:", location.origin + j.inviteUrl));
   ```
3. Send the URL to the invitee (expires in 10 minutes)
4. They sign up + accept
5. You approve the join request
6. Operator re-locks sign-up

\newpage

# Part 3: 3rd Party Integrations & Automation

## Connecting agents to external services

### Step 1 — Obtain API credentials (human, one-time)

| Service | Where | What you need |
|---|---|---|
| **LinkedIn** | linkedin.com/developers | OAuth 2.0 token + org URN |
| **X (Twitter)** | developer.x.com | API Key, Secret, Access Token |
| **Slack** | api.slack.com/apps | Bot token (`xoxb-...`) |

### Step 2 — Store as Paperclip secrets

```js
fetch("/api/companies/COMPANY_ID/secrets", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    name: "linkedin-access-token",
    value: "YOUR_TOKEN"
  }),
}).then(r => r.json()).then(j => console.log("Secret ID:", j.id));
```

Values are encrypted at rest. Only secret IDs are visible in the API.

### Step 3 — Configure agent to use the secret

Add to the agent's adapter config env:

```json
{
  "LINKEDIN_ACCESS_TOKEN": {
    "type": "secret_ref",
    "secretId": "SECRET_ID",
    "version": "latest"
  }
}
```

### Step 4 — Agent posts via API

The agent uses `curl` to call external APIs with the decrypted token at runtime.

## Scheduling recurring tasks (routines)

Create a routine with a cron trigger:

```js
// Create routine + schedule trigger
fetch("/api/companies/COMPANY_ID/routines", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    title: "LinkedIn weekly posts",
    description: "Check content calendar, post next scheduled item",
    assigneeAgentId: "CMO_AGENT_ID",
    projectId: "PROJECT_ID",
    status: "active"
  }),
}).then(r => r.json()).then(j => {
  fetch(`/api/routines/${j.id}/triggers`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: "schedule",
      cronExpression: "0 9 * * 1,3,5",
      timezone: "America/New_York"
    }),
  });
});
```

| Schedule | Cron |
|---|---|
| Mon/Wed/Fri 9am | `0 9 * * 1,3,5` |
| Every weekday 9am | `0 9 * * 1-5` |
| Weekly Monday 10am | `0 10 * * 1` |
| 1st of month | `0 9 1 * *` |

When a routine fires, it creates an issue → the agent wakes → does the work → marks done.

## End-to-end: automated LinkedIn posting

1. **Get credentials** (human, one-time): LinkedIn Developer App → access token
2. **Store token** as a Paperclip company secret
3. **Create goal + project**: "Build LinkedIn presence" → "Social Media"
4. **CMO drafts content calendar** (via an issue)
5. **Set up posting routine**: Mon/Wed/Fri 9am → CMO
6. **Steady state**: routine fires → CMO reads calendar → posts via LinkedIn API → done
7. **Token refresh**: set a monthly health-check routine; LinkedIn tokens expire after 60 days

## Token lifecycle management

Set up a monthly routine to verify API tokens still work:

- Title: "Check API token health"
- Schedule: 1st of month, 9am
- Agent: CMO
- Description: "Test each credential with a lightweight API call. If any returns 401/403, mark blocked and tag the board to refresh."

\newpage

# Part 4: Advanced Workflows

## Video content creation with Remotion

[Remotion](https://www.remotion.dev/) lets you create videos programmatically using React. Agents can write video compositions as code, render them via Remotion Lambda (serverless), and post the finished videos to social media — all without human intervention.

### Architecture

```
CMO agent wakes on routine
  │
  ├─ 1. Reads content calendar
  ├─ 2. Writes a Remotion composition (.tsx) to /paperclip workspace
  ├─ 3. Calls Remotion Lambda API to render → gets MP4 URL
  ├─ 4. Downloads MP4, attaches to the issue for board review
  └─ 5. Posts to LinkedIn/X with the video
```

### Prerequisites (one-time setup)

**Remotion Lambda** — deploy a Remotion Lambda function to AWS (or use Remotion's hosted service). This handles the actual video rendering — the Paperclip agent only needs to make API calls, no local Chromium/ffmpeg required.

**Store Remotion credentials** as Paperclip company secrets:

```js
// Remotion Lambda credentials
fetch("/api/companies/COMPANY_ID/secrets", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    name: "remotion-aws-access-key",
    value: "AKIA..."
  }),
}).then(r => r.json()).then(console.log);

// Repeat for remotion-aws-secret-key, remotion-function-name, etc.
```

**Enable video attachments** — add to Cloud Run service env vars (via Terraform):

```
PAPERCLIP_ALLOWED_ATTACHMENT_TYPES=image/*,application/pdf,text/*,video/mp4,video/webm
```

### How an agent renders a video

The CMO agent writes a Remotion composition, then calls the Lambda API:

**Step 1 — Write the composition**

The agent creates a React component that defines the video. This is just code — the agent writes it like any other file:

```tsx
// /paperclip/workspaces/<agent>/renders/linkedin-post.tsx
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";

export const LinkedInPost: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 30], [0, 1]);

  return (
    <AbsoluteFill style={{ backgroundColor: "#0077B5" }}>
      <h1 style={{ color: "white", opacity, fontSize: 64, padding: 80 }}>
        GreetEat: Business meals, reimagined
      </h1>
    </AbsoluteFill>
  );
};
```

**Step 2 — Render via Remotion Lambda**

```bash
curl -X POST "https://remotion-lambda.your-domain.com/render" \
  -H "Authorization: Bearer $REMOTION_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "composition": "LinkedInPost",
    "serveUrl": "https://your-remotion-bundle.s3.amazonaws.com/bundle.js",
    "inputProps": { "title": "GreetEat: Business meals, reimagined" },
    "codec": "h264",
    "outputFormat": "mp4"
  }'
```

Returns a render ID. Poll for completion, then download the MP4.

**Step 3 — Attach to issue for review**

```bash
curl -X POST "$PAPERCLIP_API_URL/api/companies/$COMPANY_ID/issues/$ISSUE_ID/attachments" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID" \
  -F "file=@/tmp/linkedin-post.mp4"
```

Board members see the video directly in the issue's attachment viewer.

### Template-driven video at scale

For repeatable content (weekly stats videos, product announcements), store Remotion templates in the agent's workspace:

```
/paperclip/workspaces/<cmo>/templates/
  ├── weekly-stats.tsx       # Animated chart template
  ├── product-spotlight.tsx  # Feature highlight template
  ├── company-news.tsx       # Press release template
  └── data-insight.tsx       # WallStreetStats data viz
```

The routine fires → agent picks the right template → fills in current data → renders → posts. Each video is unique but follows a consistent brand format.

### Cost considerations

| Component | Cost |
|---|---|
| Remotion Lambda render (15s video) | ~$0.01-0.05 per render |
| Claude Opus 4.6 (composition writing) | ~$0.10-0.50 per heartbeat |
| GCS storage (MP4 files) | ~$0.02/GB/month |
| LinkedIn/X API | Free (within rate limits) |

A Mon/Wed/Fri posting routine with video: ~$5-15/month total.

## Multi-agent content pipeline

For production content workflows, chain multiple agents:

```
1. Head of Product Research → competitive data + market insights
       ↓ (subtask with data attached)
2. CMO → content strategy + copy + Remotion composition
       ↓ (subtask with draft attached)
3. Board review → approve or request changes
       ↓ (comment on issue)
4. CMO → post to LinkedIn/X (routine-triggered)
```

Set this up by having the CEO create a parent issue ("Q2 content campaign") with subtasks that cascade through the pipeline. Each agent works its piece, attaches deliverables, and assigns the next step.

### Example: data-driven weekly video series

**"WallStreetStats Weekly Insights"** — every Monday, publish a 15-second animated chart video on X showing the week's top sentiment shifts.

Setup:
1. **Goal**: "Build WallStreetStats brand on X"
2. **Routine**: "Weekly Insights Video" — fires Monday 7am, assigned to CMO
3. **Pipeline per issue**:
   - CMO reads this week's WallStreetStats data (via curl to your analytics API or stored in PARA memory)
   - CMO picks the most interesting data point
   - CMO writes a Remotion composition with the chart animation
   - CMO renders via Lambda → gets MP4
   - CMO posts to X with the video + a caption
   - CMO marks issue done with a link to the tweet

## Webhook-triggered workflows

Routines can also fire via **webhooks** — external systems POST to a Paperclip URL and trigger agent work:

```js
// Create a webhook trigger on a routine
fetch(`/api/routines/${routineId}/triggers`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ kind: "webhook" }),
}).then(r => r.json()).then(t => {
  console.log("Webhook URL:", `/api/routine-triggers/public/${t.publicId}/fire`);
});
```

**Use cases**:
- **GitHub push → agent reviews the PR** (GitHub webhook fires the routine)
- **Stripe payment → agent sends a thank-you** (Stripe webhook)
- **CRM lead created → agent researches the company** (HubSpot/Salesforce webhook)
- **Monitoring alert → agent investigates** (PagerDuty/Datadog webhook)

The webhook creates an issue with the payload data → the assigned agent wakes and handles it.

## Building custom Paperclip skills

Skills are reusable capabilities you can install on agents. Paperclip has a skill authoring system:

```
skills/
  my-skill/
    SKILL.md          # Skill definition (markdown with instructions)
    references/       # Supporting docs the skill can reference
    evals/            # Test cases for the skill
```

You can create company-specific skills (e.g., "post-to-linkedin", "render-remotion-video", "analyze-wallstreetstats-data") and install them on agents via:

```
POST /api/agents/{agentId}/skills/sync
{ "desiredSkills": ["post-to-linkedin", "render-remotion-video"] }
```

This is the most powerful extensibility pattern — it lets you package repeatable workflows as skills that any agent can use, rather than embedding everything in the agent's AGENTS.md instructions.

\newpage

# Part 5: Installing Skills for LinkedIn, X, and Remotion

Skills are reusable packages of instructions + reference docs that teach agents specific capabilities. Instead of writing long AGENTS.md instructions for each integration, create a skill once and install it on any agent that needs it.

## Skill file structure

```
skills/
  post-to-linkedin/
    SKILL.md                    # Main skill instructions
    references/
      linkedin-api-reference.md # API docs the agent can read
      post-formats.md           # Template gallery

  post-to-x/
    SKILL.md
    references/
      x-api-reference.md
      thread-formats.md

  render-remotion-video/
    SKILL.md
    references/
      remotion-lambda-api.md
      composition-templates.md
```

## LinkedIn posting skill

Create this in your repo or the agent's workspace:

### `skills/post-to-linkedin/SKILL.md`

```markdown
# Post to LinkedIn Skill

Post content to a LinkedIn organization page via the LinkedIn API.

## Prerequisites

- Company secret `linkedin-access-token` must exist (OAuth 2.0 token)
- Company secret `linkedin-org-urn` must exist (e.g., `urn:li:organization:12345`)

## How to post

Read the access token and org URN from environment (injected via secret_ref):

    curl -X POST "https://api.linkedin.com/v2/ugcPosts" \
      -H "Authorization: Bearer $LINKEDIN_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "author": "'"$LINKEDIN_ORG_URN"'",
        "lifecycleState": "PUBLISHED",
        "specificContent": {
          "com.linkedin.ugc.ShareContent": {
            "shareCommentary": { "text": "YOUR POST TEXT" },
            "shareMediaCategory": "NONE"
          }
        },
        "visibility": {
          "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
        }
      }'

## With an image or video

Upload media first, then reference it:

    # 1. Register upload
    curl -X POST "https://api.linkedin.com/v2/assets?action=registerUpload" \
      -H "Authorization: Bearer $LINKEDIN_ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "registerUploadRequest": {
          "owner": "'"$LINKEDIN_ORG_URN"'",
          "recipes": ["urn:li:digitalmediaRecipe:feedshare-video"],
          "serviceRelationships": [{
            "identifier": "urn:li:userGeneratedContent",
            "relationshipType": "OWNER"
          }]
        }
      }'

    # 2. Upload the file to the URL returned in step 1
    # 3. Create the post with shareMediaCategory: "VIDEO" and the asset URN

For complete API reference, read: `references/linkedin-api-reference.md`

## Rules

- Never post more than 2x per day on LinkedIn (platform best practice)
- Always check if the token is valid before posting (GET /v2/me)
- If you get 401, mark the issue as blocked and tag the board to refresh the token
- All OTC/GEAT-related posts must be factual — no forward-looking statements
```

## X (Twitter) posting skill

### `skills/post-to-x/SKILL.md`

```markdown
# Post to X Skill

Post content to X (Twitter) via the X API v2.

## Prerequisites

- Company secret `x-api-key` (API Key)
- Company secret `x-api-secret` (API Secret)
- Company secret `x-access-token` (Access Token)
- Company secret `x-access-token-secret` (Access Token Secret)

## How to post a tweet

X API v2 uses OAuth 1.0a. Generate the authorization header or use
a helper. Simplest approach — use the v2 endpoint with Bearer token:

    curl -X POST "https://api.x.com/2/tweets" \
      -H "Authorization: Bearer $X_BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{ "text": "YOUR TWEET TEXT" }'

## Posting a thread

Post the first tweet, capture its ID, then reply to it:

    # First tweet
    TWEET_ID=$(curl -sS -X POST "https://api.x.com/2/tweets" \
      -H "Authorization: Bearer $X_BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{ "text": "1/ Thread starts here..." }' | jq -r '.data.id')

    # Reply
    curl -X POST "https://api.x.com/2/tweets" \
      -H "Authorization: Bearer $X_BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{ "text": "2/ Continuation...", "reply": { "in_reply_to_tweet_id": "'"$TWEET_ID"'" }}'

## With media

    # 1. Upload media via v1.1 media endpoint
    MEDIA_ID=$(curl -X POST "https://upload.twitter.com/1.1/media/upload.json" \
      -H "Authorization: OAuth ..." \
      -F "media=@/tmp/video.mp4" | jq -r '.media_id_string')

    # 2. Post with media
    curl -X POST "https://api.x.com/2/tweets" \
      -H "Authorization: Bearer $X_BEARER_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{ "text": "Check out this video!", "media": { "media_ids": ["'"$MEDIA_ID"'"] }}'

## Rules

- Respect rate limits: 300 tweets/3 hours for app-level auth
- Use $GEAT cashtag in investor-relevant posts
- Threads for depth, single tweets for engagement
- If posting video, wait for media processing to complete before posting
```

## Remotion video rendering skill

### `skills/render-remotion-video/SKILL.md`

```markdown
# Render Remotion Video Skill

Create and render programmatic videos using Remotion Lambda.

## Prerequisites

- Company secret `remotion-api-key` (Remotion Cloud API key or AWS credentials)
- A deployed Remotion bundle URL (the compiled React app)
- Templates stored in your workspace at `./templates/remotion/`

## Available templates

Check `./templates/remotion/` for existing compositions:

- `weekly-stats.tsx` — animated chart with data overlay
- `product-spotlight.tsx` — feature highlight with text + screenshot
- `company-news.tsx` — press release style with logo + headline
- `data-insight.tsx` — WallStreetStats data visualization

## How to render

1. Pick or create a composition
2. Call the Remotion Lambda API:

    curl -X POST "https://remotion-lambda-endpoint/render" \
      -H "Authorization: Bearer $REMOTION_API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "composition": "WeeklyStats",
        "serveUrl": "https://your-bundle-url/bundle.js",
        "inputProps": {
          "title": "Top Sentiment Shifts This Week",
          "data": [
            {"ticker": "$AAPL", "shift": "+12%"},
            {"ticker": "$GEAT", "shift": "+8%"}
          ]
        },
        "codec": "h264",
        "imageFormat": "jpeg",
        "outputFormat": "mp4",
        "durationInFrames": 450,
        "fps": 30
      }'

3. Poll for completion:

    curl "https://remotion-lambda-endpoint/render/$RENDER_ID/status" \
      -H "Authorization: Bearer $REMOTION_API_KEY"

4. When done, download the MP4:

    curl -o /tmp/output.mp4 "$RENDER_OUTPUT_URL"

5. Attach to the issue:

    curl -X POST "$PAPERCLIP_API_URL/api/companies/$COMPANY_ID/issues/$ISSUE_ID/attachments" \
      -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
      -H "X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID" \
      -F "file=@/tmp/output.mp4"

## Creating new compositions

Write standard Remotion React components. Key constraints:
- Keep compositions pure — all data via inputProps, no external fetches during render
- Target 1080x1080 (square) for LinkedIn, 1920x1080 for X
- 15-30 seconds is the sweet spot for social media video
- Use the Remotion spring() function for smooth animations
```

## Installing skills on agents

Once skills are created, install them on agents via the Paperclip API:

### Option A — Import from your repo

If skills live in the repo as files, use the company skills import:

```js
fetch("/api/companies/COMPANY_ID/skills/import", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    source: "local",
    path: "/paperclip/instances/prod/skills/COMPANY_ID/__runtime__/"
  }),
}).then(r => r.json()).then(console.log);
```

### Option B — Scan project workspaces

If skills are in a project workspace, scan for them:

```js
fetch("/api/companies/COMPANY_ID/skills/scan-projects", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
}).then(r => r.json()).then(console.log);
```

### Option C — CEO installs during hiring

When the CEO hires an agent, include `desiredSkills` in the hire request:

```json
{
  "name": "CMO",
  "desiredSkills": ["post-to-linkedin", "post-to-x", "render-remotion-video"],
  ...
}
```

### Sync skills on existing agents

```js
fetch("/api/agents/CMO_AGENT_ID/skills/sync", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    desiredSkills: ["post-to-linkedin", "post-to-x", "render-remotion-video"]
  }),
}).then(r => r.json()).then(console.log);
```

After syncing, the agent can invoke the skill via `Skill` tool calls in its heartbeats — the skill's SKILL.md becomes available as context.

\newpage

# Appendix: Key Concepts

| Term | What it means |
|---|---|
| **Board member** | Human user who signs in to the dashboard |
| **Agent** | AI worker (CEO, CMO, etc.) that runs heartbeats |
| **Heartbeat** | One execution cycle — wake, check work, act, exit |
| **Issue** | Work item assigned to an agent |
| **Goal** | Strategic objective that issues roll up to |
| **Project** | Container for related issues |
| **Routine** | Recurring task with a schedule trigger |
| **Secret** | Encrypted credential stored in Paperclip |
| **Approval** | Request needing board sign-off |
| **Run** | One heartbeat execution with transcript and cost |
| **PARA memory** | Agent's personal knowledge system |

---

*GreetEat Corp (OTC: GEAT) — [greeteat.com](https://greeteat.com)*

*Written for Paperclip commit `ac664df` (between v2026.403.0 and v2026.410.0). Paperclip is evolving rapidly — verify against your deployed version.*

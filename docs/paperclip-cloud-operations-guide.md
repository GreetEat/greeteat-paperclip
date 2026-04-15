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

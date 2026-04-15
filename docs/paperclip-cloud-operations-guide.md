---
title: "Paperclip Operations Guide"
subtitle: "Board operations, integrations, and advanced workflows"
author: "GreetEat Corp (OTC: GEAT)"
date: "April 2026"
---

\newpage

# About this guide

This guide covers operating [Paperclip](https://github.com/paperclipai/paperclip) — the open-source AI agent orchestration platform — from a board member's perspective.

**Version**: written for Paperclip commit `ac664df` (April 10, 2026, between `v2026.403.0` and `v2026.410.0`). Paperclip is evolving rapidly — features, API endpoints, and UI may change between versions.

**Audience**: board members, operators, and anyone managing agents and work through the Paperclip dashboard.

**Published by**: GreetEat Corp — [greeteat.com](https://greeteat.com) | OTC: GEAT

\newpage

# Part 1: Board Operations

## Quick reference

| I want to... | How |
|---|---|
| See what agents are doing | Dashboard → company → Live Runs |
| Give an agent work | Create an issue and assign it |
| Hire a new agent | Ask the CEO agent (via an issue) |
| Invite a new board member | See "Inviting people" section below |
| Review agent output | Agent page → Runs tab → click a run |
| Set company strategy | Create goals, then create issues linked to them |
| Check spending | Dashboard → company → Budget / Costs view |

## Understanding the hierarchy

```
Board members (humans)
  └─ sign in, create goals, assign work, approve hires
      │
Goals (strategy)
  └─ what you want to achieve ("Build LinkedIn presence")
      │
Projects (organization)
  └─ group related work ("Social Media Strategy")
      │
Issues (work items)
  └─ specific tasks ("Draft 5 LinkedIn posts")
      │
Agents (workers)
  └─ AI agents that do the work (CEO, CMO, Head of Research, etc.)
```

**Key concept**: agents only work on issues that are **assigned to them**. They don't pick up work on their own. You (or the CEO agent) must create an issue and assign it.

## Creating goals

Goals are strategic objectives that organize your work. They don't directly trigger agent activity — they provide context and structure.

1. Dashboard → **Goals** (left sidebar)
2. Click **New Goal**
3. Fill in:
   - **Title**: clear, outcome-oriented (e.g., "Grow GreetEat user base to 10K MAU")
   - **Level**: `company` (top-level strategy), `team`, `agent`, or `task`
   - **Status**: `planned` or `active`
4. Click **Create**

**Tip**: create a goal hierarchy. Example:

- Company goal: "Establish market presence"
  - Team goal: "Build social media following"
    - Agent goal: "LinkedIn content calendar"

## Assigning work to agents

This is the primary way you get things done.

1. Dashboard → **Issues** or click **New Issue**
2. Fill in:
   - **Title**: specific and actionable
   - **Description**: the brief — be specific about deliverables, constraints, audience
   - **Assignee**: pick the right agent (see below)
   - **Priority**: `critical`, `high`, `medium`, `low`
   - **Goal**: link to the relevant goal (optional but recommended)
   - **Project**: link to the relevant project (optional)
3. Click **Create**

### Which agent to assign to

| Work type | Assign to |
|---|---|
| Strategy, delegation, cross-functional coordination | **CEO** |
| Marketing, content, social media, brand, growth | **CMO** |
| Market research, competitive analysis, user insights | **Head of Product Research** |
| Technical work, engineering tasks | **CTO** (if hired) |

### Writing good issue descriptions

**Good** (specific, actionable):

> Research the top 5 competitors to GreetEat's virtual meals platform.
>
> Deliverables:
> - Competitive matrix (features, pricing, market position)
> - Gap analysis: what do they offer that we don't?
> - Opportunity list: where can GreetEat differentiate?
>
> Focus on B2B-oriented competitors.

**Bad** (vague):

> Look into our competitors.

### The CEO delegation pattern

When you assign work to the **CEO**, it doesn't do the work itself. Instead:

1. CEO reads the issue
2. CEO identifies which department owns it (marketing → CMO, research → Head of Research, etc.)
3. CEO creates a **subtask** assigned to the right agent
4. CEO comments on your issue explaining who it delegated to and why
5. The assigned agent wakes up and does the actual work

This is by design — the CEO is a coordinator, not an individual contributor.

## Watching agents work

### Live view

Dashboard → your company → **Live Runs** shows active agent heartbeats in real time.

### Run history

Agent page → **Runs** tab shows completed runs with:

- **Transcript**: what the agent thought, what tools it used, what it decided
- **Invocation details**: the command, working directory, environment
- **Cost**: how much the run spent on LLM tokens

### Issue comments

Agents comment on their issues as they work. Check the **Comments** tab on any issue to see status updates, blockers, and deliverables.

## Hiring new agents

You don't create agents directly. Instead, you ask the CEO to hire:

1. Create an issue assigned to **CEO**:
   - Title: "Hire a [role] for [purpose]"
   - Description: what the role should do, what skills it needs
2. The CEO uses its hiring skill to submit a hire request
3. If your company requires board approval for hires:
   - You'll see a pending **Approval** in the dashboard
   - Review and click **Approve** or **Request Changes**
4. Once approved, the new agent appears in the agent list

### Agent instructions

Every agent has instruction files that define its persona and behavior:

- **AGENTS.md** — main instructions: what the agent does, delegation rules
- **HEARTBEAT.md** — the checklist it runs every time it wakes up
- **SOUL.md** — persona, voice, strategic posture
- **TOOLS.md** — notes about tools it has learned to use

To view/edit: Agent page → **Instructions** tab. Make changes → floating **Save** button appears → click Save.

## Inviting a new board member

> **Current limitation**: the dashboard doesn't have a UI button for
> inviting human users. Use the method below.

1. **Ask your platform operator** to temporarily enable sign-up (~1 minute)

2. **Create an invite** — open browser developer tools (Cmd+Option+J on Mac), paste in the Console tab:

   ```js
   fetch("/api/companies/YOUR_COMPANY_ID/invites", {
     method: "POST",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({ allowedJoinTypes: "human" }),
   })
     .then(r => r.json())
     .then(j => prompt("Copy this invite URL:", location.origin + j.inviteUrl));
   ```

3. **Send the URL** to the invitee. **It expires in 10 minutes.**

4. Invitee opens the URL → signs up → clicks Accept

5. **You approve** the join request (in the dashboard or via dev tools)

6. **Ask your operator to re-lock sign-up** when done

## Approving agent requests

When an approval is pending:

1. You'll see a notification in the dashboard
2. Click into the **Approvals** section
3. Review: what's being asked, why, estimated cost/impact
4. Click **Approve** or **Request Changes** (with a comment explaining what to fix)

\newpage

# Part 2: 3rd Party Integrations

## Connecting agents to external services

Agents can interact with LinkedIn, X/Twitter, Slack, analytics platforms, and any service with an API. The pattern is always:

1. **You (human) obtain API credentials** — one-time browser OAuth flow
2. **Store them as Paperclip secrets** — encrypted at rest, agents access them at runtime
3. **Agent calls the external API** — using curl with the decrypted credentials

### Obtaining credentials

| Service | Where to get them | What you need |
|---|---|---|
| **LinkedIn** | [linkedin.com/developers](https://www.linkedin.com/developers/) → Create App | OAuth 2.0 access token + organization URN |
| **X (Twitter)** | [developer.x.com](https://developer.x.com/) → Developer Portal | API Key, API Secret, Access Token |
| **Slack** | [api.slack.com/apps](https://api.slack.com/apps) → Create App | Bot token (`xoxb-...`) |
| **Google Analytics** | Google Cloud Console → APIs & Services | Service account key or OAuth token |

### Storing credentials and configuring agents (via the dashboard)

Paperclip has built-in secret management with a UI in the agent configuration page:

1. Go to the **agent page** (e.g., CMO) → **Configuration** tab
2. Scroll to the **Environment Variables** section
3. Click **Add Variable**
4. Enter the variable name (e.g., `LINKEDIN_ACCESS_TOKEN`)
5. Switch the source from **"Plain"** to **"Secret"**
6. Either select an existing secret from the dropdown, or click **Create New Secret**:
   - Name: `linkedin-access-token`
   - Value: paste your OAuth token
   - The value is encrypted at rest — only the secret ID is stored in the config
7. Click **Save** (floating button at the top)

The agent reads `$LINKEDIN_ACCESS_TOKEN` from its environment during every heartbeat. When you rotate the token later, update the secret value — agents referencing `"version": "latest"` automatically get the new value on their next run.

### Token lifecycle

API tokens expire. Plan for it:

- **LinkedIn**: tokens expire after 60 days
- **X**: tokens don't expire but can be revoked
- **Slack**: bot tokens don't expire unless the app is uninstalled

Set up a monthly **routine** (see next section) that tests each credential and alerts the board if any are about to expire.

## Scheduling recurring tasks (routines)

Routines let you run tasks on a schedule without manually creating issues each time.

### How routines work

1. You define a routine: title, description, assigned agent, schedule
2. When the schedule fires, Paperclip creates an **issue** automatically
3. The assigned agent wakes up and works on the issue in its normal flow
4. Agent marks the issue done when finished

### Setting up a routine

**Option A — Ask the CEO**: create an issue "Set up a Mon/Wed/Fri LinkedIn posting routine for the CMO"

**Option B — Create it yourself** via browser dev tools:

```js
fetch("/api/companies/YOUR_COMPANY_ID/routines", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    title: "LinkedIn weekly posts",
    description: "Check content calendar, pick next post, publish via API",
    assigneeAgentId: "CMO_AGENT_ID",
    projectId: "YOUR_PROJECT_ID",
    status: "active"
  }),
}).then(r => r.json()).then(j => {
  // Add a schedule trigger
  fetch("/api/routines/" + j.id + "/triggers", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: "schedule",
      cronExpression: "0 9 * * 1,3,5",
      timezone: "America/New_York"
    }),
  });
  console.log("Routine created:", j.id);
});
```

### Useful schedules

| Schedule | Cron expression |
|---|---|
| Mon/Wed/Fri at 9am | `0 9 * * 1,3,5` |
| Every weekday at 9am | `0 9 * * 1-5` |
| Every Monday at 10am | `0 10 * * 1` |
| Twice daily (9am + 3pm) | `0 9,15 * * 1-5` |
| First of every month | `0 9 1 * *` |

### Routine variables and templates

Routine titles and descriptions support `{{variable}}` placeholders that get filled in when the routine fires:

**Built-in variable**: `{{date}}` — expands to today's date (YYYY-MM-DD)

**Custom variables**: define your own with types (`text`, `textarea`, `number`, `boolean`, `select`)

**Example** — a routine with dynamic title:

```json
{
  "title": "Social media post for {{date}} — {{platform}}",
  "description": "Post the next item from the content calendar.\nPlatform: {{platform}}\nContent type: {{content_type}}",
  "variables": [
    { "name": "platform", "type": "select", "options": ["linkedin", "x", "both"], "defaultValue": "linkedin", "required": true },
    { "name": "content_type", "type": "select", "options": ["text", "image", "video", "thread"], "defaultValue": "text", "required": true }
  ]
}
```

When this fires on April 14, the created issue becomes:

- Title: "Social media post for 2026-04-14 — linkedin"
- Description includes the interpolated platform and content type

This is powerful for recurring posts — each fired issue gets today's date automatically, so the agent knows exactly which day's content to post.

### How secrets, routines, and agents work together

Each piece has a distinct job:

```
Routine         → WHAT to do + WHEN (title, description, schedule)
Agent config    → HOW to authenticate (env vars with encrypted secret refs)
Agent skills    → HOW to call the API (curl commands, API formats)
```

Secrets live in the agent's environment, not in the routine. The routine just creates the issue — the agent already has the API tokens it needs when it wakes up.

### Managing routines

- **Pause**: stops firing, can resume later
- **Resume**: reactivates a paused routine
- **Archive**: permanent — cannot be reactivated
- **Manual run**: fire immediately regardless of schedule

\newpage

# Part 3: Example Workflows

## Social media campaign

### One-time setup (~30 minutes)

1. **Get LinkedIn/X credentials** from their developer portals
2. **Store as Paperclip secrets** (see Part 2)
3. **Create a goal**: "Build social media presence" (company level)
4. **Create a project**: "Social Media" linked to the goal

### Content creation

5. **Create an issue for CEO**: "Develop LinkedIn + X content strategy"
6. CEO delegates to CMO → CMO researches, drafts content calendar and posts
7. **You review** the drafts in the issue comments
8. Iterate via comments until satisfied

### Automated posting

9. **Set up posting routines**: Mon/Wed/Fri 9am for LinkedIn, daily for X
10. Each routine fire → creates an issue → CMO reads calendar → posts → marks done
11. **You monitor** the issue feed for posting confirmations

## Competitive research

1. Create an issue for **Head of Product Research**:

> Competitive analysis: virtual business meals market
>
> Deliverables:
> 1. Market map: who are the players?
> 2. Feature comparison matrix
> 3. Pricing intelligence
> 4. SWOT analysis vs top 3 competitors
> 5. Recommendation: where should we invest to differentiate?

2. Agent researches via web search, compiles structured report as issue comments
3. Review findings, request deeper dives via follow-up comments

## Data-driven video content with Remotion

Agents can create programmatic video content using [Remotion](https://www.remotion.dev/) — a React-based video framework.

### How it works

```
Routine fires → CMO agent wakes
  → reads content calendar
  → writes a video composition (React code)
  → renders to MP4 via Remotion Lambda (serverless)
  → attaches video to issue for board review
  → posts to LinkedIn/X with the video
```

### One-time setup

1. **Deploy Remotion Lambda** to AWS (or use Remotion Cloud)
2. **Store Remotion API credentials** as Paperclip secrets
3. **Create video templates** — reusable React compositions for different content types:
   - Weekly stats animation (data-driven charts)
   - Product spotlight (feature highlight + screenshots)
   - Company news (press release style)
   - Data insight (WallStreetStats visualizations)

### Steady-state flow

- Routine fires Mon/Wed/Fri
- CMO picks a template + fills in current data
- Remotion Lambda renders a 15-30 second MP4 (~$0.01-0.05 per render)
- CMO attaches the video to the issue for optional board review
- CMO posts to LinkedIn/X with the video + caption

### Cost

| Component | Cost |
|---|---|
| Video rendering (15s, per video) | ~$0.01-0.05 |
| LLM (agent writing + decision-making) | ~$0.10-0.50 per heartbeat |
| Storage (MP4 files) | ~$0.02/GB/month |
| Social media APIs | Free (within rate limits) |

A 3x/week video posting routine: **~$5-15/month total**.

## Recurring social media posting

### LinkedIn — 3x weekly posting routine

**One-time setup:**

1. Store LinkedIn credentials via agent config UI (see Part 2)
2. Have the CMO create a content calendar (assign an issue for this first)
3. Create the routine:

```
Title:       "LinkedIn post for {{date}}"
Description: "Check the content calendar for today's scheduled LinkedIn post.
              If one is scheduled:
              1. Read the post content from the calendar
              2. Post to LinkedIn via the API
              3. Confirm with a link to the live post
              If nothing is scheduled for today, comment 'No post scheduled' and mark done."
Agent:       CMO
Project:     Social Media
Schedule:    Mon/Wed/Fri at 9am ET (cron: 0 9 * * 1,3,5)
```

The `{{date}}` variable means each issue is automatically scoped to today — the CMO doesn't need to figure out which day's content to post.

### X (Twitter) — daily posting routine

```
Title:       "X post for {{date}}"
Description: "Post today's X content from the content calendar.
              For data-driven posts (WallStreetStats insights):
              1. Fetch the latest sentiment data
              2. Pick the most interesting shift
              3. Write a tweet with the $GEAT cashtag if relevant
              4. Post via X API
              If a thread is scheduled, post all parts in sequence."
Agent:       CMO
Schedule:    Every weekday at 10am ET (cron: 0 10 * * 1-5)
```

### Reading account stats from LinkedIn and X

Set up a weekly analytics routine so the CMO tracks what's working:

```
Title:       "Social media analytics report — week of {{date}}"
Description: "Pull performance data from LinkedIn and X for the past 7 days.

              LinkedIn:
              - GET https://api.linkedin.com/v2/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=$LINKEDIN_ORG_URN&timeIntervals.timeGranularityType=DAY&timeIntervals.timeRange.start=LAST_7_DAYS_EPOCH_MS
              - Extract: impressions, clicks, engagement rate, follower change

              X/Twitter:
              - GET https://api.x.com/2/users/{user_id}/tweets?tweet.fields=public_metrics&start_time=LAST_7_DAYS_ISO
              - Extract: impressions, likes, retweets, replies per post

              Deliverables:
              1. Summary table: metric | this week | last week | change
              2. Top performing post (highest engagement)
              3. Recommendation: what to do more/less of next week

              Post the report as a comment on this issue."
Agent:       CMO (or Head of Product Research for deeper analysis)
Schedule:    Every Monday at 8am ET (cron: 0 8 * * 1)
```

This creates a weekly issue every Monday. The agent pulls stats, compares week-over-week, and posts a structured report. Board members read the issue comments for insights.

### Combining posting + analytics for optimization

The analytics routine can feed back into the content strategy:

1. **Monday 8am**: Analytics routine fires → CMO reviews last week's performance
2. **Monday 9am**: CMO updates the content calendar based on what worked
3. **Mon/Wed/Fri 10am**: Posting routines fire → CMO posts optimized content
4. **Repeat**: data-driven content improvement loop, fully automated

To set this up, just create the two routines (analytics + posting) and make sure the analytics one fires BEFORE the posting ones. The CMO will naturally read the analytics report before deciding what to post.

## Multi-agent content pipeline

For production workflows, chain agents in a pipeline:

1. **Head of Product Research** → generates market data + insights
2. **CMO** → turns insights into content strategy + drafts
3. **Board** → reviews and approves
4. **CMO** → publishes (routine-triggered)

Set this up with a parent issue ("Q2 content campaign") and subtasks that cascade through the chain.

## Webhook-triggered workflows

External systems can trigger agent work by POSTing to a webhook URL:

- **GitHub push** → agent reviews the code change
- **Stripe payment** → agent sends a thank-you or updates records
- **CRM lead created** → agent researches the company
- **Monitoring alert** → agent investigates the issue

Create a webhook trigger on a routine, give the URL to the external system, and the assigned agent handles each incoming event.

\newpage

# Part 4: Installing Skills on Agents

Skills are reusable packages that teach agents specific capabilities. Instead of writing long instructions for each integration, create a skill once and install it on any agent.

## What's a skill?

A skill is a folder with:

```
skills/
  post-to-linkedin/
    SKILL.md               # Instructions the agent follows
    references/            # Supporting docs (API reference, templates)
```

When installed on an agent, the SKILL.md becomes available as context during heartbeats. The agent can invoke the skill by name.

## Available skill ideas

| Skill | What it teaches the agent |
|---|---|
| `post-to-linkedin` | LinkedIn API posting: text posts, image/video uploads, organization pages |
| `post-to-x` | X API v2: tweets, threads, media attachments, cashtag usage |
| `render-remotion-video` | Remotion Lambda: write compositions, render MP4s, manage templates |
| `analyze-market-data` | Web research patterns, competitive matrix templates, SWOT frameworks |
| `manage-content-calendar` | Calendar file format, scheduling logic, cross-platform coordination |

## Installing skills on agents

### When hiring (recommended)

Include `desiredSkills` in the hire request. The CEO agent can do this automatically when it uses the `paperclip-create-agent` skill:

```json
{
  "name": "CMO",
  "desiredSkills": ["post-to-linkedin", "post-to-x", "render-remotion-video"]
}
```

### On existing agents

Sync skills via the API:

```js
fetch("/api/agents/AGENT_ID/skills/sync", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    desiredSkills: ["post-to-linkedin", "post-to-x"]
  }),
}).then(r => r.json()).then(console.log);
```

### Creating custom skills

Write a `SKILL.md` with:
1. **Prerequisites**: what secrets/config must exist
2. **How to**: step-by-step API calls with curl examples
3. **Rules**: rate limits, compliance guardrails, error handling
4. **References**: link to supporting docs in the `references/` folder

Install company-wide via:

```js
fetch("/api/companies/COMPANY_ID/skills/import", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ source: "local", path: "/path/to/skills/" }),
}).then(r => r.json()).then(console.log);
```

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
| **Skill** | Reusable capability package installed on agents |
| **Approval** | Request needing board sign-off |
| **Run** | One heartbeat execution with transcript and cost |
| **PARA memory** | Agent's personal knowledge system |

---

*GreetEat Corp (OTC: GEAT) — [greeteat.com](https://greeteat.com)*

*Written for Paperclip commit `ac664df` (April 10, 2026, between v2026.403.0 and v2026.410.0). Paperclip is evolving rapidly — verify against your deployed version.*

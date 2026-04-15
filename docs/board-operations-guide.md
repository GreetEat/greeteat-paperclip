# Paperclip Board Operations Guide

> **For**: board members (non-technical operators) of the GreetEat Paperclip deployment.
> **Not for**: infrastructure setup (see `specs/001-deploy-gcp-public-auth/quickstart.md` for that).
>
> This guide covers common tasks you'll do from the Paperclip dashboard
> at your deployment URL.

---

## Quick reference

| I want to... | Go to |
|---|---|
| See what agents are doing | Dashboard → company → Live Runs |
| Give an agent work | Create an issue and assign it |
| Hire a new agent | Ask the CEO agent (via an issue) |
| Invite a new board member | [Inviting people](#inviting-a-new-board-member) (requires workaround) |
| Review agent output | Click an agent → Runs tab → click a run |
| Set company strategy | Create goals, then create issues linked to them |
| Stop an agent | Agent page → pause/stop controls |
| Check spending | Dashboard → company → Budget / Costs view |

---

## Understanding the hierarchy

```
Board members (humans)
  └─ sign in via the dashboard, create goals, assign work, approve hires
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

---

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

---

## Assigning work to agents

This is the primary way you get things done.

1. Dashboard → **Issues** or click **New Issue** (top right, or from within a project)
2. Fill in:
   - **Title**: specific and actionable (e.g., "Research top 5 competitors for GreetEat")
   - **Description**: the brief. Be specific about deliverables, constraints, audience. The more context you give, the better the agent's output.
   - **Assignee**: pick the right agent:
     - **CEO** — for strategy, delegation, hiring, cross-functional coordination. The CEO will typically delegate to a report rather than doing the work itself.
     - **CMO** — for marketing, content, social media, brand, growth
     - **Head of Product Research** — for market research, competitive analysis, user insights
   - **Priority**: `critical`, `high`, `medium`, `low`
   - **Goal**: link to the relevant goal (optional but recommended)
   - **Project**: link to the relevant project (optional)
3. Click **Create**

The assigned agent will be woken up and start working. Watch the **Live Runs** view to see it in action.

### Writing good issue descriptions

**Good** (specific, actionable):
```
Research the top 5 competitors to GreetEat's virtual meals platform.

Deliverables:
- Competitive matrix (features, pricing, market position)
- Gap analysis: what do they offer that we don't?
- Opportunity list: where can GreetEat differentiate?

Focus on B2B-oriented competitors. Include any that partner with
food delivery services.
```

**Bad** (vague):
```
Look into our competitors.
```

### The CEO delegation pattern

When you assign work to the **CEO**, it doesn't do the work itself. Instead:

1. CEO reads the issue
2. CEO identifies which department owns it (marketing → CMO, research → Head of Research, etc.)
3. CEO creates a **subtask** assigned to the right agent
4. CEO comments on your issue explaining who it delegated to and why
5. The report agent wakes up and does the actual work

This is by design — the CEO is a coordinator, not an individual contributor.

---

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

---

## Hiring new agents

You don't create agents directly. Instead, you ask the CEO to hire:

1. Create an issue assigned to **CEO**:
   - Title: "Hire a [role] for [purpose]"
   - Description: what the role should do, what skills it needs, what it reports to
2. The CEO uses the `paperclip-create-agent` skill to submit a hire request
3. If your company has board approval required for hires:
   - You'll see a pending **Approval** in the dashboard
   - Review and click **Approve** or **Request Changes**
4. Once approved, the new agent appears in the agent list

### Agent instructions

Every agent has instruction files that define its persona and behavior:

- **AGENTS.md** — main instructions: what the agent does, how it works, delegation rules
- **HEARTBEAT.md** — the checklist it runs every time it wakes up
- **SOUL.md** — persona, voice, strategic posture
- **TOOLS.md** — notes about tools it has learned to use

**Current limitation**: when a new agent is hired, it gets a generic 3-line default instruction set. The instructions you see may be minimal until someone customizes them.

To view/edit instructions: Agent page → **Instructions** tab. Edit in the text editor → a floating **Save** button appears at the top when you've made changes.

If you see **"Instructions root does not exist"**, ask your platform operator to check the agent's instruction files. This is a known issue with Cloud Run deployments.

---

## Inviting a new board member

> **This is the biggest gotcha.** Paperclip's dashboard doesn't have a UI for
> inviting human users. The API supports it, but you need to use the browser
> developer tools (or ask your platform operator to do it).

### The process

1. **Ask your platform operator** to temporarily enable sign-up (they flip an environment variable — takes ~1 minute)

2. **Create an invite** — in the browser, press `Cmd+Option+J` (Mac) or `Ctrl+Shift+J` (Windows) to open developer tools, go to the **Console** tab, and paste:

   ```js
   fetch("/api/companies/93345557-ceff-404d-96e0-9b0d54d21046/invites", {
     method: "POST",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({ allowedJoinTypes: "human" }),
   })
     .then(r => r.json())
     .then(j => prompt("Copy this invite URL:", location.origin + j.inviteUrl));
   ```

3. A dialog appears with the invite URL. **Copy it immediately.**

4. **Send the URL to the invitee** via Slack, Signal, text, or in person. **The invite expires in 10 minutes.**

5. The invitee opens the URL, signs up with their email + password, and clicks **Accept**.

6. **You approve the join request** — either in the dashboard (if there's a pending requests view) or via developer tools:

   ```js
   // List pending requests
   fetch("/api/companies/93345557-ceff-404d-96e0-9b0d54d21046/join-requests?status=pending_approval")
     .then(r => r.json())
     .then(console.log);

   // Approve (replace REQ_ID with the id from the list)
   fetch("/api/companies/93345557-ceff-404d-96e0-9b0d54d21046/join-requests/REQ_ID/approve",
     { method: "POST", headers: {"Content-Type":"application/json"}, body: "{}" })
     .then(r => r.json())
     .then(console.log);
   ```

7. **Ask your operator to re-lock sign-up** when done.

### Why it's complicated

Paperclip was designed for local developer use where the developer IS the only user. The multi-user invite flow exists in the API but the dashboard doesn't expose it yet. This is on the list of upstream issues to fix.

---

## Approving agent requests

Agents sometimes need board approval before proceeding:

- **Hiring a new agent** — if the company setting "Require board approval for new agents" is on
- **Budget requests** — if an agent asks to spend above its limit

When an approval is pending:

1. You'll see a notification in the dashboard
2. Click into the **Approvals** section
3. Review the request: what's being asked, why, estimated cost/impact
4. Click **Approve** or **Request Changes** (with a comment explaining what to fix)

When you approve, the requesting agent gets woken up and continues its work.

---

## Setting up a social media campaign (example workflow)

Here's a real-world example of how to use goals + issues + agents together:

### 1. Create the goal

- Title: "Establish GreetEat social media presence"
- Level: company
- Status: active

### 2. Create a project

- Name: "Social Media Launch"
- Link to the goal above

### 3. Create issues for the CEO

Issue 1:
- Title: "Develop LinkedIn social strategy and draft first 5 posts"
- Assign to: CEO
- Goal: "Establish GreetEat social media presence"
- Description: (be specific about products, audience, tone, deliverables)

Issue 2:
- Title: "Develop X (Twitter) strategy and draft first 5 posts"
- Same structure

### 4. Watch it cascade

- CEO wakes up, reads both issues
- CEO delegates LinkedIn issue → CMO (subtask)
- CEO delegates X issue → CMO (subtask)
- CMO wakes up, works on LinkedIn strategy first (or both in parallel across heartbeats)
- CMO posts research findings and draft posts as issue comments
- Issues move through: `todo` → `in_progress` → `in_review` → `done`

### 5. Review and iterate

- Read the CMO's draft posts in the issue comments
- If you want changes, comment on the issue: "Make post #3 more data-driven" — the CMO will be woken and address your feedback
- When satisfied, mark the issue as `done` (or the agent does it)

---

## Getting research done (example workflow)

### Create an issue for the Head of Product Research

- Title: "Competitive analysis: virtual business meals market"
- Assign to: Head of Product Research
- Description:
  ```
  Analyze the competitive landscape for virtual business meals platforms.

  Deliverables:
  1. Market map: who are the players? (direct competitors + adjacent)
  2. Feature comparison matrix
  3. Pricing intelligence (where publicly available)
  4. SWOT analysis for GreetEat vs top 3 competitors
  5. Recommendation: where should we invest to differentiate?

  Focus on the US/Canada market. Include any companies that combine
  video conferencing with food delivery or corporate catering.
  ```

The Head of Product Research will use web search, curl for website scraping, and its knowledge to compile the report. Results appear as issue comments with structured markdown.

---

## Troubleshooting

### Agent isn't doing anything

- Check if the agent is **paused** (agent page → status)
- Check if the issue is actually **assigned** to that agent
- Check if there's already an **active run** — agents don't run in parallel by default (`maxConcurrentRuns: 1`)
- Try clicking **Wake Now** on the agent page to force a heartbeat

### Agent is stuck or blocked

- Look at the agent's **latest run** for errors
- Check if the issue status is `blocked` — the agent should have commented explaining why
- Try commenting on the issue with guidance — the agent will be woken and read your comment

### Agent's instructions are empty

- Check the **Instructions** tab on the agent page
- If it says "Instructions root does not exist" — ask your platform operator to create the instruction files
- If the editor is empty — you can paste content directly and click Save

### "Link may be expired, revoked or already used" when accepting an invite

- Company invites expire in **10 minutes**. Create a new one.
- Make sure you're using the full URL (no truncation)

### Can't find the invite/operator settings in the dashboard

- **This is a known Paperclip limitation.** Human invite creation isn't in the dashboard UI yet. Use the developer tools console method described above.

---

## Key concepts glossary

| Term | What it means |
|---|---|
| **Board member** | A human user who signs in to the dashboard |
| **Agent** | An AI worker (CEO, CMO, etc.) that runs heartbeats |
| **Heartbeat** | One execution cycle of an agent — wake up, check work, do something, exit |
| **Issue** | A work item assigned to an agent (like a Jira ticket) |
| **Goal** | A strategic objective that issues roll up to |
| **Project** | A container for related issues, linked to goals |
| **Approval** | A request that needs board member sign-off before proceeding |
| **Run** | One heartbeat execution — has a transcript, cost, and outcome |
| **Wake** | Triggering an agent to start a heartbeat (happens on assignment, comments, schedule, or manual "Wake Now") |
| **Checkout** | An agent claims ownership of an issue before working on it |
| **PARA memory** | The agent's personal knowledge system (Projects, Areas, Resources, Archives) |

---

*Last updated: 2026-04-14. Covers Paperclip deployed on GCP Cloud Run at GreetEat Corp.*

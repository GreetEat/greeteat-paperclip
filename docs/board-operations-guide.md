# Paperclip Board Operations Guide

> **For**: board members and operators of a Paperclip deployment.
>
> This guide covers common tasks you'll do from the Paperclip dashboard.
> No terminal or coding knowledge required.

---

## Quick reference

| I want to... | How |
|---|---|
| See what agents are doing | Dashboard → company → Live Runs |
| Give an agent work | Create an issue and assign it |
| Hire a new agent | Ask the CEO agent (via an issue) |
| Review agent output | Agent page → Runs tab → click a run |
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
   - **Title**: clear, outcome-oriented (e.g., "Grow user base to 10K MAU")
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
   - **Title**: specific and actionable (e.g., "Research top 5 competitors in our market")
   - **Description**: the brief. Be specific about deliverables, constraints, audience. The more context you give, the better the agent's output.
   - **Assignee**: pick the right agent (see below)
   - **Priority**: `critical`, `high`, `medium`, `low`
   - **Goal**: link to the relevant goal (optional but recommended)
   - **Project**: link to the relevant project (optional)
3. Click **Create**

The assigned agent will be woken up and start working. Watch the **Live Runs** view to see it in action.

### Which agent to assign to

| Work type | Assign to |
|---|---|
| Strategy, delegation, cross-functional coordination | **CEO** |
| Marketing, content, social media, brand, growth | **CMO** |
| Market research, competitive analysis, user insights | **Head of Product Research** |
| Technical work, engineering tasks | **CTO** (if hired) |

### Writing good issue descriptions

**Good** (specific, actionable):

> Research the top 5 competitors in our market.
>
> Deliverables:
> - Competitive matrix (features, pricing, market position)
> - Gap analysis: what do they offer that we don't?
> - Opportunity list: where can we differentiate?
>
> Focus on direct competitors and adjacent players.

**Bad** (vague):

> Look into our competitors.

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
2. The CEO uses its hiring skill to submit a hire request
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

To view/edit instructions: Agent page → **Instructions** tab. Edit in the text editor → a floating **Save** button appears at the top when you've made changes.

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

## Connecting agents to external services

Agents can post to LinkedIn, X/Twitter, Slack, and any service with an API. The setup has two parts:

### 1. Obtain API credentials (one-time, human task)

Agents can't do OAuth browser flows. You need to get the tokens once from each service's developer portal:

| Service | Where to sign up | What you'll get |
|---|---|---|
| **LinkedIn** | linkedin.com/developers → Create App | Access token + organization ID |
| **X (Twitter)** | developer.x.com → Create Project + App | API key, secret, access token |
| **Slack** | api.slack.com/apps → Create App | Bot token |

### 2. Store credentials in the agent's config

1. Go to the **agent page** (e.g., CMO) → **Configuration** tab
2. Scroll to the **Environment Variables** section
3. Click **Add Variable**
4. Enter the variable name (e.g., `LINKEDIN_ACCESS_TOKEN`)
5. Switch the source from **"Plain"** to **"Secret"**
6. Click **Create New Secret**, paste your token, and save
7. Click the floating **Save** button

The agent can now use this credential in every heartbeat. When a token expires, update the secret — agents automatically get the new value on their next run.

---

## Scheduling recurring tasks (routines)

Routines let you run tasks on a schedule without manually creating issues each time.

### How routines work

1. You define a routine with a title, description, assigned agent, and schedule
2. When the schedule fires, Paperclip automatically creates an **issue**
3. The assigned agent wakes up and works on the issue
4. Agent marks the issue done when finished

### Setting up a routine

The easiest way: create an issue for the CEO asking it to set up a routine. Example:

> **Title**: "Set up a Mon/Wed/Fri LinkedIn posting routine for the CMO"
>
> **Description**: Create a routine that fires 3x per week at 9am ET. Each run should check the content calendar and post the next scheduled LinkedIn post. Assign the routine to the CMO.

The CEO agent can create routines via Paperclip's API.

### Routine templates

Routine titles and descriptions support `{{date}}` which auto-fills with today's date when the routine fires. Example:

- Routine title: "LinkedIn post for {{date}}"
- When it fires on April 14: issue title becomes "LinkedIn post for 2026-04-14"

This helps agents know exactly which day's content to work on.

### Common schedules

| Schedule | Description |
|---|---|
| Mon/Wed/Fri at 9am | Social media posting |
| Every weekday at 9am | Daily content |
| Every Monday at 8am | Weekly analytics review |
| First of every month | Monthly report |

### Pausing and managing

- **Pause** a routine to stop it temporarily (can resume later)
- **Archive** to stop it permanently
- **Manual run** to fire it immediately regardless of schedule

---

## Example: social media campaign

Here's how to set up a full social media workflow:

### 1. Create the strategy (one-time)

- **Create a goal**: "Build company social media presence"
- **Create a project**: "Social Media" linked to the goal
- **Create an issue for CEO**: "Develop LinkedIn + X content strategy and draft first 5 posts for each platform"
- CEO delegates to CMO → CMO drafts content calendar and initial posts

### 2. Review and approve

- Read the CMO's drafts in the issue comments
- Comment with feedback → CMO gets woken and revises
- When satisfied, mark the strategy issue as done

### 3. Set up recurring posting

- Ask the CEO to create posting routines:
  - "LinkedIn post for {{date}}" — Mon/Wed/Fri 9am
  - "X post for {{date}}" — every weekday 10am

### 4. Set up analytics

- Ask the CEO to create a weekly analytics routine:
  - "Social media analytics — week of {{date}}" — every Monday 8am
  - The CMO pulls LinkedIn + X performance stats and posts a summary report

### 5. Steady state (automated)

- **Monday 8am**: CMO reviews last week's performance
- **Monday 9am**: CMO updates content calendar based on what worked
- **Mon/Wed/Fri**: Posting routines fire → CMO posts optimized content
- **You monitor**: check issue feed for confirmations and the weekly analytics report

---

## Example: competitive research

Create an issue for the **Head of Product Research**:

> **Title**: Competitive analysis — our market
>
> **Description**:
> Analyze the competitive landscape in our market.
>
> Deliverables:
> 1. Market map: who are the players? (direct competitors + adjacent)
> 2. Feature comparison matrix
> 3. Pricing intelligence (where publicly available)
> 4. SWOT analysis vs top 3 competitors
> 5. Recommendation: where should we invest to differentiate?
>
> Focus on our primary market. Include direct and adjacent competitors.

The agent researches via web search, compiles a structured report, and posts results as issue comments with tables and citations.

---

## Cost management

### Understanding costs

Each time an agent runs a heartbeat, it uses LLM tokens which cost money. Costs vary by model:

| Model | Relative cost | Best for |
|---|---|---|
| **Claude Opus 4.6** | $$$ | Strategy, complex reasoning, CEO decisions |
| **Claude Sonnet 4.6** | $$ | Content creation, research, routine tasks |
| **Claude Haiku 4.5** | $ | Simple lookups, data formatting, quick tasks |

### Reducing costs

- **Use Sonnet for routine agents** (CMO, Research) — reserve Opus for the CEO. Change in Agent → Configuration → Model.
- **Lower max turns per run** — Agent → Configuration → Advanced → "Max turns per run". Default is 1000; most heartbeats finish in 10-30 turns. Setting it to 100 is a safe limit.
- **Keep periodic heartbeats off** — Agent → Configuration → Runtime → "Heartbeat enabled" should be off. Agents only run when they have assigned work.
- **Increase cooldown** — Agent → Configuration → Runtime → "Cooldown" to 60 seconds. Prevents rapid re-wakes from comment bursts.

### Monitoring spend

Dashboard → your company → **Costs** view shows:
- Spend by agent
- Spend by model
- Daily/weekly/monthly trends
- Budget utilization percentage

Set monthly budgets per agent to prevent runaway spend.

---

## Troubleshooting

### Agent isn't doing anything

- Check if the agent is **paused** (agent page → status)
- Check if the issue is actually **assigned** to that agent
- Check if there's already an **active run** — agents don't run in parallel by default
- Try clicking **Wake Now** on the agent page to force a heartbeat

### Agent is stuck or blocked

- Look at the agent's **latest run** for errors in the transcript
- Check if the issue status is `blocked` — the agent should have commented explaining why
- Try commenting on the issue with guidance — the agent will be woken and read your comment

### Agent's instructions are empty

- Check the **Instructions** tab on the agent page
- If the editor is empty, paste appropriate instructions and click Save
- Ask your platform operator if you see "Instructions root does not exist"

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
| **Routine** | A recurring task that automatically creates issues on a schedule |
| **Approval** | A request that needs board member sign-off before proceeding |
| **Run** | One heartbeat execution — has a transcript, cost, and outcome |
| **Secret** | An encrypted credential stored securely (API keys, tokens) |
| **Skill** | A reusable capability package installed on agents |

---

*Written for Paperclip (April 2026, commit ac664df). Paperclip evolves rapidly — verify against your deployed version.*

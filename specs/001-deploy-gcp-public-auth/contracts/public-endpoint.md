# Contract: Public HTTPS Endpoint

**Exposes**: User Stories 1 (operator sign-in), 2 (invitation-only registration), 3 (agent auth)
**Backed by**: Cloud Run service via domain mapping; Cloud DNS hosted zone for the deployment domain
**External monitor**: Cloud Monitoring Uptime Check

This contract defines the **externally observable behavior** of the
GreetEat Paperclip public URL. Anything not covered here is implementation
detail and may change without notice.

## Public hostnames

| Environment | Hostname | TLS |
|---|---|---|
| Production (single env) | `paperclip.greeteat.example` (placeholder — operator chooses the actual hostname under a domain they control, set in tfvars) | Google-managed cert via Cloud Run domain mapping |

Serves only HTTPS on 443. HTTP (port 80) is automatically redirected
to HTTPS by Cloud Run.

## Endpoints (externally observable)

### `/` — Web UI

- **GET** unauthenticated: returns the React app shell, which presents the
  Better Auth sign-in flow. No protected data is rendered.
- **GET** authenticated (Better Auth session cookie present): renders the
  board operator dashboard scoped to the operator's identity.
- **Required latency**: under 10 seconds end-to-end for an authenticated
  load on a typical broadband connection (SC-002).

### `/api/auth/*` — Better Auth endpoints

- Implemented entirely by Paperclip's Better Auth integration.
- Cookie-based session model. Sessions persist in Cloud SQL via Drizzle
  ORM (Better Auth's database adapter).
- **Self-registration is disabled** — open sign-up endpoints either
  return 404 or 403. Per FR-004, this is enforced at the application
  layer, not just hidden in the UI.
- Session revocation is supported by an operator-callable endpoint and
  takes effect on the next request (FR-005, FR-009).

### `/api/invites/:token` — Invitation claim

- **GET**: returns invitation summary (issuer, target identifier, expiry,
  status) plus links to the onboarding endpoints. Used by the invitee
  before accepting.
- **POST** (or PUT, per Paperclip's docs): claims the invitation, creating
  the new board operator account.
- Invitations expire (TTL ~10 minutes per Paperclip's docs); expired or
  used invitations return a non-leaky error.

### `/api/invites/:token/onboarding(.txt)` — Onboarding manifest

- Returns the onboarding handoff document (machine-readable JSON or the
  llm.txt-style plain-text variant). Available to anyone holding a valid
  invite token; no authentication required.

### `/api/agents/*` — Agent API

- Authenticated **only** via Paperclip's documented agent credentials
  (short-lived JWTs delivered as `PAPERCLIP_API_KEY` during heartbeats,
  or long-lived per-agent API keys created via
  `POST /api/agents/{id}/keys`). No other auth path accepted (FR-007).
- Cross-company access attempts return 403 (FR-008).
- Operators can revoke agent credentials and revocation takes effect
  within seconds, not at the next deploy (FR-009).

### `/health` — Health endpoint

- **GET**: returns 200 OK with a small JSON body when the service is
  ready to serve traffic. Returns non-200 when the service is unhealthy.
- **No authentication required** (FR-013) — this is what the Cloud
  Monitoring Uptime Check polls.
- MUST not leak any internal state (no version strings that reveal
  unpatched components, no internal hostnames).

## Error responses

All error responses to unauthenticated or unauthorized requests MUST:

- Use a documented HTTP status (400/401/403/404/429/5xx).
- Carry a JSON body with a stable error code and a human message.
- **Not leak**: stack traces, internal hostnames, database errors,
  enumerable IDs, file system paths, or environment variable values
  (FR-006).

The application MUST never echo a secret in any error response or log
line at any verbosity level (FR-014, FR-023).

## Security headers (set at Paperclip; minimum acceptable)

- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (or a CSP equivalent)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy`: a baseline CSP that disallows inline
  scripts where feasible.

If Paperclip does not set these by default, the deployment must verify
they are added either by Paperclip's config or by a future Global LB
follow-up. Until then, document the gap in `research.md` Followups.

## Availability

- The endpoint MUST be reachable and serving authenticated dashboard
  sessions ≥ 99.5% of any rolling 30-day window (SC-001).
- Measured externally by the Cloud Monitoring Uptime Check, which polls
  `/health` every 1 minute from multiple regions.
- An Uptime Check failure for ≥ 3 consecutive checks fires an alerting
  policy that pages the on-call operator.

## Rate limiting

- Rate limiting is **not** in scope for v1 of this contract. If
  abuse becomes an issue (e.g. credential stuffing on the sign-in
  endpoint), it will be added either inside Paperclip or in front of
  Cloud Run via Global LB + Cloud Armor (Decision 6 follow-up).

## Out-of-scope

- Email-based flows (password reset, email verification, security
  alerts). Paperclip does not use email; see Decision 7 in `research.md`.
- WebSocket sessions — Cloud Run supports them, but Paperclip does not
  appear to require them today. If a future Paperclip release requires
  long-lived WebSocket connections that exceed Cloud Run's 60-minute
  request timeout, this contract must be revisited.
- API versioning — Paperclip's API is consumed only by its own UI and
  by configured agents pinned to a specific Paperclip version, both of
  which advance in lockstep with the deployed image.

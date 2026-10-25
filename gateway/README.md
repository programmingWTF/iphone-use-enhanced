# iPhone Use gateway

One gateway deployment controls one phone. No domain, device credential, or agent
credential is compiled into the iOS app. The interface is disabled by default.

## Deploy your own

Requires Node.js and a Cloudflare account with Workers/Durable Objects access.

```sh
npm ci
npx wrangler secret put DEVICE_TOKEN
npx wrangler secret put AGENT_KEYS
npm run deploy
```

`DEVICE_TOKEN` is a long random device-only credential. `AGENT_KEYS` is a JSON
object mapping independent random API keys to trusted display names, for example
`{"<random-agent-key>":"Codex"}`. Never use the device token as an agent key.
Supply secret values using Wrangler's prompt; don't put them in source control.
On a first deployment, deploy the Worker before adding secrets if Wrangler
requires an existing Worker. It rejects connections until configured.

Configure your own hostname through Cloudflare Workers Custom Domains, or use
the assigned workers.dev address. In iPhone Use Settings → 远程调用, turn on
开放接口 and enter the HTTPS gateway base URL and DEVICE_TOKEN. The base URL may
include a reverse-proxy path prefix; it must not contain query parameters.

## Agent API

All API calls require `Authorization: Bearer <agent-key>`. Send a descriptive
`User-Agent`, such as `iphone-use-agent/1.0`, for compatibility with edge security
filters (generic Python client user agents may be blocked before the Worker).
The device uses a
different key for its WebSocket connection. Agent names are assigned by the
gateway configuration, not trusted from the request body.

```http
GET /v1/device

POST /v1/tasks
Content-Type: application/json
Idempotency-Key: <unique-request-id>

{"prompt":"Open Settings and read the battery level","approval_timeout_seconds":120}

GET /v1/tasks/<task-id>
```

POST returns `202` and a task ID when a confirmation is sent. Poll GET for
`awaiting_approval`, `running`, `rejected`, `expired`, `completed`, or `failed`.
Only that agent key can read its results. Retrying POST with the same
Idempotency-Key returns the existing task; changing its prompt returns 409.
The latest 100 task records are retained; clients should save completed results.
No task or screenshot is logged by the gateway code.

- `409 device_busy`: one task is awaiting approval/running, or a local run is in progress. Caller coordinates retries; no queue.
- `503 device_unavailable`: phone is offline, in the background without a run, or its heartbeat is stale.
- Approvals expire after 120 seconds by default (caller may shorten to 1–120).
- The phone shows the full prompt and agent name before approval. Leaving the foreground dismisses/rejects a pending approval.
- Approved tasks use the existing PhoneAgent; its normal stop control, result history, and background execution rules apply.
- Disconnecting does **not** release a running task. The phone persists its task ID and retries result delivery; a process restart reports interruption instead of replaying actions. Reopen the same installation/configuration to reconcile a disconnected task.
- There is no push notification requirement. The phone must be foregrounded to receive a new request.

## Validation

Create a gitignored `.dev.vars` with test-only credentials:

```dotenv
DEVICE_TOKEN="local-device-test-token"
AGENT_KEYS='{"local-agent-test-token":"Test Agent","other-agent-test-token":"Other Agent"}'
```

```sh
npm run types
npm run check
npm test
npx wrangler deploy --dry-run
```

The integration suite starts a local Worker, simulates the phone over WebSocket,
and checks authentication, task ownership, simultaneous submissions, rejection,
approval, expiration, idempotency, background admission, and reconnect/result delivery.

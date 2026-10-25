import { DurableObject } from "cloudflare:workers";

type TaskStatus = "awaiting_approval" | "running" | "rejected" | "expired" | "completed" | "failed";
interface TaskRecord {
  id: string; agent: string; prompt: string; status: TaskStatus;
  createdAt: number; expiresAt: number; result?: string;
}
type StoredTask = { id: string; owner: string; requestKey: string; status: string; body: string };
interface DeviceState { seen: number; accepting: boolean; busy: boolean }
const json = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" }
});
const failure = (error: string, status: number) => json({ error }, status);
async function digest(value: string) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}
async function sameSecret(left: string, right: string) {
  const key = await crypto.subtle.importKey("raw", new Uint8Array(32), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  const signature = await crypto.subtle.sign("HMAC", key, await digest(right));
  return crypto.subtle.verify("HMAC", key, signature, await digest(left));
}
async function readJSON(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get("Content-Type")?.startsWith("application/json")) throw new Error("invalid_json");
  const reader = request.body?.getReader();
  if (!reader) throw new Error("invalid_json");
  let size = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > 32768) { await reader.cancel(); throw new Error("body_too_large"); }
    chunks.push(value);
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.byteLength; }
  const value: unknown = JSON.parse(new TextDecoder().decode(data));
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_json");
  return value as Record<string, unknown>;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/health" && request.method === "GET") return json({ service: "iphone-use-gateway", version: 1 });
    const credential = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/)?.[1];
    if (!credential) return failure("unauthorized", 401);
    if (path === "/v1/device/connect") {
      if (!env.DEVICE_TOKEN || !await sameSecret(credential, env.DEVICE_TOKEN)) return failure("unauthorized", 401);
      // WebSocket upgrades must use fetch so the upgraded socket crosses the boundary.
      return env.PHONE.getByName("phone").fetch(request);
    }
    let agents: Record<string, string>;
    try { agents = JSON.parse(env.AGENT_KEYS); } catch { return failure("gateway_not_configured", 503); }
    let agent: string | undefined;
    for (const [key, name] of Object.entries(agents)) {
      if (await sameSecret(credential, key)) { agent = name; break; }
    }
    if (!agent) return failure("unauthorized", 401);
    const owner = Array.from(await digest(credential), b => b.toString(16).padStart(2, "0")).join("");
    const phone = env.PHONE.getByName("phone");
    if (path === "/v1/device" && request.method === "GET") return phone.status();
    if (path === "/v1/tasks" && request.method === "POST") {
      let body: Record<string, unknown>;
      try { body = await readJSON(request); } catch { return failure("invalid_or_oversized_json", 400); }
      const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
      const requestKey = request.headers.get("Idempotency-Key") ?? "";
      const seconds = body.approval_timeout_seconds ?? 120;
      if (!prompt || prompt.length > 8000 || !/^[A-Za-z0-9_-]{1,128}$/.test(requestKey)
          || typeof seconds !== "number" || !Number.isInteger(seconds) || seconds < 1 || seconds > 120) {
        return failure("invalid_request", 400);
      }
      return phone.submit(owner, agent, prompt, requestKey, seconds);
    }
    const match = path.match(/^\/v1\/tasks\/([a-f0-9-]{36})$/);
    if (match && request.method === "GET") return phone.result(owner, match[1]);
    return failure("not_found", 404);
  }
} satisfies ExportedHandler<Env>;

/** One deployment controls one phone. SQLite is the authority for the single task slot. */
export class PhoneGateway extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY, owner TEXT NOT NULL, requestKey TEXT NOT NULL,
      status TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(owner, requestKey))`);
  }
  private socket(): WebSocket | undefined { return this.ctx.getWebSockets("phone").find(ws => ws.readyState === WebSocket.OPEN); }
  private state(): DeviceState | undefined { return this.socket()?.deserializeAttachment() as DeviceState | undefined; }
  private send(value: unknown) {
    try { this.socket()?.send(JSON.stringify(value)); } catch { /* Reconnect reports task state. */ }
  }
  private record(row: StoredTask) { return JSON.parse(row.body) as TaskRecord; }
  private get(id: string): StoredTask | undefined {
    return this.ctx.storage.sql.exec<StoredTask>("SELECT * FROM tasks WHERE id = ?", id).toArray()[0];
  }
  private save(task: TaskRecord) {
    this.ctx.storage.sql.exec("UPDATE tasks SET status = ?, body = ? WHERE id = ?", task.status, JSON.stringify(task), task.id);
  }
  private active(): TaskRecord | undefined {
    const row = this.ctx.storage.sql.exec<StoredTask>("SELECT * FROM tasks WHERE status IN ('awaiting_approval','running') LIMIT 1").toArray()[0];
    if (!row) return;
    const task = this.record(row);
    if (task.status === "awaiting_approval" && task.expiresAt <= Date.now()) {
      task.status = "expired"; this.save(task); this.send({ type: "withdraw", id: task.id }); return;
    }
    return task;
  }
  async fetch(request: Request): Promise<Response> {
    if (request.method !== "GET" || request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return failure("websocket_required", 426);
    for (const old of this.ctx.getWebSockets("phone")) old.close(1000, "replaced");
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, ["phone"]);
    server.serializeAttachment({ seen: 0, accepting: false, busy: false } satisfies DeviceState);
    server.send(JSON.stringify({ type: "ready" }));
    return new Response(null, { status: 101, webSocket: client });
  }
  async status(): Promise<Response> {
    const active = this.active();
    const device = this.state();
    const online = !!device && Date.now() - device.seen < 30000;
    return json({ online, accepting: online && !!device?.accepting && !device.busy && !active,
      busy: !!active || !!device?.busy, taskStatus: active?.status ?? null });
  }
  async submit(owner: string, agent: string, prompt: string, requestKey: string, seconds: number): Promise<Response> {
    const active = this.active();
    const previous = this.ctx.storage.sql.exec<StoredTask>("SELECT * FROM tasks WHERE owner = ? AND requestKey = ?", owner, requestKey).toArray()[0];
    if (previous) {
      const task = this.record(previous);
      return task.prompt === prompt ? json(task) : failure("idempotency_conflict", 409);
    }
    const device = this.state();
    if (active || device?.busy) return failure("device_busy", 409);
    if (!device?.accepting || Date.now() - device.seen >= 30000) return failure("device_unavailable", 503);
    const task: TaskRecord = { id: crypto.randomUUID(), agent, prompt, status: "awaiting_approval", createdAt: Date.now(), expiresAt: Date.now() + seconds * 1000 };
    this.ctx.storage.sql.exec("INSERT INTO tasks VALUES (?, ?, ?, ?, ?)", task.id, owner, requestKey, task.status, JSON.stringify(task));
    this.send({ type: "task", task });
    return json(task, 202);
  }
  async result(owner: string, id: string): Promise<Response> {
    this.active();
    const row = this.get(id);
    return row && row.owner === owner ? json(this.record(row)) : failure("not_found", 404);
  }
  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    if (ws !== this.socket()) return;
    if (typeof raw !== "string" || raw.length > 32768) { ws.close(1009, "message too large"); return; }
    let message: Record<string, unknown>;
    try { message = JSON.parse(raw); if (!message || typeof message !== "object") return; } catch { return; }
    this.active();
    if (message.type === "status") {
      ws.serializeAttachment({ seen: Date.now(), accepting: message.accepting === true, busy: message.busy === true } satisfies DeviceState);
      ws.send(JSON.stringify({ type: "status_ack" }));
      return;
    }
    if (typeof message.id !== "string") return;
    const row = this.get(message.id);
    if (!row) return;
    const task = this.record(row);
    if (message.type === "decision") {
      if (task.status !== "awaiting_approval") { ws.send(JSON.stringify({ type: "withdraw", id: task.id })); return; }
      if (message.accepted === true) {
        task.status = "running"; this.save(task);
        ws.send(JSON.stringify({ type: "execute", task }));
      } else {
        task.status = "rejected"; task.result = "用户拒绝了任务"; this.save(task);
        ws.send(JSON.stringify({ type: "settled", id: task.id }));
      }
    } else if (message.type === "complete") {
      if (task.status === "running") {
        task.result = typeof message.result === "string" ? message.result.slice(0, 16000) : "error: 执行中断";
        task.status = message.success === true ? "completed" : "failed"; this.save(task);
      } else if (task.status === "awaiting_approval") {
        task.status = "rejected";
        task.result = typeof message.result === "string" ? message.result.slice(0, 16000) : "设备当前无法执行";
        this.save(task);
      }
      ws.send(JSON.stringify({ type: "settled", id: task.id }));
    }
    // Keep a bounded result history, never evicting a task occupying the phone.
    this.ctx.storage.sql.exec("DELETE FROM tasks WHERE status NOT IN ('awaiting_approval','running') AND rowid NOT IN (SELECT rowid FROM tasks ORDER BY rowid DESC LIMIT 100)");
  }
  async webSocketClose(ws: WebSocket, code: number) { ws.close(code === 1006 ? 1000 : code); }
  async webSocketError(ws: WebSocket) { ws.close(1011, "connection error"); }
}

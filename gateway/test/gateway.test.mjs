import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import WebSocket from "ws";

const origin = process.env.GATEWAY_TEST_URL ?? "http://127.0.0.1:8787";
const agentToken = process.env.TEST_AGENT_TOKEN ?? "local-agent-test-token";
const deviceToken = process.env.TEST_DEVICE_TOKEN ?? "local-device-test-token";
const agentHeaders = { Authorization: `Bearer ${agentToken}` };
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

test("gateway admission, approval, identity, concurrency and reconnect", { timeout: 90000 }, async t => {
  let server;
  if (!process.env.GATEWAY_TEST_URL) {
    server = spawn(process.execPath, ["node_modules/wrangler/bin/wrangler.js", "dev", "--port", "8787", "--persist-to", `.wrangler/test-state/${crypto.randomUUID()}`], {
      cwd: new URL("..", import.meta.url), stdio: ["ignore", "pipe", "pipe"]
    });
    let startup = "";
    server.stdout.on("data", data => { startup += data; });
    server.stderr.on("data", data => { startup += data; });
    t.after(() => server.kill());
    for (let i = 0; i < 150; i++) {
      try { if ((await fetch(origin + "/health")).ok) break; } catch {}
      if (server.exitCode !== null) throw new Error(startup);
      if (i === 149) throw new Error("Local Worker did not start: " + startup);
      await pause(300);
    }
  }
  const api = async (path, options = {}, token = agentToken) => {
    const response = await fetch(origin + path, { ...options, headers: { Authorization: `Bearer ${token}`, ...options.headers } });
    return { status: response.status, body: await response.json() };
  };
  const submit = (key, prompt = "Read the battery level", seconds = 120) => api("/v1/tasks", {
    method: "POST", headers: { "Content-Type": "application/json", "Idempotency-Key": key },
    body: JSON.stringify({ prompt, agent: "Spoofed name", approval_timeout_seconds: seconds })
  });
  const connect = async () => {
    const socket = new WebSocket(origin.replace(/^http/, "ws") + "/v1/device/connect", { headers: { Authorization: `Bearer ${deviceToken}` } });
    const messages = [];
    socket.on("message", data => messages.push(JSON.parse(data.toString())));
    await once(socket, "open");
    t.after(() => socket.terminate());
    const send = value => socket.send(JSON.stringify(value));
    const wait = async predicate => {
      for (let i = 0; i < 100; i++) {
        const index = messages.findIndex(predicate);
        if (index >= 0) return messages.splice(index, 1)[0];
        await pause(30);
      }
      throw new Error("Expected phone message was not delivered");
    };
    await wait(m => m.type === "ready");
    send({ type: "status", accepting: true, busy: false });
    await wait(m => m.type === "status_ack");
    return { socket, send, wait };
  };

  assert.equal((await api("/v1/device", {}, "wrong")).status, 401);
  assert.equal((await api("/v1/device", {}, deviceToken)).status, 401);
  assert.equal((await submit(crypto.randomUUID())).status, 503, "offline phone cannot admit work");
  let phone = await connect();
  const prefix = crypto.randomUUID();
  const races = await Promise.all([submit(prefix + "-a"), submit(prefix + "-b")]);
  assert.deepEqual(races.map(r => r.status).sort(), [202, 409], "only one concurrent caller obtains the slot");
  const accepted = races.find(r => r.status === 202).body;
  assert.equal(accepted.status, "awaiting_device", "delivery must not be reported as requiring manual approval");
  assert.equal(accepted.nextAction, "poll");
  assert.equal(accepted.pollUrl, "/v1/tasks/" + accepted.id);
  assert.notEqual(accepted.agent, "Spoofed name", "identity comes from the API key");
  const pending = await phone.wait(m => m.type === "task");
  assert.equal(pending.task.id, accepted.id);
  phone.send({ type: "decision", id: accepted.id, accepted: false });
  await phone.wait(m => m.type === "settled");
  assert.equal((await api("/v1/tasks/" + accepted.id)).body.status, "rejected");
  if (!process.env.GATEWAY_TEST_URL) assert.equal((await api("/v1/tasks/" + accepted.id, {}, "other-agent-test-token")).status, 404);
  const winnerKey = prefix + (races[0].status === 202 ? "-a" : "-b");
  assert.equal((await submit(winnerKey)).body.id, accepted.id, "retry never creates a second task");
  assert.equal((await submit(winnerKey, "different prompt")).status, 409);

  const running = (await submit(prefix + "-run")).body;
  await phone.wait(m => m.type === "task");
  await pause(150);
  assert.equal((await api("/v1/tasks/" + running.id)).body.status, "awaiting_device", "waiting for an auto-accepting phone is not human approval");
  phone.send({ type: "decision", id: running.id, accepted: true });
  await phone.wait(m => m.type === "execute");
  phone.socket.terminate();
  await pause(100);
  assert.equal((await submit(prefix + "-during-disconnect")).status, 409, "disconnect does not release an executing task");
  phone = await connect();
  phone.send({ type: "complete", id: running.id, success: true, result: "done: battery is 80%" });
  await phone.wait(m => m.type === "settled");
  const result = (await api("/v1/tasks/" + running.id)).body;
  assert.equal(result.status, "completed");
  assert.equal(result.result, "done: battery is 80%");
  assert.equal(result.nextAction, "none");

  const expired = (await submit(prefix + "-expire", "Expires quickly", 1)).body;
  await phone.wait(m => m.type === "task");
  await pause(1100);
  phone.send({ type: "decision", id: expired.id, accepted: true });
  await phone.wait(m => m.type === "withdraw");
  assert.equal((await api("/v1/tasks/" + expired.id)).body.status, "expired");
  phone.send({ type: "status", accepting: false, busy: false });
  await phone.wait(m => m.type === "status_ack");
  assert.equal((await submit(prefix + "-background")).status, 503, "background idle phone does not accept tasks");
  phone.send({ type: "status", accepting: false, busy: true });
  await phone.wait(m => m.type === "status_ack");
  assert.equal((await submit(prefix + "-local-run")).status, 409, "local runs also occupy the phone");
  assert.equal((await api("/v1/tasks", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ prompt: "x" }) })).status, 400);
  phone.send({ type: "status", accepting: false, busy: false });
  await phone.wait(m => m.type === "status_ack");
});

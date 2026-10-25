// Secrets injected at runtime (`.dev.vars` locally, `wrangler secret put` in production).
// `wrangler types` only knows the vars declared in wrangler.jsonc, so declare the secrets here;
// TypeScript merges this with the generated `interface Env` in worker-configuration.d.ts.
interface Env {
  DEVICE_TOKEN: string;
  AGENT_KEYS: string;
}

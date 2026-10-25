< [简体中文](./CONTRIBUTING.md) | English >

# Contributing

Issues, pull requests and ideas are welcome. This project is an unofficial enhanced fork of
[EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app) — read the
[README](README.en.md) and the [architecture notes](docs/ARCHITECTURE.md) first.

## What you need

| You want to… | You need |
|---|---|
| just use the app | an iPhone on iOS 26+, any signing tool, a vision + tool-calling model endpoint |
| change the UI (Swift) | macOS with Xcode 26/27, or just use the GitHub Actions workflow |
| change the `idevice` patch (Rust) | macOS, rustup, the `aarch64-apple-ios` target (`scripts/build-idevice.sh`) |
| change the gateway (TypeScript) | Node.js 22+, then `npm ci` inside `gateway/` |

No Mac? Fork the repo and let Actions build your branch.

## Reporting issues

- Search for duplicates first.
- **Bugs**: use the [bug form](./.github/ISSUE_TEMPLATE/bug.yml) and include the iOS version, iPhone model,
  signing method (free Apple ID / paid certificate), model endpoint, and reproduction steps.
  The app writes `Documents/idevice_log.txt`; export it through the Files app.
- **Feature requests**: describe the situation you hit, not only the solution you have in mind.
- **Security**: do not open a public issue — follow [SECURITY.md](SECURITY.md).

## Pull requests

1. Branch from `main`, keep commits small.
2. Commit messages follow `type(scope): description`, **in English**, e.g.
   `fix(ddi): fall back to the proxy mirror when raw times out`.
3. One topic per PR; keep formatting-only churn separate.
4. UI changes need a screenshot or recording (device preferred — the simulator only exercises the UI shell).
5. Explain the *why* and *how you verified it* in the PR description.
6. Never commit certificates, provisioning profiles, `.p12` files, API keys, pairing files, `dist/` or `node_modules/`.

## Conventions

- **Swift**: must build against iOS 17.4 — wrap newer APIs in `#available`.
  All surfaces go through `iPhoneUse/Support/GlassStyle.swift`; no hard-coded colours in views.
- **Copy**: user-facing strings are Simplified Chinese; protocol markers (`done:`, `error:`), model prompts
  and logs stay English.
- **Rust patch**: only touch `idevice-patch/`, never the upstream checkout under `.build/`.
- **Gateway**: off by default, and every capability needs a documented trust boundary.

## Languages

Docs are bilingual: Chinese is the default (`README.md`, `CONTRIBUTING.md`), English lives in `*.en.md`.
When you change a doc, update both and keep the structure parallel.

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.en.md).

## License

Contributions are licensed under [AGPL-3.0](LICENSE). Opening a PR means you agree to publish your changes
under that licence.

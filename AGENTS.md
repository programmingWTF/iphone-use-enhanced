# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, Codex, OpenClaw …) working in this repository.

## What this repo is

An **unofficial enhanced fork** of [EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app)
(AGPL-3.0). The app lets an LLM drive the iPhone it runs on: screenshot → chat completion with tool calls →
tap / swipe / type / open app → repeat. It reaches its own device's developer services through a loopback VPN
plus an RP pairing file, via the Rust FFI `idevice`.

This fork adds: Mac-free CI packaging (unsigned IPA on Releases), China-friendly DDI mirrors with a progress
card, full Simplified Chinese UI, pinyin input, Markdown + math rendering, a Liquid Glass design system,
Shortcuts that return values, and an optional Cloudflare Worker gateway.

Start with: [README.md](README.md) · [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) ·
[docs/FEATURES.md](docs/FEATURES.md) · [CONTRIBUTING.md](CONTRIBUTING.md) · [LABELS.md](LABELS.md).

## Layout

- `iPhoneUse/Agent/`: `AgentView` (chat + drawer), `PhoneAgent` (loop, tools), `LLMSettings` (endpoint, Keychain, prompt), `RunAgentIntent`, `RemoteGateway`
- `iPhoneUse/Device/`: `Connection` (VPN → tunnel → DDI), `DeviceSession` (tunnel, ports, logs), `DeviceSession+Services` (screenshot, touch, type, launch), `DeveloperDiskImageService` + `DDIDownloadCenter`
- `iPhoneUse/Support/`: `MarkdownText` (renderer + math), `GlassStyle` (design system), `DDIProgressCard`, `MessageTextSheet`
- `TunnelProvider/`: loopback packet-tunnel extension · `AgentWidget/`: Live Activity · `Shared/`: compiled into both
- `idevice-patch/`: our Rust additions to idevice's FFI (`probe.rs`)
- `gateway/`: optional Cloudflare Worker (TypeScript) · `scripts/`: build & debug helpers

## Commands

    # Rust FFI (once, or after touching idevice-patch/) — macOS + rustup only
    rustup target add aarch64-apple-ios
    bash scripts/build-idevice.sh          # -> iPhoneUse/idevice/libidevice_ffi.a (gitignored, ~45 MB)

    # Unsigned device build (no signing identity needed)
    xcodebuild -project iPhoneUse.xcodeproj -scheme iPhoneUse -configuration Release \
      -destination 'generic/platform=iOS' -derivedDataPath build \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" BUILTIN_VPN=NO build

    # Gateway
    cd gateway && npm ci && npm run check && npm test

There is no Swift unit-test target. Verification is: the CI build succeeds, and the behaviour is checked on a
real device (the simulator only exercises the UI shell).

## Rules

- **iOS 17.4 is the floor.** Every iOS 18/26 API must be inside `#available`.
- **Style goes through `GlassStyle.swift`** — no hard-coded colours, no ad-hoc `.ultraThinMaterial`.
- **User-facing copy is Simplified Chinese**; protocol markers (`done:`, `error:`), model prompts and logs stay English.
- **Never commit** certificates, `.p12`, provisioning profiles, API keys, `pairingFile.plist`, `dist/`, `node_modules/`.
  `.dev.vars` holds `DEVICE_TOKEN`/`AGENT_KEYS` and must stay ignored.
- **`DEVELOPMENT_TEAM` stays empty**; `bundle_id` stays `blog.eliot.iphoneuse` unless the user changes it on purpose —
  changing it invalidates the imported pairing file.
- **Docs are bilingual**: Chinese is the default (`README.md`, `CONTRIBUTING.md`), English lives in `*.en.md`.
  Keep structure parallel; don't add a language without updating both.
- **Commit style**: `type(scope): description` in English, e.g. `fix(ddi): fall back to the mirror when raw times out`.
- **Labels**: only use names defined in `LABELS.md`; define a new label there before creating it.

## Gotchas

- CI must run on **`xcode-27`**: Xcode 26.6's Swift frontend times out type-checking the composer expression in
  `iPhoneUse/Agent/AgentView.swift`.
- `idevice` is pinned in `scripts/build-idevice.sh` (`COMMIT=`), not vendored. `.build/` is a throwaway checkout.
- `probe_paste` (clipboard ⌘V) is dead — iOS does not let a backgrounded app write the pasteboard in a way the
  foreground app sees. Chinese input goes through pinyin + the candidate bar.
- The DDI files are large and fetched at run time; the app adopts files already present in `Documents/DDI/`.
- GitHub push over HTTPS is flaky on some networks; the fallback is the Git Data API
  (`git/blobs` → `git/trees` → `git/commits` → `PATCH git/refs/heads/main`).
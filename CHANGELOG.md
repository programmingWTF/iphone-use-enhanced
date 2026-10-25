# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Versioning: [SemVer](https://semver.org/).
This fork starts its own version line at `v0.1.0`; for the upstream history see
[EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app).

## [v0.1.0] - 2026-10-25

First public release of the enhanced fork.

### Added

- GitHub Actions workflow that builds an **unsigned IPA** on the `xcode-27` runner and attaches it to GitHub
  Releases on a `v*` tag (`bundle_id`, `strip_extensions`, `name_suffix` inputs).
- Multi-mirror developer disk image (DDI) download with an in-app **progress card**: file counter, speed,
  ETA, current mirror, and the list of mirrors that failed.
- Chinese input: the agent types pinyin and taps the candidate bar, with a `long_press` tool to open the
  paste menu as a fallback and `ask_user_question` as the last resort.
- Markdown renderer written from scratch: headings, bold/italic/bold-italic, strikethrough, inline code,
  task lists, nested lists, code blocks with language label and copy button, tables, quotes, rules,
  `$…$` / `$$…$$` approximations, and `\*`-style escapes.
- Simplified Chinese UI across the app, including Shortcuts intents, system prompt and error messages,
  with automatic migration from the old English default prompt.
- Liquid Glass design system (`GlassStyle.swift`) — native `glassEffect` on iOS 26, blur fallback on 17.4,
  four identity colours, round icon buttons, coloured outline for lifted history rows.
- Shortcuts integration that returns a value: `RunAgent` result plus a separate `Get Last Agent Result` action.
- Optional remote task gateway: a Cloudflare Worker (`gateway/`) with `DEVICE_TOKEN` / `AGENT_KEYS`,
  approval-by-default and an explicit trust boundary; the client lives in `iPhoneUse/Agent/RemoteGateway.swift`.
- Repository scaffolding: bilingual README/contributing docs, issue forms, PR template, CODEOWNERS,
  gateway CI, label taxonomy, changelog, security policy and architecture notes.

### Changed

- `idevice` pinned to `edf25870` ("fix(tunnel): set MSS to 8192").
- Free Apple ID builds use `BUILTIN_VPN=NO` and rely on [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)
  for the loopback tunnel.
- `DEVELOPMENT_TEAM` is intentionally empty — sign with your own account.
- History drawer scrolls to the physical bottom edge with the action buttons floating above the list.
- Settings rows carry icons and follow the two-weight glass scheme (only status, send, new session and
  user bubbles are coloured).

### Fixed

- DDI download could stall forever when GitHub raw was unreachable; the downloader now walks a mirror list
  and reports per-mirror failures.
- Clipboard-based pasting never landed in the background on iOS (system restriction) — replaced by the
  pinyin flow.
- `scrollEdgeEffectHidden` was applied where the parent had no safe area; the drawer now measures the real
  bottom inset and extends past it.
- The toolbar "new session" button showed two glass layers; the shared background is now hidden on iOS 26.

### Security

- No signing identity, provisioning profile, API key or pairing file is committed.
- Documented the credential surface (`DEVICE_TOKEN`, `AGENT_KEYS`, pairing file, certificates) in `SECURITY.md`.

[v0.1.0]: https://github.com/programmingWTF/iphone-use-enhanced/releases/tag/v0.1.0

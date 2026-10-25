<div align="center">

<img src="docs/images/logo.png" alt="iPhone Use Enhanced" width="140">

# iPhone Use Enhanced

**Let an LLM drive the iPhone it runs on — no Mac, no jailbreak, no extra hardware.**

[![CI](https://github.com/programmingWTF/iphone-use-enhanced/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/programmingWTF/iphone-use-enhanced/actions/workflows/build-unsigned-ipa.yml)
[![Release](https://img.shields.io/github/v/release/programmingWTF/iphone-use-enhanced?include_prereleases&sort=semver)](https://github.com/programmingWTF/iphone-use-enhanced/releases)
![iOS](https://img.shields.io/badge/iOS-26%2B-black)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
![Swift + Rust](https://img.shields.io/badge/Swift%20%2B%20Rust-orange)

< [简体中文](./README.md) | English >

</div>

> **An unofficial enhanced fork of [EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app).**
> Original work © Eliot Andres, licensed AGPL-3.0. This fork keeps the same license and adds
> Chinese-localised UX, China-friendly networking, Mac-free CI builds, and a reworked interface.
> See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution.

## What it is

iPhone Use is an iOS app where an LLM controls the phone it is running on. You type a task, the app
screenshots itself through the developer services (CoreDevice / Remote Pairing), sends the screenshot to a
vision-capable model that returns a tool call, and then taps, swipes, types or opens apps accordingly —
until it calls `done` and reports back in Markdown.

The whole loop runs on the phone. Nothing leaves the device except the calls to your LLM endpoint.

## Differences from upstream

| Area | Upstream | This fork |
|---|---|---|
| Build & distribution | Build with Xcode on a Mac | **GitHub Actions produces an unsigned IPA and attaches it to GitHub Releases** — no Mac needed |
| China networking | DDI downloaded from GitHub raw, often stalls | Multi-mirror DDI download (`ghfast.top` / `gh-proxy.com` / raw) with a **live progress card** (speed, ETA, failed mirrors) |
| Chinese input | ASCII only, non-ASCII silently dropped | **Pinyin entry + candidate bar**, plus a `long_press` tool to open the paste menu as a fallback |
| UI language | English | **Simplified Chinese by default, with a one-tap English switch in Settings** (system prompt stays in its original language; Shortcuts phrases and system permission prompts follow the system language) |
| Model replies | Plain text | **Markdown rendering**: headings, bold/italic/strike, task lists, code blocks (language label + copy button), tables, quotes, `$…$` / `$$…$$` math, `\*` escapes |
| Visual style | System blur | **Liquid Glass** design system: native `glassEffect` on iOS 26, blur fallback on 17.4; purple reserved for three actions |
| Model access | OpenRouter only | Built-in **OpenRouter / DeepSeek** (DeepSeek is the default, `deepseek-flash` supports vision + tool calls), plus any OpenAI-compatible endpoint |
| Shortcuts | Launch only | `RunAgentIntent` **returns the result**, plus `Get Last Agent Result` for Siri |
| Remote use | — | Optional **Cloudflare Worker gateway** (`gateway/`): off by default, device token + explicit approval, documented trust boundary |

## Features

- **No computer at run time** — the agent runs on the iPhone and drives that same iPhone. A desktop is needed once, for the pairing file.
- **Start it from anywhere** — chat UI, Siri, the "Run Agent" Shortcut, or an `iphoneuse://run?prompt=…` deep link.
- **Everything visible** — every step shows its screenshot, action and one-line reasoning; failures are reported in the chat.
- **Readable results** — the run ends with a Markdown summary that Shortcuts and scripts can also read.
- **Optional remote gateway** — dispatch tasks from a desktop to the phone with allow-listed keys and manual approval.

## Requirements

| Part | Notes |
|---|---|
| **iPhone** | iOS 26 or later (developed and verified on iOS 27.2). The deployment target is 17.4, but 17.x is untested. Developer Mode on. |
| **Apple account** | **Paid team:** the built-in loopback VPN needs the Network Extension entitlement.<br>**Free Apple ID:** build with `BUILTIN_VPN=NO` and install [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044); re-sign every 7 days. |
| **Pairing file** | Created once (iDevicePair on Windows, `xcrun devicectl` on macOS). No computer afterwards. |
| **Vision model** | Any OpenAI-compatible endpoint that accepts images and tool calls — OpenRouter, or `https://api.deepseek.com` with `deepseek-flash`. |
| **Build host** | macOS + Xcode 26/27 + rustup, only if you compile it yourself. |

## Install without a Mac

1. **Download the IPA** from [Releases](https://github.com/programmingWTF/iphone-use-enhanced/releases) (`iphone-use-app-unsigned.ipa`, unsigned).
2. **Sign it** with any sideloading tool — Sideloadly, i4Tools, ESign, AllSign, etc. A free Apple ID signature lasts 7 days (3 apps max); a paid certificate lasts a year.
3. **Change the bundle id** — `blog.eliot.iphoneuse` is registered to the upstream team, so a free account cannot reuse it. Let the signing tool add a unique suffix (Sideloadly's *Use automatic bundle ID*) or rebuild through CI with the `bundle_id` input. **Re-import the pairing file after changing it** — pairings are bound to the bundle id.
4. **Create the pairing file** (once):
   - Windows: [iDevicePair](https://github.com/jkcoxson/idevice_pair/releases), connect over USB, choose **Remote pairing**, save `pairingFile.plist`.
   - macOS: `xcrun devicectl device pair --device <UDID> --store-here pair.plist`.
5. **Import it** into the app (Settings → Pairing file), or drop `pairingFile.plist` into the app's `Documents/` folder via the Files app.
6. **Configure and run** — enable the VPN (built-in or LocalDevVPN), allow Local Network and Location "Always", fill in base URL / model / API key under Settings → Model, then type a task.

> Re-signing with a free account rotates the certificate. **Do not delete the app** — that wipes the pairing file and the downloaded DDI.

## First-run checklist

- [ ] Developer Mode enabled
- [ ] Pairing file imported (Settings → Pairing file shows ✅)
- [ ] VPN ready: built-in for paid teams, LocalDevVPN selected under Phone Connection for free accounts
- [ ] Local Network allowed, Location set to Always
- [ ] Model configured and "Test connection" passes
- [ ] The first run downloads the developer disk image (DDI); watch the progress card for mirror and speed

## Tips

- **Chinese text**: the model types pinyin and taps the candidate bar. If an app does not take it, the agent falls back to `long_press` → tap "Paste", and finally to `ask_user_question`.
- **Slow DDI download**: Settings → Phone Connection → *Redownload developer disk image*. You can also place the five DDI files into `Documents/DDI/` yourself and the app will adopt them without networking.
- **Keep your VPN**: iPhone Use needs the single VPN slot. In ClashMi, add `tun: loopback-address: [10.7.0.1]` to an override profile and reconnect — both then coexist.
- **"Viewed remotely from Mac" on every run**: an iOS notice for developer services; no data actually leaves the phone.

## Building

### With GitHub Actions (no Mac)

`.github/workflows/build-unsigned-ipa.yml` runs on the **`xcode-27` runner**:

1. builds the `idevice` static library (`scripts/build-idevice.sh`);
2. runs `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`;
3. packs `iphone-use-app-unsigned.ipa` and uploads it as an artifact;
4. **on a `v*` tag, creates a GitHub Release and attaches the IPA**.

Manual runs accept `bundle_id`, `strip_extensions` and `name_suffix`.

> Xcode 26.6's Swift frontend times out on the composer expression in `iPhoneUse/Agent/AgentView.swift`,
> hence the pinned `xcode-27` runner. Actions is free for public repositories; private repositories are billed
> at the 10× macOS multiplier.

### Locally (macOS)

```sh
rustup target add aarch64-apple-ios
bash scripts/build-idevice.sh
xcodebuild -project iPhoneUse.xcodeproj -scheme iPhoneUse \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO BUILTIN_VPN=NO build
```

### Signing

The repository ships **no signing identity**: `DEVELOPMENT_TEAM` is intentionally empty and the bundle id is
still the upstream one. Sign with your own account — via Xcode's Team picker, or
`DEVELOPMENT_TEAM=YOURTEAMID bundle_id=your.unique.id xcodebuild ...`, plus `BUILTIN_VPN=NO` for free accounts.

## Project layout

```
iPhoneUse/            the SwiftUI app
iPhoneUse/Agent/      chat UI, agent loop, model settings, Shortcuts intents, remote gateway client
iPhoneUse/Device/     tunnel, session, screenshot/touch injection, DDI download
iPhoneUse/Support/    Markdown renderer, Liquid Glass styles, DDI progress card
TunnelProvider/       loopback VPN extension (paid teams)
AgentWidget/          Live Activity
idevice-patch/        Rust patch for the idevice FFI (Chinese input support)
scripts/              build and debug scripts
gateway/              optional Cloudflare Worker gateway
docs/                 architecture, feature scope, screenshots
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) · [Feature scope](docs/FEATURES.md) · [Labels](LABELS.md) · [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.en.md) · [Security](SECURITY.md) · [中文说明](./README.md)

## Known limitations

- **Cellular needs a Shortcut**: iOS refuses new loopback VPN connections on cellular data, so the app toggles data through a Shortcut while it connects.
- **One VPN at a time**: unless you use the ClashMi `loopback-address` override, Tailscale and friends are displaced while the app runs.
- **"Viewed remotely" notice** on every run — system behaviour, cannot be disabled.
- **Pairing files expire** and must be regenerated.
- **Sideload only**: it needs Developer Mode and developer services, so it cannot ship on the App Store.
- **A few seconds per step**, dominated by the model.
- **Apple may change these private services** at any time; this is an experimental tool, not a supported API.

## Disclaimer

- This project is **not affiliated with or endorsed by Apple Inc. or Eliot Andres**.
- It drives the device through iOS developer services and private protocols. Expect breakage on OS updates.
- Use it only on devices and accounts you own or are authorised to operate. Do not use it to evade platform rules or to commit fraud.
- You are responsible for your signing certificate, Apple account and model API keys. **Never** commit certificates, keys or pairing files.
- Provided "as is" under AGPL-3.0, without warranty of any kind.
- "iPhone", "Apple" and "iOS" are trademarks of Apple Inc., used here descriptively only.

## License

[AGPL-3.0](LICENSE), same as upstream. Redistributions must keep the license and attribution —
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

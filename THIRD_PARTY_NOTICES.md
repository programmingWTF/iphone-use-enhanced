# Third-party notices

This repository is a fork. The table below lists what it builds on and under which terms.

| Component | Source | License | Notes |
|---|---|---|---|
| iPhone Use (`iPhoneUse/`, `TunnelProvider/`, `AgentWidget/`, `Shared/`, `docs/`) | [EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app) © Eliot Andres | AGPL-3.0 | Forked at commit `89afa45`. The fork adds CI packaging, Chinese localisation, DDI mirroring, Markdown rendering, Liquid Glass UI, Chinese input support and an optional remote gateway. |
| `idevice` (Rust) | [jkcoxson/idevice](https://github.com/jkcoxson/idevice) | MIT (as published upstream) | Built from source by `scripts/build-idevice.sh`, pinned to commit `edf25870`; `idevice-patch/idevice.patch` and `probe.rs` add the FFI surface this app uses. Not vendored — fetched at build time. |
| Developer disk images (DDI) | [doronz88/DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage) | See upstream repository | Downloaded on demand by the app (never bundled). The app tries `raw.githubusercontent.com`, `ghfast.top` and `gh-proxy.com` mirrors. |
| Cloudflare Worker SDK (`gateway/`) | [cloudflare/workers-sdk](https://github.com/cloudflare/workers-sdk), `wrangler` | MIT / Apache-2.0 | Dev-time dependencies only; not redistributed. |
| TypeScript, Node.js test runner (`gateway/`) | Microsoft / OpenJS Foundation | Apache-2.0 / MIT | Dev-time dependencies only. |
| Contributor Covenant | [contributor-covenant.org](https://www.contributor-covenant.org/) | CC BY 4.0 | `CODE_OF_CONDUCT.md` is an adapted Chinese translation; the English original is canonical. |

## Trademarks

"iPhone", "Apple", "iOS", "Siri", "Shortcuts" and "App Store" are trademarks of Apple Inc.
"Cloudflare Workers" is a trademark of Cloudflare, Inc. "GitHub Actions" is a trademark of GitHub, Inc.
All trademarks are used descriptively; no affiliation or endorsement is implied.

## Attribution requirements

AGPL-3.0 requires that redistributions keep this licence, state the changes, and keep the copyright
notices intact. If you publish a modified build, say so and link back to this repository and to the
upstream project.

## Report mistakes

If something here misattributes a licence, open an issue titled `docs: license` — we treat licence issues as
`P1`.

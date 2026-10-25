# 安全策略 · Security Policy

< 简体中文 | [English](#english) >

## 报告安全问题

**不要开公开 issue。** 请用 GitHub 的私密报告通道：

https://github.com/programmingWTF/iphone-use-enhanced/security/advisories/new

报告里请包含：受影响的版本或 commit、iOS 版本与机型、复现步骤、影响面（例如「能读到别人的配对文件」），
以及你希望公开的时间点。我们会在 7 天内确认收到，并在修复后于 advisory 中致谢（除非你要求匿名）。

## 需要重点保护的凭据

| 凭据 | 位置 | 泄露后果 |
|---|---|---|
| `DEVICE_TOKEN` | `gateway/.dev.vars` 或 Cloudflare secret | 任何人可向你的手机投递任务 |
| `AGENT_KEYS` | 同上 | 同上，且会以白名单身份出现 |
| 配对文件 `pairingFile.plist` | 手机 `Documents/`、电脑桌面 | 拿到它 + 隧道 = 可以控制这台手机 |
| 签名证书 / `.p12` / 描述文件 | 你的签名工具 | 可以以你的身份签发 App |
| 模型 API Key | App 的 Keychain | 会被刷额度 |

这些内容**一律不要**出现在 issue、PR、截图、日志或仓库里。如果已经贴出来，请立即吊销并重新签发。

## 已知的设计取舍（不是漏洞）

- App 依赖 iOS 的开发者服务与私有协议，`idevice` 就是这类实现的 Rust 封装；它们随时可能被 Apple 更改。
- 运行时 iOS 会弹出「这台设备正被 Mac 远程查看」，这是系统行为，不代表有数据外发。
- 远程网关默认关闭；启用后必须同时配置 `DEVICE_TOKEN` 与 `AGENT_KEYS`，并保持「需人工批准」的默认策略。
- 免费 Apple ID 签名 7 天过期、最多 3 个 App，这是 Apple 的限制，不是本项目的缺陷。

## 支持范围

只有 `main` 分支的最新 commit 会收到修复。本项目按 AGPL-3.0 按现状提供，不承诺任何 SLA。

---

<a id="english"></a>

## English

**Do not open a public issue.** Report privately through GitHub Security Advisories:

https://github.com/programmingWTF/iphone-use-enhanced/security/advisories/new

Include the affected version/commit, iOS version and device model, reproduction steps, impact
(e.g. "can read someone else's pairing file"), and your disclosure timeline. We acknowledge within 7 days
and credit you in the advisory once fixed, unless you ask to stay anonymous.

### Secrets that matter

| Secret | Where it lives | Impact if leaked |
|---|---|---|
| `DEVICE_TOKEN` | `gateway/.dev.vars` or a Cloudflare secret | Anyone can dispatch tasks to your phone |
| `AGENT_KEYS` | same | Same, with an allow-listed identity |
| `pairingFile.plist` | the app's `Documents/`, your desktop | Pairing + tunnel access to the device |
| Signing certificate / `.p12` / profiles | your signing tool | App signing under your identity |
| Model API key | the app's Keychain | Billing abuse on your account |

Never paste these into issues, PRs, screenshots, logs or the repository. If you already did, revoke and reissue.

### Known trade-offs (not vulnerabilities)

- The app relies on iOS developer services and private protocols (wrapped by `idevice`); Apple may change them at any time.
- iOS shows a "viewed remotely from Mac" notice on every run; that is system behaviour, not exfiltration.
- The remote gateway is off by default and requires both `DEVICE_TOKEN` and `AGENT_KEYS`, keeping approval-by-default.
- Free Apple ID signatures expire after 7 days with a 3-app limit — an Apple constraint, not a bug here.

### Supported versions

Only the latest commit on `main` receives fixes. Provided "as is" under AGPL-3.0, with no SLA.

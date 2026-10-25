< 简体中文 | [English](./CONTRIBUTING.en.md) >

# 参与贡献

欢迎 issue、PR 和想法。这个项目是 [EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app)
的非官方增强版，改动前请先读一遍 [README](README.md) 与 [架构说明](docs/ARCHITECTURE.md)。

## 先确认你的环境

| 场景 | 你需要 |
|---|---|
| 只是想用 | 一台 iOS 26+ 的 iPhone、任意签名工具、一个支持视觉 + 工具调用的模型接口 |
| 改界面（Swift） | macOS + Xcode 26/27，或直接用仓库里的 GitHub Actions |
| 改 `idevice` 补丁（Rust） | macOS + rustup + `aarch64-apple-ios` target（`scripts/build-idevice.sh`） |
| 改网关（TypeScript） | Node.js 22+，在 `gateway/` 下 `npm ci` |

没有 Mac 也能贡献界面或文档：改完推到自己的分支，让 Actions 出包验证。

## 提 issue

- 先搜一下有没有重复。
- **Bug**：用 [Bug 模板](./.github/ISSUE_TEMPLATE/bug.yml)，写清 iOS 版本、机型、签名方式（免费号 / 付费证书）、
  模型与接口，以及复现步骤。日志在 App 的 `Documents/idevice_log.txt`，可以通过「文件」App 取出。
- **功能建议**：说明你实际遇到的场景，而不是只给结论。
- **安全问题**：不要开公开 issue，按 [SECURITY.md](SECURITY.md) 私下报告。

## 提 PR

1. 从 `main` 切分支，小步提交。
2. 提交信息用 `type(scope): description`，**英文**，例如：
   - `fix(ddi): fall back to the proxy mirror when raw times out`
   - `feat(ui): keep the send button round`
   - `docs: explain the pairing file`
3. 一次 PR 只做一件事。纯格式化、纯重排的改动请单独提。
4. 界面改动请附截图或录屏（真机优先，模拟器只能看 UI，连不上设备）。
5. 影响行为的改动请在 PR 描述里写「为什么」和「怎么验证」。
6. 不要提交：证书、描述文件、`.p12`、API Key、配对文件、`dist/`、`node_modules/`。

## 代码约定

- **Swift**：保持 iOS 17.4 可编译；iOS 18/26 的新 API 必须包在 `#available` 里。
  界面样式统一走 `iPhoneUse/Support/GlassStyle.swift`，不要在视图里硬写颜色。
- **文案**：用户可见的字符串用简体中文；协议标记（`done:`、`error:`）、给模型的提示串、日志保持英文。
- **Rust 补丁**：只改 `idevice-patch/`，不要动 `.build/` 里的上游源码。
- **网关**：`gateway/` 默认关闭；任何新增能力都要有明确的信任边界说明。

## 语言

文档是双语的：中文是默认（`README.md`、`CONTRIBUTING.md`），英文单独成文件（`*.en.md`）。
改文档时请同时更新两种语言，保持结构对应。

## 行为准则

参与本项目即表示同意遵守 [行为准则](CODE_OF_CONDUCT.md)。

## 许可

贡献的代码按 [AGPL-3.0](LICENSE) 授权。提交 PR 即表示你同意以该许可证发布你的改动。

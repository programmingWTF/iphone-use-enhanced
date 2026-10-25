<div align="center">

<img src="docs/images/logo.png" alt="iPhone Use Enhanced" width="140">

# iPhone Use Enhanced · iPhone Use 增强版

**让大模型直接操作它自己运行的那台 iPhone —— 不需要 Mac、不需要越狱、不需要额外硬件。**

[![CI](https://github.com/programmingWTF/iphone-use-enhanced/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/programmingWTF/iphone-use-enhanced/actions/workflows/build-unsigned-ipa.yml)
[![Release](https://img.shields.io/github/v/release/programmingWTF/iphone-use-enhanced?include_prereleases&sort=semver)](https://github.com/programmingWTF/iphone-use-enhanced/releases)
![iOS](https://img.shields.io/badge/iOS-26%2B-black)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
![Swift + Rust](https://img.shields.io/badge/Swift%20%2B%20Rust-orange)

< 简体中文 | [English](./README.en.md) >

</div>

> **本项目是 [EliotAndres/iphone-use-app](https://github.com/EliotAndres/iphone-use-app) 的非官方增强版（fork）。**
> 原作者：Eliot Andres，原项目采用 AGPL-3.0。这个 fork 保留同样的许可证，并在其基础上针对
> **中文环境、国内网络、无 Mac 构建、界面与交互** 做了一整套工程化改造。
> 详细来源与第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 它是什么

iPhone Use 是一个运行在 iPhone 上的 iOS App：你在聊天框里写下任务，App 用开发者服务
（CoreDevice / Remote Pairing）截图自己的屏幕，把截图发给一个**支持视觉与工具调用**的大模型，
再按模型返回的坐标点按、滑动、输入、打开 App —— 直到它认为任务完成，最后用 Markdown 汇报。

整个循环都在手机本地；除了调用你配置的 LLM 接口，截图不会离开设备。运行时不依赖电脑。

## 与上游的差异

| 方向 | 上游 | 本增强版 |
|---|---|---|
| 构建与分发 | 需要 Mac，用 Xcode 手动编译 | **GitHub Actions 自动出未签名 IPA，直接挂到 Release**，没有 Mac 也能拿到安装包 |
| 国内网络 | DDI 从 GitHub raw 下载，经常卡住 | DDI 多镜像回退（`ghfast.top` / `gh-proxy.com` / raw），带**单卡实时进度**（速度、剩余时间、失败镜像） |
| 界面语言 | 全英文 | **默认全中文，设置里可一键切英文**（系统提示词保持原文，不随切换；快捷指令意图与系统权限提示跟系统语言） |
| 模型回复 | 纯文本 | **Markdown 渲染**：标题、粗斜体、任务列表、代码块（语言标签 + 复制按钮）、表格、引用、`$…$` / `$$…$$` 近似公式、`\*` 转义 |
| 界面风格 | 系统毛玻璃 | **液态玻璃（Liquid Glass）** 体系：iOS 26 走原生 `glassEffect`，17.4 回退毛玻璃；紫色只用在「新建会话 / 发送 / 用户气泡」三处 |
| 模型接入 | 只有 OpenRouter | 内置 **OpenRouter / DeepSeek**（默认 DeepSeek，`deepseek-flash` 支持视觉 + 工具调用），也可填任意 OpenAI 兼容端点 |
| 远程协作 | 无 | 可选 **Cloudflare Worker 网关**（`gateway/`），默认关闭，需要设备令牌与批准，全程有明确的安全边界 |

## 功能

- **运行时不依赖电脑**：智能体在 iPhone 上跑，控制的就是这台 iPhone。电脑只用一次，用来生成配对文件。
- **随时唤起**：聊天界面、Siri、「运行 Agent」快捷指令，或 `iphoneuse://run?prompt=…` 深链。
- **全过程可见**：每一步都有截图、动作与模型的一句话推理，失败原因直接写在聊天里。
- **结果可读**：结束时用 Markdown 总结；快捷指令/脚本也能拿到同一段文本。
- **可选远程网关**：把任务从电脑投递到手机执行，需要白名单密钥 + 手动批准，默认不启用。

## 环境要求

| 部分 | 说明 |
|---|---|
| **iPhone** | iOS 26 及以上（开发与验证基于 iOS 27.2）。工程的最低部署目标是 17.4，但 17.x 未做回归验证。需打开开发者模式。 |
| **Apple 账号** | **付费开发者团队**：可用 App 自带的内建回环 VPN（需要 Network Extension 权限）。<br>**免费 Apple ID**：只能用 `BUILTIN_VPN=NO` 构建，并安装 App Store 的 [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)，每 7 天重签一次。 |
| **配对文件** | 一次性生成（Windows 用 iDevicePair，Mac 用 `xcrun devicectl`），之后电脑不再需要。 |
| **视觉模型** | 支持图片输入 + 工具调用的任意 OpenAI 兼容接口，例如 OpenRouter，或 `https://api.deepseek.com` + `deepseek-flash`。 |
| **构建环境** | 只有自己编译时才需要 macOS + Xcode 26/27 + rustup；装现成包不需要。 |

## 安装（不需要 Mac）

1. **下载安装包**：到 [Releases](https://github.com/programmingWTF/iphone-use-enhanced/releases) 取最新的
   `iphone-use-app-unsigned.ipa`（未签名，需要你自己的证书）。
2. **签名**：用任意侧载工具签名并安装，例如 Sideloadly、爱思助手（i4Tools）、ESign、AllSign 等。
   免费 Apple ID 签名有效 7 天，最多 3 个 App；付费证书可签 1 年。
3. **改 bundle id**：`blog.eliot.iphoneuse` 已被上游团队注册，免费账号无法复用。
   签名时让工具自动加后缀（Sideloadly 的 `Use automatic bundle ID`），或在 CI 里用
   `bundle_id` 参数重新出包。**换 id 后必须重新导入配对文件**（配对与 bundle id 绑定）。
4. **生成配对文件**（一次性）：
   - Windows：下载 [iDevicePair](https://github.com/jkcoxson/idevice_pair/releases)，
     用 USB 连接手机，选 **Remote pairing** 模式，生成 `pairingFile.plist`。
   - macOS：`xcrun devicectl device pair --device <UDID> --store-here pair.plist`（参考 Apple 文档）。
5. **导入配对文件**：把 `pairingFile.plist` 通过「文件」App 放进 iPhone Use 的 `Documents/`，
   或在 App 的「设置 → 配对文件」里导入。
6. **开始使用**：打开 VPN（内建或 LocalDevVPN）、授予「本地网络」与「位置：始终」，
   在「设置 → 模型」里填接口地址、模型名和 API Key，然后回聊天页写下任务。

> 免费 Apple ID 每次重签都会换证书，**不要卸载 App**（卸载会丢掉配对文件与已下载的 DDI）。

## 首次配置清单

- [ ] 开发者模式已打开（设置 → 隐私与安全性 → 开发者模式）
- [ ] 配对文件已导入（设置 → 配对文件，显示 ✅）
- [ ] VPN 可用：付费团队用内建，免费账号装好 LocalDevVPN 并在「手机连接」里选中
- [ ] 本地网络权限 = 允许；位置权限 = 始终
- [ ] 模型：Base URL + 模型名 + API Key 填好，点「测试连接」通过
- [ ] 首次运行会自动下载开发者磁盘映像（DDI），可在进度卡里看到镜像与速度

## 使用提示

- **中文输入**：模型会先打出拼音，再点候选栏选字。如果某个 App 不认，会改用 `long_press` 长按输入框、
  在菜单里点「粘贴」，仍不行就会用 `ask_user_question` 请你自己补。
- **DDI 下载慢**：设置 → 手机连接 →「重新下载开发者磁盘映像」；也可以自己把 5 个文件放进
  `Documents/DDI/`，App 会直接认领，不再联网。
- **同时开代理 / VPN**：iPhone Use 需要占用唯一的 VPN 槽位。如果手机上还开着 TUN 模式的代理
  （ClashMi、Surge、Stash 等），在代理配置的「覆写」里放行回环地址，两者就能共存：

  ```yaml
  tun:
    loopback-address:
      - 10.7.0.1
  ```

  保存后重连代理，再回 App 里点「重新连接」即可。
- **每次运行都会弹「这台设备正被 Mac 远程查看」**：那是 iOS 对开发者服务的提示，实际没有数据离开手机。

## 构建

### 用 GitHub Actions（推荐，不需要 Mac）

fork 本仓库后，`.github/workflows/build-unsigned-ipa.yml` 会在 **`xcode-27` runner** 上：

1. 编译 `idevice` 静态库（`scripts/build-idevice.sh`）；
2. `xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 出未签名 `.app`；
3. 打包成 `iphone-use-app-unsigned.ipa`，上传为 artifact；
4. **打 `v*` tag 时自动创建 GitHub Release 并挂上 IPA**。

手动运行（Actions → Build unsigned IPA → Run workflow）支持三个参数：
`bundle_id`（自定义 bundle id）、`strip_extensions`（去掉 Widget 与 VPN 扩展）、`name_suffix`（产物后缀）。

> 注意：Xcode 26.6 的 Swift 前端会在 `iPhoneUse/Agent/AgentView.swift` 的输入框表达式上超时，
> 所以工作流固定使用 `xcode-27`。公开仓库的 Actions 免费，私有仓库会按 macOS 10 倍系数计费。

### 本地构建（需要 macOS）

```sh
rustup target add aarch64-apple-ios
bash scripts/build-idevice.sh                 # 产出 iPhoneUse/idevice/libidevice_ffi.a（约 45 MB，已被忽略）
xcodebuild -project iPhoneUse.xcodeproj -scheme iPhoneUse \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO BUILTIN_VPN=NO build
```

生成 IPA：

```sh
cd build/Build/Products/Release-iphoneos && mkdir -p Payload && cp -R iPhoneUse.app Payload
ditto -c -k --sequesterRsrc --keepParent Payload iphone-use-app-unsigned.ipa
```

### 自己签名

仓库**不包含任何签名身份**：`project.pbxproj` 里的 `DEVELOPMENT_TEAM` 已留空，
`bundle_id` 仍沿用上游的 `blog.eliot.iphoneuse`。请用自己的 Apple 账号签名：

- Xcode 里选自己的 Team，或
- 命令行 `DEVELOPMENT_TEAM=你的TeamID bundle_id=你的唯一id xcodebuild ...`；
- 免费账号记得加 `BUILTIN_VPN=NO`，并安装 LocalDevVPN。

## 项目结构

```
iPhoneUse/            iOS App（SwiftUI）
iPhoneUse/Agent/      聊天界面、智能体循环、模型设置、快捷指令意图、远程网关客户端
iPhoneUse/Device/     隧道、会话、截图/触控注入、DDI 下载
iPhoneUse/Support/    Markdown 渲染、液态玻璃样式、DDI 进度卡
TunnelProvider/       回环 VPN 扩展（付费团队可用）
AgentWidget/          Live Activity
idevice-patch/        idevice 的 Rust 补丁（中文输入相关能力）
scripts/              构建与调试脚本
gateway/              可选的 Cloudflare Worker 网关
docs/                 架构、功能范围、截图
```

## 文档

- [架构说明](docs/ARCHITECTURE.md) —— 隧道、配对、DDI、智能体循环与安全边界
- [功能范围](docs/FEATURES.md) —— 上游的功能清单与取舍
- [标签体系](LABELS.md) —— issue / PR 标签分级
- [更新日志](CHANGELOG.md)
- [参与贡献](CONTRIBUTING.md) · [English](CONTRIBUTING.en.md)
- [安全问题报告](SECURITY.md)

## 已知限制

- **蜂窝网络需要快捷指令**：iOS 拒绝在蜂窝下新建回环 VPN，App 会调用「切换蜂窝数据」快捷指令，
  连接期间关数据、连上后再打开。
- **同一时间只能有一个 VPN**：除非用 ClashMi 的 `loopback-address` 覆写，否则 Tailscale 等会被挤掉。
- **每次运行都有「远程查看」提示**：iOS 的系统行为，无法关闭。
- **配对文件会过期**：过期后需要重新生成并导入。
- **只能侧载**：依赖开发者服务与开发者模式，无法上架 App Store。
- **每步几秒**：耗时主要来自模型本身。
- **Apple 可能调整私有服务**：这是建立在私有协议上的实验性工具，不保证长期兼容。

## 免责声明

- 本项目**与 Apple Inc.、Eliot Andres 均无关联**，不是官方产品，也未获其背书。
- 它能操作手机，靠的是 iOS 的开发者服务与私有协议，属于**实验性**用法；系统升级可能随时让它失效。
- 请只在自己的设备、自己的账号、自己有权操作的环境中使用；不要用它绕过任何平台规则或进行欺诈。
- 签名证书、Apple 账号、模型 API Key 的安全由你自己负责；**不要**把证书、密钥、配对文件提交到仓库。
- 软件按 AGPL-3.0 「按现状」提供，作者与贡献者不对任何直接或间接损失负责。
- 「iPhone」「Apple」「iOS」是 Apple Inc. 的商标，本项目仅作描述性使用。

## 许可证

[AGPL-3.0](LICENSE) —— 与上游一致。修改并分发时必须保留同样的许可证与出处说明，
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

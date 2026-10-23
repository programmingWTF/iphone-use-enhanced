# 没有 Mac 怎么跑起来（Windows + GitHub Actions）

> 本文件是本地备忘，未提交到上游仓库。上游 README 说「配对一个 pairing file 必须用 Mac」，
> 实际上 Windows 上用 iDevicePair 生成 **Remote Pairing** 记录即可，不需要 Mac。
> 真正离不开 macOS 的只有「编译」这一步，可以交给 GitHub Actions 的 macOS runner。

## 实测记录（2026-10-23，Windows + GitHub Actions）

- 编译**成功**：`xcode-27` runner（默认 Xcode 27.1 / Rust 1.99），整条 job 只用 **1 分 31 秒**；
  artifact 10.9 MB，`sha256 = 50ddf43631348b5ec5a892ecc126ca90185e7a6cb634faee6faf7e7fe4d4590a`。
- 产物已核对：`Payload/iPhoneUse.app`，bundle id `blog.eliot.iphoneuse`，版本 0.1 (1)，
  `MinimumOSVersion 17.4`，arm64，含 `AgentWidget.appex` + `TunnelProvider.appex`。
- 先试过 `macos-26`（Xcode 26.6）：Rust 库能编，但 Swift 前端在
  `iPhoneUse/Agent/AgentView.swift:242`（composer 那个大 HStack）上
  “unable to type-check this expression in reasonable time” 超时 → 换 `xcode-27` 即可。
- 私有仓库跑一次约消耗 15–20 macOS 分钟额度（10 倍系数），成本可忽略。

## 0. 这个 App 是什么

- iOS 客户端（Swift/SwiftUI）+ 一个 Rust 静态库（jkcoxson/idevice 的 FFI）。
- 运行在 iPhone 本机上：mount Developer Disk Image → 起一个 loopback VPN（10.7.0.1）→
  通过 RemoteXPC/CoreDevice 截屏、点击、输入，把每步截图发给视觉模型，循环直到完成。
- 不是桌面端程序，Windows 上不能直接跑；它控制的是**装它的那台 iPhone**。

硬性要求：

| 项 | 说明 |
|---|---|
| iPhone | README 写 iOS 26+；工程 `IPHONEOS_DEPLOYMENT_TARGET = 17.4`，作者只在 26/27 上验证过。Developer Mode 必须开。 |
| Apple 账号 | 免费账号：用 `BUILTIN_VPN=NO` 构建 + App Store 装 LocalDevVPN，每 7 天重签一次，最多 3 个自签 App。<br>付费账号（$99/年）：可签 Network Extension entitlement，用 App 内建 VPN，有效期 1 年。 |
| Pairing file | Windows 用 iDevicePair 生成（Remote pairing 模式），USB 连一次。 |
| 模型 | OpenRouter key，或任意兼容 OpenAI 的、支持图片 + tool call 的端点。 |
| 网络 | 需要 Wi-Fi（蜂窝下 loopback VPN 连不上，见 TODO）。 |

## 1. 在 GitHub Actions 上编译（不需要 Mac / 不需要开发者账号）

用仓库里的 `.github/workflows/build-unsigned-ipa.yml`：

1. 把仓库推到自己的 GitHub 仓库（public 仓库的 Actions 标准 runner 免费；private 仓库
   按 macOS 10 倍系数扣额度，实测一次 job 1m31s ≈ 16 分钟额度）。
2. Actions → **Build unsigned IPA** → Run workflow（push 到 main 也会自动跑）。
3. 实测 2 分钟内跑完，下载 artifact `iphone-use-app-unsigned-ipa`，里面是
   `iphone-use-app-unsigned.ipa` 和 `sha256.txt`。

构建做了什么：`rustup target add aarch64-apple-ios` → `scripts/build-idevice.sh`
（clone jkcoxson/idevice @ 3854a5d，打 `idevice-patch/`，产出 45 MB 的
`libidevice_ffi.a`）→ `xcodebuild -configuration Release -destination generic/platform=iOS`
带 `CODE_SIGNING_ALLOWED=NO BUILTIN_VPN=NO` 出未签名 .app → 打包成 .ipa。

workflow 只产出未签名包：签名和安装都在 Windows 上做（见下），所以不需要把证书放进仓库。

## 2. Windows 上签名 + 安装：Sideloadly

1. 装 **网页版 iTunes**（Apple 官网下载的 exe，不要 Microsoft Store 版），它会装上
   Apple Mobile Device 驱动；Sideloadly 需要它。
2. 装 [Sideloadly](https://sideloadly.io/)。
3. USB 连 iPhone，解锁并点「信任」。
4. 把 `iphone-use-app-unsigned.ipa` 拖进 Sideloadly，填 Apple ID（免费/付费都行），Start。
   Sideloadly 会把主 App 和两个扩展（AgentWidget、TunnelProvider）一起重签并安装。
   **免费账号注意**：作者把 `blog.eliot.iphoneuse` 这个 App ID 注册过了，App ID 全局唯一，
   所以 Sideloadly 会强制换一个唯一 bundle id（Advanced Options 里也能手动改）。
   换了之后 App 内硬编码的 tunnel provider id 就对不上，内建 VPN 启动失败→自动回退
   LocalDevVPN，这正是免费号该走的路线，不影响使用。
   如果两个扩展的 App ID 注册不过去（免费号 10 个/周的上限），Advanced Options →
   **Remove Extensions** 去掉它们再装，App 主体照样能跑（只是没有 Live Activity、内建 VPN）。
5. iPhone：设置 → 隐私与安全性 → **开发者模式** 打开并重启；
   设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。
6. 免费账号：7 天后过期，重跑一次 Sideloadly 即可；想自动续签可以用 SideStore，
   但 SideStore 自己也要先侧载。

## 3. Windows 上生成 pairing file：iDevicePair

1. 从 [jkcoxson/idevice_pair releases](https://github.com/jkcoxson/idevice_pair/releases)
   下 Windows x86_64 的 exe。
2. 需要：iTunes 驱动、USB 线、设备设了锁屏密码、已侧载过一个带 `get-task-allow` 的 App
   （即上一步装好的本 App）、Developer Mode 已开。
3. 打开 iDevicePair，选中设备，模式选 **Remote pairing**，Generate；
   手机上点「信任」；然后 Save to file，得到 `.mobiledevicepairing` / plist。
4. 导入到这个 App：
   - 方式 A：App 内 设置 → Import Pairing File，选这个文件；
   - 方式 B：App 的 `UIFileSharingEnabled = true`，文件 App →「我的 iPhone」→ iphone-use-app
     目录，把文件命名成 `pairingFile.plist` 放进去（App 启动时会从 Documents 读取）。
5. 如果 App 报 pairing file invalid/expired，重新生成一份再导入。

## 4. 手机上的首次配置

1. App Store 装 [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)（免费账号路线必须装）。
2. 打开 App → 右上角齿轮 → Phone Connection：选 LocalDevVPN 并打开它；
   如果是付费账号且构建时 `BUILTIN_VPN=YES`，则走内建 VPN（会弹「添加 VPN 配置」）。
3. Settings → Model：填 OpenRouter key，选一个支持图片 + tool call 的模型。
4. 允许本地网络、位置「始终」、麦克风（语音输入用）。
5. 等输入框上方「未连接」提示消失（首次会下载并 mount Developer Disk Image）。
6. 输入任务开始跑；Dynamic Island / 聊天页可以 Stop。

## 5. 已知坑

- iOS 会弹「Device Hub: This device was viewed remotely from Mac」——即使根本没有 Mac，
  这是开发者服务被使用的正常提示。
- 内建 VPN 需要 Network Extension entitlement，免费 Apple ID 签不了，所以必须
  `BUILTIN_VPN=NO` + LocalDevVPN；两种 VPN 同一时间只能开一个（会顶掉 Tailscale 等）。
- 蜂窝网络下 iOS 拒绝新的 loopback VPN 连接，需要快捷指令先关数据再连（README 有说明）。
- 免费账号 7 天过期、3 个 App 上限、10 个 App ID/周。
- 作者 TODO 里还有未验证项：heartbeat、Live Activity 的 Stop、30 分钟 soak test。
- 上游没有 tag / release，只能自己编；bundle id 是 `blog.eliot.iphoneuse`
  （改了 bundle id 之后 pairing file 要重新导入）。tunnel provider id 是硬编码在
  `iPhoneUse/Device/Connection.swift:154` 的字符串，所以换 bundle id 后内建 VPN 一定连不上，
  只能靠 LocalDevVPN。
- 用 Xcode 26.x 编译会挂在 `AgentView.swift:242` 的类型检查超时上；必须用 Xcode 27 的 runner
  （`xcode-27`）。

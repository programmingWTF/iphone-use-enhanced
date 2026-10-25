# TODO · 未完成项

范围定义见 [docs/FEATURES.md](docs/FEATURES.md)。这里只放「已知但还没做」的事，做完就删。

## 需要真机验证

- [ ] 内建回环 VPN 在蜂窝下的表现：上游报告 iOS 26.6/27 上蜂窝单卡不可用（LocalDevVPN issue #31），
      当前只能靠「切换蜂窝数据」快捷指令绕开。
- [ ] `idevice` 用 `ring` 而不是 `aws-lc` 时，配对与 TLS 是否仍然稳定。
- [ ] 智能体运行期间的心跳（heartbeat）在长任务下的表现。
- [ ] Live Activity 上的「停止」是否真能中断当前运行。
- [ ] 重启后首次运行、以及 30 分钟长跑的内存与电量表现。
- [ ] iOS 17.x / 18.x 上的回归（工程最低支持 17.4，但只在 26/27 上验证过）。

## 体验

- [ ] App 图标还是占位（`iPhoneUse/AppIcon.icon`）。
- [ ] 中文输入在自绘输入框 / WebView 里的兜底路径，目前只有 `long_press` +「粘贴」。
- [ ] 首次安装的一页式引导（目前是设置页里的清单）。

## 工程

- [ ] 合并上游新提交：`896bae8 Add long_press tool`、`20ac066 Hold-to-talk sends after transcription; steadier waveform`
      （本 fork 从 `89afa45` 分出，自己的 `probe_long_press` 与按住说话实现需要与上游版本对齐后再合并）。
- [ ] 给 `gateway/` 补端到端测试（目前是单元测试）。
- [ ] CI 缓存 `idevice` 编译产物，缩短每次构建时间。
- [ ] 应用内「导出日志」按钮（现在需要走「文件」App）。

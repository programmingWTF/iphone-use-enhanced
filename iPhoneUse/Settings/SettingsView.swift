//
//  SettingsView.swift
//  iPhoneUse
//
//  A setup checklist first (what the agent needs to run), then agent options.
//  Each checklist row opens the screen that fixes it.
//

import CoreLocation
import SwiftUI

private enum Links {
    static let repo = URL(string: "https://github.com/EliotAndres/iphone-use-app")!
    static let pairingFileGuide = URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!
    static let openRouterKeys = URL(string: "https://openrouter.ai/settings/keys")!
}

struct SettingsView: View {
    @ObservedObject private var llm = LLMSettings.shared
    @ObservedObject private var connection = Connection.shared
    @ObservedObject private var location = BackgroundLocationManager.shared
    @ObservedObject private var remote = RemoteGateway.shared
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasPairingFile = Connection.shared.hasPairingFile
    @State private var isShowingPairingFilePicker = false
    @State private var pairingMessage: (text: String, isError: Bool)?
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    GlassSection("准备工作", weight: .light) {
                        NavigationLink { LLMSettingsView(settings: llm) } label: {
                            CheckRow("模型 API 密钥", symbol: "cpu",
                                     detail: llm.problem ?? "\(llm.provider.title) · \(llm.model)",
                                     state: llm.problem == nil ? .done : .error,
                                     tint: Color.blue)
                        }
                        .glassRow()
                        GlassRowDivider()
                        Button { isShowingPairingFilePicker = true } label: {
                            CheckRow("配对文件", symbol: "doc.text",
                                     detail: hasPairingFile ? "已导入。点击可替换。" : "点击导入。",
                                     state: hasPairingFile ? .done : .error,
                                     tint: Color.blue)
                        }
                        .buttonStyle(.haptic(.plain))
                        .glassRow()
                        if let pairingMessage {
                            Text(pairingMessage.text)
                                .font(.caption)
                                .foregroundStyle(pairingMessage.isError ? .red : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                        GlassRowDivider()
                        NavigationLink { ConnectionSettingsView(connection: connection) } label: {
                            CheckRow("手机连接", symbol: "iphone",
                                     detail: connection.step.summary, state: connection.step.checkState,
                                     tint: Color.blue)
                        }
                        .glassRow()
                        GlassRowDivider()
                        NavigationLink { BackgroundSettingsView(location: location) } label: {
                            CheckRow("后台运行", symbol: "location",
                                     detail: backgroundDetail, state: backgroundState,
                                     tint: Color.blue)
                        }
                        .glassRow()
                    } footer: {
                        // A link, drawn like one: the icon, an underline, and the same blue
                        // as the 配对文件 row above it.
                        Link(destination: Links.pairingFileGuide) {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                Text("如何获取配对文件").underline()
                            }
                            .foregroundStyle(Color.blue)
                        }
                    }

                    GlassSection("远程调用", weight: .light) {
                        Toggle(isOn: $remote.enabled) {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "network")
                                Text("开放接口")
                            }
                        }
                        .glassRow()
                        if remote.enabled {
                            GlassRowDivider()
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "link")
                                TextField("网关网址（https://…）", text: $remote.address)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("网关网址")
                            }
                            .glassRow()
                            GlassRowDivider()
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "key.horizontal")
                                SecureField("设备令牌", text: $remote.token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("设备令牌")
                            }
                            .glassRow()
                            GlassRowDivider()
                            Label(remote.status, systemImage: "antenna.radiowaves.left.and.right")
                                .font(.footnote).foregroundStyle(.secondary).glassRow()
                        }
                    } footer: {
                        Text("仅在前台接收任务，每次执行前由你确认。同时只处理一个任务，不建立待办队列。设备令牌由网关管理员提供，与模型 API 密钥不同。")
                    }
                    .disabled(remote.configurationLocked)

                    GlassSection("语音", weight: .light) {
                        Picker(selection: $llm.voiceModel) {
                            ForEach(Set(LLMSettings.voiceModels + [llm.voiceModel]).sorted(), id: \.self) { Text($0).tag($0) }
                        } label: {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "waveform")
                                Text("模型")
                            }
                        }
                        .glassRow()
                        GlassRowDivider()
                        Picker(selection: $llm.voiceLanguage) {
                            Text("自动检测").tag("")
                            ForEach(LLMSettings.voiceLanguages, id: \.self) {
                                Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "globe")
                                Text("语言")
                            }
                        }
                        .glassRow()
                    } footer: {
                        Text(llm.provider == .openRouter
                             ? "由 OpenRouter 用你的 API 密钥转写。手动指定语言比自动检测更快、更准确。"
                             : "语音输入仅在服务商为 OpenRouter 时可用。")
                    }
                    .disabled(llm.provider != .openRouter)

                    GlassSection("智能体", weight: .light) {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "arrow.triangle.2.circlepath")
                            Stepper("最大步数：\(llm.maxSteps)", value: $llm.maxSteps, in: 5...500, step: 5)
                        }
                        .glassRow()
                        GlassRowDivider()
                        NavigationLink {
                            SystemPromptEditor(settings: llm)
                        } label: {
                            // `NavigationLink` draws its label in the accent colour outside a
                            // Form; these rows stay in the plain label colour so the section
                            // reads like the rest of the settings.
                            GlassDisclosureLabel(chevron: Color.primary) {
                                HStack(spacing: 12) {
                                    GlassRowIcon(name: "text.alignleft", tint: Color.primary)
                                    Text("系统提示词").foregroundStyle(.primary)
                                }
                            }
                        }
                            .glassRow()
                        GlassRowDivider()
                        NavigationLink {
                            ShortcutsGuideView()
                        } label: {
                            GlassDisclosureLabel(chevron: Color.primary) {
                                HStack(spacing: 12) {
                                    GlassRowIcon(name: "command", tint: Color.primary)
                                    Text("快捷指令与深链").foregroundStyle(.primary)
                                }
                            }
                        }
                            .glassRow()
                        GlassRowDivider()
                        Button(role: .destructive) { showClearHistoryConfirmation = true } label: {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "trash")
                                Text("清空历史").foregroundStyle(.red)
                            }
                        }
                            .glassRow()
                            .confirmationDialog("删除所有会话？", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
                                Button("清空历史", role: .destructive) { PhoneAgent.shared.clearHistory() }
                            }
                    }

                    GlassSection("关于", weight: .light) {
                        Link(destination: Links.repo) {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "link")
                                Text("GitHub")
                            }
                        }
                            .glassRow()
                        GlassRowDivider()
                        NavigationLink {
                            CreditsView()
                        } label: {
                            GlassDisclosureLabel {
                                HStack(spacing: 12) {
                                    GlassRowIcon(name: "heart")
                                    Text("鸣谢")
                                }
                            }
                        }
                            .glassRow()
                        GlassRowDivider()
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "info.circle")
                            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                        }
                            .glassRow()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("设置")
            .scrollDismissesKeyboard(.interactively)
        }
        .task { await connection.connect() } // no-op when connected; retries after a failure
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hasPairingFile = connection.hasPairingFile }
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes
        ) { result in
            do {
                try PairingFileStore.importFromPicker(result.get())
                hasPairingFile = true
                pairingMessage = ("已导入，正在连接…", false)
                Task { await connection.connect(force: true) }
            } catch {
                pairingMessage = ("导入失败：\(error.localizedDescription)", true)
            }
        }
    }

    // Amber, not red: silent audio still keeps most runs alive.
    private var backgroundState: CheckState {
        if !keepAliveLocation && location.authorization != .denied { return .done } // audio only, chosen
        return location.authorization == .authorizedAlways ? .done : .warning
    }

    private var backgroundDetail: String {
        if !keepAliveLocation && location.authorization != .denied { return "静音音频" }
        switch location.authorization {
        case .authorizedAlways: return "静音音频 + 定位"
        case .notDetermined: return "允许定位以提升稳定性"
        case .authorizedWhenInUse: return "把定位权限改为“始终”"
        default: return "定位被拒绝：仅静音音频"
        }
    }
}

enum CheckState { case done, warning, error, working }

private struct CheckRow: View {
    let title: String
    let symbol: String
    let detail: String
    let state: CheckState
    /// A row that is itself about a colour (the pairing file's blue) passes it in; every
    /// other row keeps the default label colour.
    let tint: Color?

    init(_ title: String, symbol: String, detail: String, state: CheckState, tint: Color? = nil) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.state = state
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            GlassRowIcon(name: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(tint ?? Color.primary)
                // A tinted row tints its caption too, one notch lighter so the title still
                // leads; the trailing check/cross keeps its own green/red.
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(tint.map { $0.opacity(0.8) } ?? Color.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            statusMark
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// The checklist state, trailing: the leading column is for "what is this row",
    /// the trailing one is for "is it done".
    @ViewBuilder
    private var statusMark: some View {
        Group {
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .working: ProgressView()
            }
        }
        .font(.body)
    }
}

private extension Connection.Step {
    var summary: String {
        switch self {
        case .idle: "未连接"
        case .working(let message): message
        case .ready: VPNMode.current == .localDevVPN ? "已通过 LocalDevVPN 连接" : "已连接这台 iPhone"
        case .failed(let message): message
        }
    }

    var checkState: CheckState {
        switch self {
        case .idle: .warning
        case .working: .working
        case .ready: .done
        case .failed: .error
        }
    }
}

private struct LLMSettingsView: View {
    @ObservedObject var settings: LLMSettings
    @State private var isTesting = false
    @State private var testMessage: (text: String, isError: Bool)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlassSection(weight: .light) {
                    Picker(selection: $settings.provider) {
                        ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                    } label: {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "cloud")
                            Text("服务商")
                        }
                    }
                    .glassRow()
                    if settings.provider == .custom {
                        GlassRowDivider()
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "link")
                            TextField("接口地址", text: $settings.customURL, prompt: Text(verbatim: "https://…/v1"))
                                .keyboardType(.URL)
                        }
                        .glassRow()
                    }
                    GlassRowDivider()
                    HStack(spacing: 12) {
                        GlassRowIcon(name: "key")
                        SecureField("API 密钥", text: $settings.apiKey,
                                    prompt: Text(settings.provider == .custom ? "API 密钥（可选）" : "API 密钥"))
                    }
                    .glassRow()
                    GlassRowDivider()
                    HStack(spacing: 12) {
                        GlassRowIcon(name: "cube")
                        ModelPicker(settings: settings)
                    }
                    .glassRow()
                } footer: {
                    if settings.provider == .openRouter {
                        Link("获取 OpenRouter API 密钥", destination: Links.openRouterKeys)
                    } else {
                        Text("任意兼容 OpenAI 的接口，需支持图像识别和工具调用。语音输入仅在 OpenRouter 下可用。")
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                GlassSection(weight: .light) {
                    Button {
                        isTesting = true
                        testMessage = nil
                        Task {
                            testMessage = await settings.testConnection()
                            isTesting = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "bolt")
                            Text(settings.provider == .openRouter ? "测试 OpenRouter 连接" : "测试连接")
                        }
                    }
                    .disabled(isTesting)
                    .glassRow()
                    if isTesting {
                        ProgressView()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else if let testMessage {
                        Text(testMessage.text)
                            .font(.caption)
                            .foregroundStyle(testMessage.isError ? .red : .green)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle("模型 API 密钥")
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ConnectionSettingsView: View {
    @ObservedObject var connection: Connection
    @AppStorage(VPNMode.key) private var vpnMode = VPNMode.builtIn
    @State private var showDDIConfirmation = false
    @State private var ddiMessage: (text: String, isError: Bool)?

    /// The download center owns the state for both the automatic download and a manual
    /// one, so the button and the card below always agree on whether one is running.
    private var isRedownloadingDDI: Bool { DDIDownloadCenter.shared.isRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // The only coloured card in Settings: it reports the live connection state,
                // so here the colour is the information.
                GlassSection(tint: statusTint, weight: .light) {
                    CheckRow("状态", symbol: "iphone", detail: connection.step.summary, state: connection.step.checkState)
                        .glassRow()
                }

                GlassSection(weight: .light) {
                    Picker(selection: $vpnMode) {
                        Text("内置").tag(VPNMode.builtIn)
                        Text("LocalDevVPN").tag(VPNMode.localDevVPN)
                    } label: {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "network")
                            Text("VPN")
                        }
                    }
                    .glassRow()
                    GlassRowDivider()
                    Button { Task { await connection.connect(force: true) } } label: {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "arrow.clockwise")
                            Text("重新连接")
                        }
                    }
                    .disabled(connection.step.checkState == .working || !connection.hasPairingFile)
                    .glassRow()
                } footer: {
                    if vpnMode == .builtIn {
                        Text("启动内置 VPN，连接这台 iPhone 的开发者服务并挂载开发者磁盘映像。")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("适用于没有 VPN 权限的构建（免费 Apple ID）。打开 LocalDevVPN，再点重新连接即可连上这台 iPhone 的开发者服务并挂载开发者磁盘映像。")
                            Link("获取 LocalDevVPN", destination: VPNMode.localDevVPNURL)
                        }
                    }
                }

                GlassSection(weight: .light) {
                    Button { showDDIConfirmation = true } label: {
                        HStack(spacing: 12) {
                            GlassRowIcon(name: "externaldrive")
                            Text("重新下载开发者磁盘映像")
                        }
                    }
                    .disabled(isRedownloadingDDI)
                    .glassRow()
                    if isRedownloadingDDI {
                        DDIProgressCard(embedded: true)
                            .padding(.bottom, 14)
                    } else if let ddiMessage {
                        Text(ddiMessage.text)
                            .font(.caption)
                            .foregroundStyle(ddiMessage.isError ? .red : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                } footer: {
                    Text("仅在反复挂载失败时使用，比如 iOS 升级之后。")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle("手机连接")
        .confirmationDialog("重新下载开发者磁盘映像？", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("重新下载", role: .destructive) { redownloadDDI() }
        }
    }

    /// Green when connected, red for anything the user has to act on, blue while working.
    private var statusTint: Color {
        switch connection.step.checkState {
        case .done: GlassTint.success
        case .warning, .error: GlassTint.failure
        case .working: GlassTint.blue
        }
    }

    private func redownloadDDI() {
        ddiMessage = nil
        Task {
            do {
                try await DeveloperDiskImageService.shared.redownload()
                ddiMessage = ("开发者磁盘映像已下载。", false)
            } catch {
                ddiMessage = ("下载失败：\(error.localizedDescription)", true)
            }
        }
    }
}

private struct BackgroundSettingsView: View {
    @ObservedObject var location: BackgroundLocationManager
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlassSection(weight: .light) {
                    HStack(spacing: 12) {
                        GlassRowIcon(name: "location")
                        LabeledContent("定位权限", value: authorizationText)
                    }
                    .glassRow()
                    if location.authorization == .notDetermined {
                        GlassRowDivider()
                        Button { location.requestAuthorizationIfNeeded() } label: {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "location.circle")
                                Text("允许定位")
                            }
                        }
                        .glassRow()
                    } else if location.authorization != .authorizedAlways {
                        GlassRowDivider()
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            HStack(spacing: 12) {
                                GlassRowIcon(name: "gearshape")
                                Text("打开 iOS 设置")
                            }
                        }
                        .glassRow()
                    }
                } footer: {
                    Text("后台定位只在权限为“始终”时才能让智能体保持运行。")
                }

                GlassSection(weight: .light) {
                    HStack(spacing: 12) {
                        GlassRowIcon(name: "speaker.slash")
                        Toggle("静音音频", isOn: $keepAliveAudio)
                            .onChange(of: keepAliveAudio) { _, enabled in
                                if !enabled, !keepAliveLocation { keepAliveLocation = true }
                                keepAliveDidChange()
                            }
                    }
                    .glassRow()
                    GlassRowDivider()
                    HStack(spacing: 12) {
                        GlassRowIcon(name: "location")
                        Toggle("后台定位", isOn: $keepAliveLocation)
                            .onChange(of: keepAliveLocation) { _, enabled in
                                if enabled {
                                    location.requestAuthorizationIfNeeded()
                                } else if !keepAliveAudio {
                                    keepAliveAudio = true
                                }
                                keepAliveDidChange()
                            }
                    }
                    .glassRow()
                } footer: {
                    Text("让智能体在使用其他 App 时保持运行。至少需要开启一项。")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .navigationTitle("后台运行")
    }

    private var authorizationText: String {
        switch location.authorization {
        case .authorizedAlways: "始终"
        case .authorizedWhenInUse: "使用期间"
        case .notDetermined: "未询问"
        default: "已拒绝"
        }
    }

    private func keepAliveDidChange() {
        BackgroundAudioManager.shared.configurationDidChange()
        BackgroundLocationManager.shared.configurationDidChange()
    }
}

private struct SystemPromptEditor: View {
    @ObservedObject var settings: LLMSettings

    var body: some View {
        TextEditor(text: $settings.systemPrompt)
            .font(.callout)
            .padding(.horizontal)
            .navigationTitle("系统提示词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("恢复默认") { settings.systemPrompt = LLMSettings.defaultSystemPrompt }
                    .disabled(settings.systemPrompt == LLMSettings.defaultSystemPrompt)
            }
    }
}

private struct CreditsView: View {
    private let credits: [(name: String, detail: String, url: String)] = [
        ("StikDebug", "隧道、配对文件和开发者磁盘映像相关代码基于 Stephen 及贡献者的 StikDebug。",
         "https://github.com/StephenDev0/StikDebug"),
        ("idevice", "用于访问 iPhone 开发者服务的 Rust 库。",
         "https://github.com/jkcoxson/idevice"),
        ("LocalDevVPN / StosVPN", "环回 VPN 基于 SideStore 团队的 StosVPN，经 LocalDevVPN 使用。",
         "https://github.com/jkcoxson/LocalDevVPN"),
        ("esp32-iphone-agent", "模型服务商与模型选择器的设计参考。",
         "https://github.com/onehumanbeing/esp32-iphone-agent"),
        ("DeveloperDiskImage", "首次启动时下载的开发者磁盘映像来源。",
         "https://github.com/doronz88/DeveloperDiskImage"),
    ]

    var body: some View {
        List(credits, id: \.name) { credit in
            Link(destination: URL(string: credit.url)!) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.name).foregroundStyle(.primary)
                    Text(credit.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("鸣谢")
    }
}

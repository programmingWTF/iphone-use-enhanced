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
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasPairingFile = Connection.shared.hasPairingFile
    @State private var isShowingPairingFilePicker = false
    @State private var pairingMessage: (text: String, isError: Bool)?
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { LLMSettingsView(settings: llm) } label: {
                        CheckRow("模型 API 密钥", detail: llm.problem ?? "\(llm.provider.title) · \(llm.model)",
                                 state: llm.problem == nil ? .done : .error)
                    }
                    Button { isShowingPairingFilePicker = true } label: {
                        CheckRow("配对文件", detail: hasPairingFile ? "已导入。点击可替换。" : "点击导入。",
                                 state: hasPairingFile ? .done : .error)
                    }
                    .buttonStyle(.haptic(.plain))
                    if let pairingMessage {
                        Text(pairingMessage.text)
                            .font(.caption)
                            .foregroundStyle(pairingMessage.isError ? .red : .secondary)
                    }
                    NavigationLink { ConnectionSettingsView(connection: connection) } label: {
                        CheckRow("手机连接", detail: connection.step.summary, state: connection.step.checkState)
                    }
                    NavigationLink { BackgroundSettingsView(location: location) } label: {
                        CheckRow("后台运行", detail: backgroundDetail, state: backgroundState)
                    }
                } header: {
                    Text("准备工作")
                } footer: {
                    Link("如何获取配对文件", destination: Links.pairingFileGuide)
                }

                Section {
                    Picker("模型", selection: $llm.voiceModel) {
                        ForEach(Set(LLMSettings.voiceModels + [llm.voiceModel]).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("语言", selection: $llm.voiceLanguage) {
                        Text("自动检测").tag("")
                        ForEach(LLMSettings.voiceLanguages, id: \.self) {
                            Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0)
                        }
                    }
                } header: {
                    Text("语音")
                } footer: {
                    Text(llm.provider == .openRouter
                         ? "由 OpenRouter 用你的 API 密钥转写。手动指定语言比自动检测更快、更准确。"
                         : "语音输入仅在服务商为 OpenRouter 时可用。")
                }
                .disabled(llm.provider != .openRouter)

                Section("智能体") {
                    Stepper("最大步数：\(llm.maxSteps)", value: $llm.maxSteps, in: 5...200, step: 5)
                    NavigationLink("系统提示词") { SystemPromptEditor(settings: llm) }
                    NavigationLink("快捷指令与深链") { ShortcutsGuideView() }
                    Button("清空历史", role: .destructive) { showClearHistoryConfirmation = true }
                        .confirmationDialog("删除所有会话？", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
                            Button("清空历史", role: .destructive) { PhoneAgent.shared.clearHistory() }
                        }
                }

                Section("关于") {
                    Link("GitHub", destination: Links.repo)
                    NavigationLink("鸣谢") { CreditsView() }
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
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
    let detail: String
    let state: CheckState

    init(_ title: String, detail: String, state: CheckState) {
        self.title = title
        self.detail = detail
        self.state = state
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .warning: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case .working: ProgressView()
                }
            }
            .font(.title3)
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
        Form {
            Section {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(LLMProvider.allCases) { Text($0.title).tag($0) }
                }
                if settings.provider == .custom {
                    TextField("接口地址", text: $settings.customURL, prompt: Text(verbatim: "https://…/v1"))
                        .keyboardType(.URL)
                }
                SecureField("API 密钥", text: $settings.apiKey,
                            prompt: Text(settings.provider == .custom ? "API 密钥（可选）" : "API 密钥"))
                ModelPicker(settings: settings)
            } footer: {
                if settings.provider == .openRouter {
                    Link("获取 OpenRouter API 密钥", destination: Links.openRouterKeys)
                } else {
                    Text("任意兼容 OpenAI 的接口，需支持图像识别和工具调用。语音输入仅在 OpenRouter 下可用。")
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section {
                Button(settings.provider == .openRouter ? "测试 OpenRouter 连接" : "测试连接") {
                    isTesting = true
                    testMessage = nil
                    Task {
                        testMessage = await settings.testConnection()
                        isTesting = false
                    }
                }
                .disabled(isTesting)
                if isTesting {
                    ProgressView()
                } else if let testMessage {
                    Text(testMessage.text)
                        .font(.caption)
                        .foregroundStyle(testMessage.isError ? .red : .green)
                }
            }
        }
        .navigationTitle("模型 API 密钥")
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ConnectionSettingsView: View {
    @ObservedObject var connection: Connection
    @AppStorage(VPNMode.key) private var vpnMode = VPNMode.builtIn
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiProgress = 0.0
    @State private var ddiMessage: (text: String, isError: Bool)?

    var body: some View {
        Form {
            Section {
                CheckRow("状态", detail: connection.step.summary, state: connection.step.checkState)
                Picker("VPN", selection: $vpnMode) {
                    Text("内置").tag(VPNMode.builtIn)
                    Text("LocalDevVPN").tag(VPNMode.localDevVPN)
                }
                Button("重新连接") { Task { await connection.connect(force: true) } }
                    .disabled(connection.step.checkState == .working || !connection.hasPairingFile)
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
            Section {
                Button("重新下载开发者磁盘映像") { showDDIConfirmation = true }
                    .disabled(isRedownloadingDDI)
                if isRedownloadingDDI {
                    ProgressView(value: ddiProgress)
                } else if let ddiMessage {
                    Text(ddiMessage.text)
                        .font(.caption)
                        .foregroundStyle(ddiMessage.isError ? .red : .secondary)
                }
            } footer: {
                Text("仅在反复挂载失败时使用，比如 iOS 升级之后。")
            }
        }
        .navigationTitle("手机连接")
        .confirmationDialog("重新下载开发者磁盘映像？", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("重新下载", role: .destructive) { redownloadDDI() }
        }
    }

    private func redownloadDDI() {
        isRedownloadingDDI = true
        ddiMessage = nil
        Task {
            do {
                try await DeveloperDiskImageService.shared.redownload { progress, _ in
                    Task { @MainActor in ddiProgress = progress }
                }
                ddiMessage = ("开发者磁盘映像已下载。", false)
            } catch {
                ddiMessage = ("下载失败：\(error.localizedDescription)", true)
            }
            isRedownloadingDDI = false
        }
    }
}

private struct BackgroundSettingsView: View {
    @ObservedObject var location: BackgroundLocationManager
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true

    var body: some View {
        Form {
            Section {
                LabeledContent("定位权限", value: authorizationText)
                if location.authorization == .notDetermined {
                    Button("允许定位") { location.requestAuthorizationIfNeeded() }
                } else if location.authorization != .authorizedAlways {
                    Button("打开 iOS 设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } footer: {
                Text("后台定位只在权限为“始终”时才能让智能体保持运行。")
            }
            Section {
                Toggle("静音音频", isOn: $keepAliveAudio)
                    .onChange(of: keepAliveAudio) { _, enabled in
                        if !enabled, !keepAliveLocation { keepAliveLocation = true }
                        keepAliveDidChange()
                    }
                Toggle("后台定位", isOn: $keepAliveLocation)
                    .onChange(of: keepAliveLocation) { _, enabled in
                        if enabled {
                            location.requestAuthorizationIfNeeded()
                        } else if !keepAliveAudio {
                            keepAliveAudio = true
                        }
                        keepAliveDidChange()
                    }
            } footer: {
                Text("让智能体在使用其他 App 时保持运行。至少需要开启一项。")
            }
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

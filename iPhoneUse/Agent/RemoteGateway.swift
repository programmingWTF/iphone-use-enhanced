import Combine
import SwiftUI
import UIKit

struct RemoteRequest: Decodable, Identifiable {
    let id: String
    let agent: String
    let prompt: String
    let expiresAt: Double
}

/// Foreground-only admission. A confirmed run may keep reporting while controlling other apps.
@MainActor
final class RemoteGateway: ObservableObject {
    static let shared = RemoteGateway()
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "remote.enabled"); reconfigure() } }
    @Published var address: String { didSet { UserDefaults.standard.set(address, forKey: "remote.address"); reconfigure() } }
    @Published var token: String { didSet { Keychain.set(token, for: "remote.deviceToken"); reconfigure() } }
    @Published private(set) var automaticallyApprove: Bool
    @Published private(set) var status = t("已关闭")
    @Published private(set) var pending: RemoteRequest?

    private var foreground = false
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var runObserver: AnyCancellable?
    private weak var approvalController: UIViewController?
    @Published private var runningID: String?
    @Published private var awaitingExecution: String?
    @Published private var ready = false
    private var lastAcknowledgement = Date.now
    @Published private var finished: (id: String, result: String)?

    var configurationLocked: Bool { pending != nil || runningID != nil || awaitingExecution != nil || finished != nil }
    var isAcceptingTasks: Bool { ready && foreground && enabled && !PhoneAgent.shared.isRunning && !configurationLocked }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "remote.enabled")
        address = UserDefaults.standard.string(forKey: "remote.address") ?? ""
        token = Keychain.get("remote.deviceToken") ?? ""
        automaticallyApprove = UserDefaults.standard.bool(forKey: "remote.automaticallyApprove")
        // A process restart must report an interrupted task, never replay phone operations.
        if let id = UserDefaults.standard.string(forKey: "remote.activeID") {
            finished = (id, UserDefaults.standard.string(forKey: "remote.result") ?? "error: 应用重启，任务已中断") // l10n:keep protocol payload
        }
        runObserver = PhoneAgent.shared.$isRunning.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.agentStateChanged() }
        }
    }

    var configurationProblem: String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            return t("请填写 HTTPS 网关网址，不要附带令牌或查询参数")
        }
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t("请填写网关的设备令牌") }
        return nil
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if !active, pending != nil { decline() }
        refreshConnection()
        sendStatus()
    }

    /// Enabling is called only by the explicit risk confirmation in Settings.
    func setAutomaticApproval(_ enabled: Bool) {
        automaticallyApprove = enabled
        UserDefaults.standard.set(enabled, forKey: "remote.automaticallyApprove")
    }

    private func reconfigure() {
        reconnectTask?.cancel()
        // Once approved, finish with the original connection and credentials.
        guard runningID == nil, awaitingExecution == nil else { return }
        decline()
        disconnect()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.refreshConnection()
        }
    }

    private func refreshConnection() {
        guard enabled || runningID != nil || awaitingExecution != nil || finished != nil else { disconnect(); status = t("已关闭"); return }
        guard foreground || runningID != nil || awaitingExecution != nil || finished != nil else { disconnect(); status = t("后台不接收新任务"); return }
        guard let problem = configurationProblem else {
            if socket == nil { connect() }
            return
        }
        disconnect(); status = problem
    }

    private func connect() {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        components.scheme = "wss"
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").map(String.init).reduce("") { $0 + "/" + $1 } + "/v1/device/connect"
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.setValue("iphone-use-app/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        let connection = URLSession.shared.webSocketTask(with: request)
        socket = connection
        ready = false
        lastAcknowledgement = .now
        status = t("正在连接网关…")
        connection.resume()
        receiveTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let incoming = try await connection.receive()
                    guard let self, self.socket === connection else { return }
                    let data: Data
                    switch incoming {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    self.handle(data)
                }
            } catch {
                guard let self, self.socket === connection, !Task.isCancelled else { return }
                self.connectionLost()
            }
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, self.socket === connection else { return }
                if Date.now.timeIntervalSince(self.lastAcknowledgement) > 30 {
                    self.connectionLost(); return
                }
                self.sendStatus()
                self.sendFinished()
            }
        }
    }

    private func disconnect() {
        receiveTask?.cancel(); heartbeatTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil; ready = false
    }

    private func connectionLost() {
        disconnect()
        decline()
        // An approval without the server's execute acknowledgement must not run later.
        if let id = awaitingExecution {
            awaitingExecution = nil
            saveFinished(id: id, result: "error: 确认连接中断，任务未启动") // l10n:keep protocol payload
        }
        status = t("连接断开，正在重试…")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.refreshConnection()
        }
    }

    private func send(_ value: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return }
        Task { [weak self] in
            do { try await socket.send(.string(text)) }
            catch { if self?.socket === socket { self?.connectionLost() } }
        }
    }

    private func sendStatus() {
        guard ready else { return }
        send(["type": "status", "accepting": foreground && enabled && !PhoneAgent.shared.isRunning && pending == nil && awaitingExecution == nil && finished == nil,
              "busy": PhoneAgent.shared.isRunning || pending != nil || awaitingExecution != nil || finished != nil])
    }

    private func sendFinished() {
        guard ready, let finished else { return }
        send(["type": "complete", "id": finished.id, "result": finished.result,
              "success": finished.result.hasPrefix("done: ")])
    }

    private func handle(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = value["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true; lastAcknowledgement = .now; sendFinished(); sendStatus()
        case "status_ack":
            lastAcknowledgement = .now
            if PhoneAgent.shared.isRunning { status = t("正在执行任务") }
            else if pending != nil { status = t("等待你确认任务") }
            else if awaitingExecution != nil { status = t("正在确认执行") }
            else if finished != nil { status = t("正在回传结果") }
            else { status = foreground ? t("已连接，前台可接收任务") : t("后台不接收新任务") }
        case "task", "execute":
            guard let body = value["task"], let taskData = try? JSONSerialization.data(withJSONObject: body),
                  let request = try? JSONDecoder().decode(RemoteRequest.self, from: taskData) else { return }
            if type == "task" { receive(request) } else { execute(request) }
        case "withdraw":
            if value["id"] as? String == pending?.id { clearApproval() }
            if value["id"] as? String == awaitingExecution {
                awaitingExecution = nil
                UserDefaults.standard.removeObject(forKey: "remote.activeID")
            }
            sendStatus()
        case "settled":
            if value["id"] as? String == finished?.id {
                finished = nil
                UserDefaults.standard.removeObject(forKey: "remote.activeID")
                UserDefaults.standard.removeObject(forKey: "remote.result")
            }
            sendStatus(); refreshConnection()
        default: break
        }
    }

    private func receive(_ request: RemoteRequest) {
        guard foreground, enabled, !PhoneAgent.shared.isRunning, pending == nil,
              runningID == nil, awaitingExecution == nil, finished == nil,
              request.expiresAt > Date.now.timeIntervalSince1970 * 1000 else {
            send(["type": "decision", "id": request.id, "accepted": false]); return
        }
        pending = request
        if automaticallyApprove {
            // Reuse the same foreground, expiry and single-task checks as manual approval.
            approve()
            return
        }
        sendStatus()
        presentApproval(request)
        expiryTask = Task { [weak self] in
            let remaining = max(0, request.expiresAt / 1000 - Date.now.timeIntervalSince1970)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, self?.pending?.id == request.id else { return }
            self?.decline()
        }
    }

    func decline() {
        guard let request = pending else { return }
        clearApproval()
        saveFinished(id: request.id, result: "rejected: 用户拒绝了任务") // l10n:keep protocol payload
        send(["type": "decision", "id": request.id, "accepted": false])
        sendFinished()
        sendStatus()
    }

    func approve() {
        guard let request = pending else { return }
        guard foreground, !PhoneAgent.shared.isRunning, request.expiresAt > Date.now.timeIntervalSince1970 * 1000 else { decline(); return }
        awaitingExecution = request.id
        UserDefaults.standard.set(request.id, forKey: "remote.activeID")
        clearApproval()
        send(["type": "decision", "id": request.id, "accepted": true])
        sendStatus()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.awaitingExecution == request.id else { return }
            self.awaitingExecution = nil
            self.saveFinished(id: request.id, result: "error: 网关确认超时，任务未启动") // l10n:keep protocol payload
            self.sendFinished(); self.sendStatus()
        }
    }

    private func execute(_ request: RemoteRequest) {
        guard awaitingExecution == request.id else { return }
        expiryTask?.cancel(); expiryTask = nil
        awaitingExecution = nil
        guard foreground, enabled, !PhoneAgent.shared.isRunning else {
            saveFinished(id: request.id, result: "error: 设备当前无法执行"); sendFinished(); return // l10n:keep protocol payload
        }
        runningID = request.id
        Task { [weak self] in
            let outcome = await PhoneAgent.shared.runAndWait(prompt: request.prompt)
            guard let self else { return }
            self.runningID = nil
            self.saveFinished(id: request.id, result: outcome)
            self.sendFinished(); self.sendStatus()
        }
    }

    private func saveFinished(id: String, result: String) {
        finished = (id, String(result.prefix(8000)))
        UserDefaults.standard.set(id, forKey: "remote.activeID")
        UserDefaults.standard.set(finished?.result, forKey: "remote.result")
    }

    private func agentStateChanged() {
        if PhoneAgent.shared.isRunning, pending != nil { decline() }
        sendStatus(); refreshConnection()
    }

    private func clearApproval() {
        expiryTask?.cancel(); expiryTask = nil
        pending = nil
        approvalController?.dismiss(animated: true)
        approvalController = nil
    }

    private func presentApproval(_ request: RemoteRequest) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { decline(); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = UIHostingController(rootView: RemoteApprovalView(gateway: self, request: request))
        controller.isModalInPresentation = true
        controller.modalPresentationStyle = .pageSheet
        approvalController = controller
        presenter.present(controller, animated: true)
    }
}

private struct RemoteApprovalView: View {
    @ObservedObject var gateway: RemoteGateway
    let request: RemoteRequest
    @ObservedObject private var language = LanguageStore.shared
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(t("%@ 请求使用这台 iPhone", request.agent), systemImage: "network")
                            .font(.headline)
                        Text(request.prompt).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        Text(t("仅在你同意后执行。此请求会自动过期。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding()
                }
                HStack(spacing: 16) {
                    Button(t("拒绝"), role: .cancel) { gateway.decline() }.buttonStyle(.bordered)
                    Button(t("同意并执行")) { gateway.approve() }.buttonStyle(.borderedProminent)
                }.padding(.bottom)
            }
            .navigationTitle(t("远程任务确认"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

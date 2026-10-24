//
//  LLMSettings.swift
//  iPhoneUse
//
//  Which OpenAI-compatible endpoint the agent talks to. Provider/model picking is
//  modeled on esp32-iphone-agent (https://github.com/onehumanbeing/esp32-iphone-agent, MIT).
//

import Foundation
import Security

enum LLMProvider: String, CaseIterable, Identifiable {
    case openRouter, custom
    var id: String { rawValue }
    var title: String { self == .openRouter ? "OpenRouter" : "Custom URL" }
}

/// What one agent run needs, read once on the main actor.
struct LLMConfig: Sendable {
    var chatURL: URL
    var apiKey: String
    var model: String
    var maxSteps: Int
    var systemPrompt: String
}

@MainActor
final class LLMSettings: ObservableObject {
    static let shared = LLMSettings()
    static let openRouterURL = "https://openrouter.ai/api/v1"
    static let defaultModel = "anthropic/claude-sonnet-5.5"
    /// Fast OpenRouter transcription models, first is the default.
    static let voiceModels = [
        "openai/whisper-large-v3-turbo",
        "nvidia/parakeet-tdt-0.6b-v3",
        "openai/gpt-4o-mini-transcribe",
        "mistralai/voxtral-mini-transcribe",
        "elevenlabs/scribe-v2",
    ]
    static let voiceLanguages = ["en", "fr", "es", "de", "it", "pt", "nl", "ja", "zh", "ko", "hi", "ar", "ru"]
    static let defaultSystemPrompt = """
    你代替机主操作这台 iPhone。每一步你都会拿到一张新的截图，并且必须调用恰好一个工具。\
    坐标是这张截图里的像素（原点在左上角）。能直接 open_app 就别去桌面上找图标。\
    要打字时先点一下输入框把键盘调起来，再调用 type（只支持 ASCII；"\\n" 表示回车）。\
    动手之前，先用一句话说明你的判断。如果遇到只有机主才能提供的信息或选择，\
    调用 ask_user_question，不要自己猜。任务完成、或确认做不到时，调用 done。

    done 的 summary 会原样显示给机主，且按 Markdown 渲染，所以你可以用：\
    标题（# / ##）、无序列表（- ）、有序列表（1. ）、**粗体**、`行内代码`、\
    三反引号代码块、引用（>）和表格。写 summary 时先说结论，再列关键步骤，别长篇大论；\
    除非是需要打到手机上的字面内容，用中文写。
    """

    /// The English prompt shipped before the app rendered Markdown. Kept only so an untouched
    /// stored copy can be migrated to `defaultSystemPrompt` once.
    static let legacyDefaultSystemPrompt = """
    You operate an iPhone on behalf of its owner. Every step you get a fresh screenshot and \
    must call exactly one tool. Coordinates are pixels in that screenshot (origin top-left). \
    Prefer open_app over hunting for icons. To type, first tap the text field so the keyboard \
    is up, then call type (ASCII only; "\\n" presses return). Before acting, write one short \
    sentence of reasoning. If you need information or a choice only the owner can give, call \
    ask_user_question instead of guessing. Call done when the task is complete or impossible, with a summary.
    """

    private let defaults = UserDefaults.standard

    @Published var provider: LLMProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: "llmProvider")
            models = []
            apiKey = Keychain.get(keychainAccount) ?? "" // each provider keeps its own key
        }
    }
    @Published var customURL: String { didSet { defaults.set(customURL, forKey: "llmCustomURL") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "agentModelID") } }
    @Published var maxSteps: Int { didSet { defaults.set(maxSteps, forKey: "agentMaxSteps") } }
    @Published var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "agentSystemPrompt") } }
    @Published var apiKey: String { didSet { Keychain.set(apiKey, for: keychainAccount) } }
    @Published var voiceModel: String { didSet { defaults.set(voiceModel, forKey: "voiceModel") } }
    /// ISO-639-1 code; empty means auto-detect.
    @Published var voiceLanguage: String { didSet { defaults.set(voiceLanguage, forKey: "voiceLanguage") } }

    @Published private(set) var models: [String] = []
    @Published private(set) var loadingModels = false
    @Published private(set) var modelsError: String?

    private var keychainAccount: String { "apiKey.\(provider.rawValue)" }

    private init() {
        let provider = LLMProvider(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .openRouter
        self.provider = provider
        customURL = defaults.string(forKey: "llmCustomURL") ?? ""
        model = defaults.string(forKey: "agentModelID") ?? Self.defaultModel
        maxSteps = defaults.object(forKey: "agentMaxSteps") as? Int ?? 40
        let storedPrompt = defaults.string(forKey: "agentSystemPrompt") ?? Self.defaultSystemPrompt
        if storedPrompt == Self.legacyDefaultSystemPrompt {
            // An untouched copy of the old English prompt: swap it for the Chinese one.
            systemPrompt = Self.defaultSystemPrompt
            defaults.set(Self.defaultSystemPrompt, forKey: "agentSystemPrompt")
        } else {
            systemPrompt = storedPrompt
        }
        apiKey = Keychain.get("apiKey.\(provider.rawValue)") ?? ""
        voiceModel = defaults.string(forKey: "voiceModel") ?? Self.voiceModels[0]
        voiceLanguage = defaults.string(forKey: "voiceLanguage") ?? ""
    }

    var baseURL: String {
        let raw = provider == .openRouter ? Self.openRouterURL : customURL
        return raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
    }

    /// nil when the agent can run; otherwise what to fix in Settings.
    var problem: String? {
        if URL(string: baseURL)?.host == nil { return "Set a base URL in Settings." }
        if provider == .openRouter && apiKey.isEmpty { return "Add an OpenRouter API key in Settings." }
        if model.trimmingCharacters(in: .whitespaces).isEmpty { return "Pick a model in Settings." }
        return nil
    }

    /// Voice uses OpenRouter's transcription endpoint, so it needs the OpenRouter provider.
    var voiceAvailable: Bool { provider == .openRouter && !apiKey.isEmpty }

    var config: LLMConfig? {
        guard problem == nil, let url = URL(string: baseURL + "/chat/completions") else { return nil }
        return LLMConfig(chatURL: url, apiKey: apiKey, model: model.trimmingCharacters(in: .whitespaces),
                         maxSteps: max(1, maxSteps), systemPrompt: systemPrompt)
    }

    /// Checks the key against the endpoint. OpenRouter's /key rejects bad keys; /models is public there.
    func testConnection() async -> (text: String, isError: Bool) {
        let path = provider == .openRouter ? "/key" : "/models"
        guard let url = URL(string: baseURL + path), url.host != nil else { return ("Set a base URL first.", true) }
        var request = URLRequest(url: url)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return ("Failed: HTTP \(status).", true) }
            // OpenRouter's /key: limit_remaining is null when the key has no spending limit.
            let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
            if let remaining = key?["limit_remaining"] as? Double {
                return (String(format: "Connected. $%.2f left on this key.", remaining), false)
            }
            if let usage = key?["usage"] as? Double {
                return (String(format: "Connected. $%.2f used, no limit on this key.", usage), false)
            }
            return ("Connected.", false)
        } catch {
            return ("Failed: \(error.localizedDescription)", true)
        }
    }

    func loadModels() async {
        guard let url = URL(string: baseURL + "/models"), url.host != nil else { return }
        loadingModels = true
        defer { loadingModels = false }
        var request = URLRequest(url: url)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let list = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
            models = list.compactMap { $0["id"] as? String }.sorted()
            modelsError = models.isEmpty ? "The endpoint lists no models. Enter a model ID instead." : nil
        } catch {
            models = []
            modelsError = error.localizedDescription
        }
    }
}

/// Generic-password items, this device only.
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "blog.eliot.iphoneuse",
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

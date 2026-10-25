//
//  Localization.swift
//  iPhoneUse
//
//  In-app language switching. The Simplified Chinese copy is both the source text and the
//  lookup key, so the default language needs no table at all and a missing English entry
//  falls back to readable Chinese instead of a raw key. Everything the owner can read follows
//  the switch; the agent's system prompt is deliberately exempt (see LLMSettings).
//

import Foundation
import SwiftUI

/// The two languages the app ships. Raw values double as the stored `UserDefaults` value and
/// as the payload the Live Activity receives (an extension cannot read the app's defaults).
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// Written in the language itself so the choice stays readable from either side.
    var title: String { self == .chinese ? "中文" : "English" }

    /// Locale for system-provided names (voice languages, dates) so they match the UI language.
    var locale: Locale { Locale(identifier: rawValue) }
}

/// Lookup namespace. `current` is the app-wide setting, guarded by the main thread in practice:
/// views read it on the main actor and only `LanguageStore` writes it.
enum L10n {
    static let defaultsKey = "appLanguage"

    /// Lazily read once from disk so a cold start renders in the stored language even if no view
    /// touches `LanguageStore` first; `LanguageStore.selected` keeps it in sync afterwards.
    nonisolated(unsafe) static var current: AppLanguage = {
        let stored = UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:))
        return stored ?? .chinese
    }()

    /// Simplified Chinese is the source text, so it has no table and returns the key as-is.
    static func translate(_ key: String, language: AppLanguage? = nil) -> String {
        guard (language ?? current) == .english else { return key }
        return english[key] ?? key
    }

    /// One table per area so translations can be added without touching a shared file.
    static let english: [String: String] = {
        [L10nAgentView.table, L10nAgentCore.table, L10nDevice.table, L10nSettings.table, L10nWidget.table]
            .reduce(into: [String: String]()) { merged, table in
                merged.merge(table) { existing, _ in existing }
            }
    }()
}

/// The one lookup every user-facing string goes through. The key is the Chinese source text and
/// must be a plain literal (no interpolation); values are passed as arguments instead, and every
/// placeholder is `%@` (turn numbers into strings at the call site so formatting stays explicit).
func t(_ key: String, _ arguments: CVarArg...) -> String {
    let text = L10n.translate(key)
    guard !arguments.isEmpty else { return text }
    return String(format: text, arguments: arguments)
}

/// Explicit-language lookup for code that renders in another process — the Live Activity gets
/// the chosen language through its `ContentState` because extensions share no defaults.
func t(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
    let text = L10n.translate(key, language: language)
    guard !arguments.isEmpty else { return text }
    return String(format: text, arguments: arguments)
}

/// Observable holder so flipping the language redraws every view that shows copy. Each view that
/// calls `t(...)` keeps an observer alive with `@ObservedObject private var language = LanguageStore.shared`.
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            L10n.current = selected
            UserDefaults.standard.set(selected.rawValue, forKey: L10n.defaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: L10n.defaultsKey).flatMap(AppLanguage.init(rawValue:))
        let initial = stored ?? .chinese
        selected = initial
        L10n.current = initial
    }
}

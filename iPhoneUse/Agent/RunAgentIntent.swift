import AppIntents

// Shortcuts / Siri entry point: same as typing the prompt and tapping Run.
// Opens the app because starting a Live Activity and the tunnel need the foreground.
struct RunAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Agent"
    static let description = IntentDescription("Let the agent control this iPhone to do a task.")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt", requestValueDialog: "What should I do?")
    var prompt: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Wait for the run to end so the next action can read the result out loud.
        let outcome = await PhoneAgent.shared.runAndWait(prompt: prompt)
        return .result(value: Self.readable(outcome))
    }

    nonisolated static func readable(_ outcome: String) -> String {
        outcome.hasPrefix("done: ") ? String(outcome.dropFirst(6)) : outcome
    }
}

/// Read the last run's result without starting a new one.
struct LastAgentResultIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Agent Result"
    static let description = IntentDescription("Read the result of the last run.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: PhoneAgent.lastResult)
    }
}

struct AgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunAgentIntent(),
            phrases: [
                "运行 \(.applicationName) Agent", // l10n:keep Siri phrase follows the system language, not the in-app switch
                "问问 \(.applicationName)",
            ],
            shortTitle: "Run Agent",
            systemImageName: "sparkles"
        )
    }
}

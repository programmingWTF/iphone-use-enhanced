import ActivityKit
import Foundation

// Shared by the app (starts/updates the activity) and AgentWidget (renders it).
struct AgentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var step: Int
        var line: String
        var running: Bool
        /// Language code the widget renders its own labels in. The app sends the language it is
        /// currently showing; without an app group the widget cannot read the in-app setting.
        var language: String = AppLanguage.chinese.rawValue

        init(step: Int, line: String, running: Bool, language: String = AppLanguage.chinese.rawValue) {
            self.step = step
            self.line = line
            self.running = running
            self.language = language
        }

        /// The widget may have to decode a state persisted by a build without `language`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            step = try container.decode(Int.self, forKey: .step)
            line = try container.decode(String.self, forKey: .line)
            running = try container.decode(Bool.self, forKey: .running)
            language = try container.decodeIfPresent(String.self, forKey: .language) ?? AppLanguage.chinese.rawValue
        }

        private enum CodingKeys: String, CodingKey {
            case step, line, running, language
        }
    }

    var prompt: String
    var startedAt: Date
}

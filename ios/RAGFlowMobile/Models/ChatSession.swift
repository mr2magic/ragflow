import Foundation

struct ChatSession: Identifiable, Hashable {
    var id: String
    var kbId: String
    var name: String
    var createdAt: Date
    /// Per-chat model override (e.g. "claude-opus-4-6"). Nil = use provider default.
    var modelOverride: String?
    /// Per-chat temperature (0.0–2.0). Nil = use provider default.
    var temperature: Double?
    /// Per-chat Top-P (0.0–1.0). Nil = use provider default.
    var topP: Double?
    /// Extra instructions appended to the system prompt for this chat only.
    var systemPrompt: String?
    /// How many recent messages to include in the LLM context window. Nil = unlimited.
    var historyWindow: Int?
}

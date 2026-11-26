import Foundation

enum Agent: String, CaseIterable {
    case claude = "Claude Code", codex = "Codex", grok = "Grok Build", terminal = "Terminal screen"

    var directory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude/projects")
        case .codex: return home.appendingPathComponent(".codex/sessions")
        case .grok: return home.appendingPathComponent(".grok/sessions")
        case .terminal: return home
        }
    }

    func latestFile() -> URL? {
        guard self != .terminal,
              let files = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var latest: (URL, Date)?
        for case let url as URL in files {
            guard url.pathExtension == "jsonl", !url.path.contains("/subagents/"),
                  self != .grok || url.lastPathComponent == "updates.jsonl" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date > (latest?.1 ?? .distantPast) { latest = (url, date) }
        }
        return latest?.0
    }
}

struct Reply: Equatable {
    var id: String
    var text: String
}

enum Conversation {
    static func latest(in data: String, agent: Agent, assistantOnly: Bool) -> Reply? {
        var latest: Reply?
        var grokText = ""
        var grokID = ""
        for (index, line) in data.split(separator: "\n").enumerated() {
            guard let bytes = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
            if agent == .grok {
                guard let params = record["params"] as? [String: Any],
                      let update = params["update"] as? [String: Any],
                      let kind = update["sessionUpdate"] as? String else { continue }
                if kind == "user_message_chunk" || kind == "turn_completed" { grokText = ""; grokID = "" }
                guard kind == "agent_message_chunk" || (!assistantOnly && kind == "user_message_chunk"),
                      let content = update["content"] as? [String: Any], content["type"] as? String == "text",
                      let text = content["text"] as? String else { continue }
                if kind == "agent_message_chunk" {
                    if grokID.isEmpty { grokID = "\(record["timestamp_us"] ?? record["timestamp"] ?? index)" }
                    grokText += text
                    latest = Reply(id: grokID, text: grokText)
                } else { latest = Reply(id: "user-\(index)", text: text) }
                continue
            }
            let type = record["type"] as? String
            let message: [String: Any]
            if agent == .claude, type == "assistant" || type == "user",
               let value = record["message"] as? [String: Any] { message = value }
            else if agent == .codex, type == "response_item",
                    let value = record["payload"] as? [String: Any], value["type"] as? String == "message" { message = value }
            else { continue }
            let role = message["role"] as? String
            guard role == "assistant" || (!assistantOnly && role == "user") else { continue }
            var text = ""
            if let blocks = message["content"] as? [[String: Any]] {
                text = blocks.compactMap { block -> String? in
                    guard let kind = block["type"] as? String,
                          ["text", "output_text", "input_text"].contains(kind) else { return nil }
                    return block["text"] as? String
                }.joined(separator: "\n")
            } else if let value = message["content"] as? String { text = value }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let id = record["uuid"] as? String ?? message["id"] as? String ?? "\(index)"
            latest = Reply(id: id, text: text)
        }
        return latest
    }

    static func read(_ url: URL, agent: Agent, assistantOnly: Bool) throws -> Reply? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // shortcut: only the last 8 MiB are parsed; use incremental indexing for unusually large replies.
        let start = size > 8 * 1024 * 1024 ? size - 8 * 1024 * 1024 : 0
        try handle.seek(toOffset: start)
        let bytes = try handle.readToEnd() ?? Data()
        var text = String(decoding: bytes, as: UTF8.self)
        if start > 0 { text = text.components(separatedBy: "\n").dropFirst().joined(separator: "\n") }
        if !text.hasSuffix("\n") { text = text.components(separatedBy: "\n").dropLast().joined(separator: "\n") }
        return latest(in: text, agent: agent, assistantOnly: assistantOnly)
    }
}

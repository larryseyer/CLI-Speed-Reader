import Foundation

struct Reading {
    let text: String
    let ranges: [Range<String.Index>]

    init(_ text: String) {
        self.text = text
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        ranges = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }

    var words: [String] { ranges.map { String(text[$0]) } }

    func word(atUTF16Offset offset: Int) -> Int {
        ranges.firstIndex { NSRange($0, in: text).upperBound > offset } ?? max(0, ranges.count - 1)
    }

    // A length-based focal-letter heuristic; this is not Spritz's proprietary algorithm.
    static func focalIndex(_ word: String) -> Int {
        let letters = Array(word)
        let indices = letters.indices.filter { letters[$0].isLetter || letters[$0].isNumber }
        guard !indices.isEmpty else { return 0 }
        let slot: Int
        switch indices.count {
        case 1: slot = 0
        case 2...5: slot = 1
        case 6...9: slot = 2
        case 10...13: slot = 3
        default: slot = 4
        }
        return indices[min(slot, indices.count - 1)]
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func newText(after previous: String, in current: String) -> String {
        if current == previous { return "" }
        if current.hasPrefix(previous) {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Match whole lines when Terminal scrolls old text off the screen.
        let old = previous.components(separatedBy: "\n")
        let new = current.components(separatedBy: "\n")
        for count in stride(from: min(old.count, new.count), through: 1, by: -1) {
            if old.suffix(count).elementsEqual(new.prefix(count)) {
                return new.dropFirst(count).joined(separator: "\n")
            }
        }
        // shortcut: full-screen redraws have no reliable reply boundary; use clipboard for exact replies.
        return current
    }
}

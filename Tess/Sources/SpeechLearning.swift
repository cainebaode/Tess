import Foundation

// A result's provenance is frozen before delivery; editable output is never the baseline.
struct SpeechBaseline: Codable, Equatable, Sendable {
    let sessionID: UUID
    let original: String
    let delivered: String
    let mode: String
    let textProcessed: Bool
    let applicationID: String?
    let applicationName: String?
    let model: String
    let promptSnapshotID: UUID
    let promptVersion: Int

    var eligible: Bool { mode == "raw" && !textProcessed && original == delivered && !delivered.isEmpty }
}

enum SpeechEditSource: String, Codable, Sendable { case resultPage, submitted, inputField }

struct SpeechDifference: Equatable, Identifiable, Sendable {
    let id = UUID()
    let mistaken: String
    let spelling: String
    let range: NSRange
    var key: String { mistaken + "\u{0}" + spelling }
}

struct SpeechLearningReview: Sendable {
    let resultID: UUID
    let revision: Int
    let baseline: SpeechBaseline
    let edited: String
    let source: SpeechEditSource
    let createdAt: Date
    var differences: [SpeechDifference]
}

struct SpeechMemory: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let mistaken: String
    let spelling: String
    var note = ""
    let applicationID: String?
    let applicationName: String?
    var allApplications: Bool
    var enabled = true
    let confirmedAt: Date
    let source: SpeechEditSource
    let resultID: UUID

    var isValid: Bool {
        !mistaken.isEmpty && !spelling.isEmpty && mistaken != spelling
            && mistaken.count <= 32 && spelling.count <= 32 && note.count <= 160
            && (allApplications || applicationID?.isEmpty == false)
    }
    func applies(to app: String?) -> Bool { allApplications || (app != nil && app == applicationID) }
    func sameScope(as other: SpeechMemory) -> Bool {
        allApplications == other.allApplications && (allApplications || applicationID == other.applicationID)
    }
    func overlaps(_ other: SpeechMemory) -> Bool {
        allApplications || other.allApplications || applicationID == other.applicationID
    }
}

enum SpeechLearning {
    static let fileName = "speech-learning.json"
    static let limit = 50

    static func conflicts(in memories: [SpeechMemory]) -> Set<UUID> {
        let active = memories.filter { $0.enabled && $0.isValid }
        var conflicts: Set<UUID> = []
        for (index, first) in active.enumerated() {
            for second in active.dropFirst(index + 1) where first.mistaken.lowercased() == second.mistaken.lowercased()
                && first.spelling != second.spelling && first.overlaps(second) {
                conflicts.insert(first.id); conflicts.insert(second.id)
            }
        }
        return conflicts
    }

    static func alreadyKnown(_ difference: SpeechDifference, applicationID: String?, memories: [SpeechMemory]) -> Bool {
        // Disabled/conflicting memories are managed explicitly, never silently re-enabled by a new edit.
        memories.contains { $0.mistaken == difference.mistaken && $0.spelling == difference.spelling
            && $0.applies(to: applicationID) }
    }
}

struct SpeechPromptSnapshot: Sendable {
    let id = UUID()
    static let version = 1
    let context: String?
    let memoryIDs: [UUID]
    let omittedCount: Int

    static func make(vocabulary: SpeechVocabulary, learningEnabled: Bool, memories: [SpeechMemory],
                     applicationID: String?, supportsHints: Bool) -> SpeechPromptSnapshot {
        guard supportsHints else { return .init(context: nil, memoryIDs: [], omittedCount: 0) }
        var lines = vocabulary.activeScene.isEmpty ? [] : ["背景：" + vocabulary.activeScene]
        var seen: Set<String> = []
        var ids: [UUID] = []
        var omitted = 0
        func append(_ spelling: String, _ note: String) -> Bool {
            let key = spelling.precomposedStringWithCanonicalMapping.lowercased()
            guard !seen.contains(key) else { return false }
            let line = spelling + (note.isEmpty ? "" : "（" + note + "）")
            guard seen.count < SpeechVocabulary.wordLimit,
                  (lines + [line]).joined(separator: "\n").count <= SpeechVocabulary.contextLimit else {
                omitted += 1; return false
            }
            seen.insert(key); lines.append(line); return true
        }
        for word in vocabulary.activeWords { _ = append(word.spelling, word.meaning) }
        let conflicts = SpeechLearning.conflicts(in: memories)
        if learningEnabled {
            let applicable = memories.filter { $0.enabled && $0.isValid && $0.applies(to: applicationID) }
                .sorted { first, second in
                    if first.allApplications != second.allApplications { return !first.allApplications }
                    return first.confirmedAt > second.confirmedAt
                }
            for memory in applicable {
                if conflicts.contains(memory.id) { omitted += 1; continue }
                if append(memory.spelling, memory.note) { ids.append(memory.id) }
            }
        }
        return .init(context: lines.isEmpty ? nil : lines.joined(separator: "\n"), memoryIDs: ids, omittedCount: omitted)
    }
}

// Character (grapheme) diff, with conservative intent/ambiguity gates. No replacement rules.
enum SpeechDiff {
    private struct Hunk { var before: Range<Int>; var after: Range<Int> }
    static func differences(from original: String, to edited: String) -> [SpeechDifference] {
        guard original != edited, !edited.isEmpty, original.count <= 8_000, edited.count <= 8_000,
              abs(original.count - edited.count) <= 96,
              protectedTokens(original) == protectedTokens(edited) else { return [] }
        let before = Array(original), after = Array(edited)
        guard let (removed, inserted) = boundedChanges(before, after) else { return [] }
        guard removed.count + inserted.count <= max(8, min(192, before.count * 3 / 5)) else { return [] }
        guard removed.map({ String(before[$0]) }).sorted() != inserted.map({ String(after[$0]) }).sorted() else { return [] }
        var hunks: [Hunk] = []
        var i = 0, j = 0
        while i < before.count || j < after.count {
            let startI = i, startJ = j
            while removed.contains(i) { i += 1 }
            while inserted.contains(j) { j += 1 }
            if startI != i || startJ != j {
                if let last = hunks.last, startI - last.before.upperBound <= 2,
                   startJ - last.after.upperBound <= 2 {
                    hunks[hunks.count - 1] = Hunk(before: last.before.lowerBound..<i, after: last.after.lowerBound..<j)
                } else { hunks.append(Hunk(before: startI..<i, after: startJ..<j)) }
            }
            if i < before.count && j < after.count { i += 1; j += 1 }
            else if i == startI && j == startJ { break }
        }
        guard !hunks.isEmpty, hunks.count <= 3 else { return [] }
        var result: [SpeechDifference] = []
        for var hunk in hunks {
            // Insertions/deletions and formatting aren't recognition evidence.
            guard !hunk.before.isEmpty, !hunk.after.isEmpty else { continue }
            while hunk.before.lowerBound > 0 && hunk.after.lowerBound > 0,
                  latin(before[hunk.before.lowerBound - 1]), latin(after[hunk.after.lowerBound - 1]),
                  latin(before[hunk.before.lowerBound]), latin(after[hunk.after.lowerBound]) {
                hunk.before = (hunk.before.lowerBound - 1)..<hunk.before.upperBound
                hunk.after = (hunk.after.lowerBound - 1)..<hunk.after.upperBound
            }
            while hunk.before.upperBound < before.count && hunk.after.upperBound < after.count,
                  latin(before[hunk.before.upperBound]), latin(after[hunk.after.upperBound]),
                  latin(before[hunk.before.upperBound - 1]), latin(after[hunk.after.upperBound - 1]) {
                hunk.before = hunk.before.lowerBound..<(hunk.before.upperBound + 1)
                hunk.after = hunk.after.lowerBound..<(hunk.after.upperBound + 1)
            }
            // Keep a short unchanged Chinese suffix: 云→语音 becomes 云输入→语音输入.
            if han(before[hunk.before.upperBound - 1]) && han(after[hunk.after.upperBound - 1]),
               min(hunk.before.count, hunk.after.count) <= 2 {
                for _ in 0..<2 {
                    guard hunk.before.upperBound < before.count, hunk.after.upperBound < after.count,
                          before[hunk.before.upperBound] == after[hunk.after.upperBound], han(before[hunk.before.upperBound]) else { break }
                    hunk.before = hunk.before.lowerBound..<(hunk.before.upperBound + 1)
                    hunk.after = hunk.after.lowerBound..<(hunk.after.upperBound + 1)
                }
            }
            let source = String(before[hunk.before]), replacement = String(after[hunk.after])
            guard source.count <= 32, replacement.count <= 32, meaningful(source) != meaningful(replacement),
                  !meaningful(source).isEmpty, !meaningful(replacement).isEmpty,
                  !source.contains("\n"), !replacement.contains("\n"),
                  occurrences(source, in: original) == 1, occurrences(replacement, in: edited) == 1 else { continue }
            let left = min(hunk.before.lowerBound, hunk.after.lowerBound)
            let right = min(before.count - hunk.before.upperBound, after.count - hunk.after.upperBound)
            guard left >= 2 || right >= 2 else { continue }
            let start = original.index(original.startIndex, offsetBy: hunk.before.lowerBound)
            let end = original.index(original.startIndex, offsetBy: hunk.before.upperBound)
            let range = NSRange(start..<end, in: original)
            guard result.allSatisfy({ NSIntersectionRange($0.range, range).length == 0 }) else { return [] }
            result.append(.init(mistaken: source, spelling: replacement, range: range))
        }
        // Reordering existing words isn't a new spelling to remember.
        return result.filter { !original.contains($0.spelling) && !edited.contains($0.mistaken) }
    }

    private static func latin(_ c: Character) -> Bool {
        c.unicodeScalars.first.map { CharacterSet.letters.contains($0) && !han(c) } == true
    }
    private static func han(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && c.unicodeScalars.first.map { (0x3400...0x9FFF).contains($0.value) } == true
    }
    private static func meaningful(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    private static func occurrences(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
    // Bounded Myers diff: large rewrites stop after 192 edits instead of allocating
    // a quadratic table or leaving unbounded background work after each keystroke.
    private static func boundedChanges(_ before: [Character], _ after: [Character]) -> (Set<Int>, Set<Int>)? {
        var frontier = [1: 0]
        var trace: [[Int: Int]] = []
        for distance in 0...192 {
            trace.append(frontier)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                var x = diagonal == -distance || (diagonal != distance && frontier[diagonal - 1, default: -1] < frontier[diagonal + 1, default: -1])
                    ? frontier[diagonal + 1, default: 0] : frontier[diagonal - 1, default: 0] + 1
                var y = x - diagonal
                while x < before.count && y < after.count && before[x] == after[y] { x += 1; y += 1 }
                frontier[diagonal] = x
                if x >= before.count && y >= after.count {
                    var removed: Set<Int> = [], inserted: Set<Int> = []
                    x = before.count; y = after.count
                    for d in stride(from: distance, through: 0, by: -1) {
                        let previous = trace[d], k = x - y
                        let previousK = k == -d || (k != d && previous[k - 1, default: -1] < previous[k + 1, default: -1]) ? k + 1 : k - 1
                        let previousX = previous[previousK, default: 0], previousY = previousX - previousK
                        while x > previousX && y > previousY { x -= 1; y -= 1 }
                        if d > 0 {
                            if x == previousX { y -= 1; inserted.insert(y) }
                            else { x -= 1; removed.insert(x) }
                        }
                    }
                    return (removed, inserted)
                }
            }
        }
        return nil
    }
    private static func protectedTokens(_ text: String) -> [String] {
        let pattern = #"(?:https?://|~/|\.\.?/|/|[A-Za-z]:\\)[^\s，。；;!！?？、]+|`[^`]+`|[A-Za-z0-9_]+(?:[._][A-Za-z0-9_]+)+|[a-z]+[A-Z][A-Za-z]*|\d+(?:[.,:/-]\d+)*|[零一二三四五六七八九十百千万两]+(?:点|时|分|秒|元|个|天|周|月|年)|(?:周|星期)[一二三四五六日天]|今天|明天|昨天|后天|不|没|无|别|未|否|不要|取消|必须|可以|不能|\b(?:not|no|never|don't|can't|won't|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
    }
}

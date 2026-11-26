import Foundation

enum NCCodeToolError: LocalizedError {
    case invalidValue
    case unsupported(Int)
    case feedModeUnknown
    case spindleModeUnknown
    case unitUnknown
    case afterEnd
    case noMatches

    var errorDescription: String? {
        switch self {
        case .invalidValue: return L.t("nc.tools.invalidValue")
        case .unsupported(let line): return L.t("nc.tools.unsupported", line)
        case .feedModeUnknown: return L.t("nc.tools.feedModeUnknown")
        case .spindleModeUnknown: return L.t("nc.tools.spindleModeUnknown")
        case .unitUnknown: return L.t("nc.tools.unitUnknown")
        case .afterEnd: return L.t("nc.tools.afterEnd")
        case .noMatches: return L.t("nc.tools.noMatches")
        }
    }
}

enum NCCodeTools {
    enum Change: Sendable {
        case spindle(Double)
        case feed(Double)
        case feedPercent(Double)
    }

    private static let words = try! NSRegularExpression(
        pattern: #"([A-Z])\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))"#,
        options: [.caseInsensitive]
    )
    private static let comments = try! NSRegularExpression(pattern: #"\([^)]*\)|;.*$"#)

    private static func codeOnly(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        let matches = comments.matches(in: text, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
        }
        return mutable as String
    }

    private static func validate(_ code: String, line: Int, feedModeKnown: inout Bool) throws -> [NSTextCheckingResult] {
        if code.contains("#") || code.contains("=") || code.contains("[") || code.contains("]") {
            throw NCCodeToolError.unsupported(line)
        }
        let source = code as NSString
        let matches = words.matches(in: code, range: NSRange(location: 0, length: source.length))
        let remainder = NSMutableString(string: code)
        for match in matches.reversed() {
            remainder.replaceCharacters(in: match.range, with: "")
        }
        let ignored = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "%/"))
        guard (remainder as String).trimmingCharacters(in: ignored).isEmpty else {
            throw NCCodeToolError.unsupported(line)
        }
        for match in matches {
            let letter = source.substring(with: match.range(at: 1)).uppercased()
            guard let number = Double(source.substring(with: match.range(at: 2))), number.isFinite else {
                throw NCCodeToolError.unsupported(line)
            }
            if letter == "G" {
                let allowed: [Double] = [0, 1, 2, 3, 17, 18, 19, 20, 21, 28, 30, 40, 49, 53, 54, 55, 56, 57, 58, 59, 80, 90, 90.1, 91, 91.1, 94, 97]
                guard allowed.contains(number) else { throw NCCodeToolError.unsupported(line) }
                if number == 94 { feedModeKnown = true }
            }
            if letter == "M", ![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 30].contains(number) {
                throw NCCodeToolError.unsupported(line)
            }
            if !["G", "M", "X", "Y", "Z", "I", "J", "K", "R", "F", "S", "N", "O", "T", "D", "H", "P", "Q", "L"].contains(letter) {
                throw NCCodeToolError.unsupported(line)
            }
        }
        return matches
    }

    static func change(_ text: String, _ change: Change, assumeSpindleRPM: Bool = false) throws -> String {
        let isFeed: Bool
        let value: Double
        switch change {
        case .spindle(let number): isFeed = false; value = number
        case .feed(let number): isFeed = true; value = number
        case .feedPercent(let number): isFeed = true; value = number
        }
        guard value.isFinite else { throw NCCodeToolError.invalidValue }
        switch change {
        case .feedPercent:
            guard value > -100 && value <= 10_000 else { throw NCCodeToolError.invalidValue }
        default:
            guard value > 0 && value <= 100_000_000 else { throw NCCodeToolError.invalidValue }
        }

        let lines = text.components(separatedBy: "\n")
        var feedModeKnown = false
        var spindleModeKnown = false
        var millimetersPerUnit: Double?
        var replacements: [(NSRange, String)] = []
        var offset = 0
        for (index, line) in lines.enumerated() {
            let code = codeOnly(line)
            let matches = try validate(code, line: index + 1, feedModeKnown: &feedModeKnown)
            let source = code as NSString
            for match in matches where source.substring(with: match.range(at: 1)).uppercased() == "G" {
                let number = Double(source.substring(with: match.range(at: 2)))
                if number == 20 { millimetersPerUnit = 25.4 }
                if number == 21 { millimetersPerUnit = 1 }
                if number == 97 { spindleModeKnown = true }
            }
            for match in matches {
                let letter = source.substring(with: match.range(at: 1)).uppercased()
                guard letter == (isFeed ? "F" : "S") else { continue }
                if isFeed && !feedModeKnown { throw NCCodeToolError.feedModeUnknown }
                if !isFeed && !spindleModeKnown && !assumeSpindleRPM { throw NCCodeToolError.spindleModeUnknown }
                guard let old = Double(source.substring(with: match.range(at: 2))), old > 0 else {
                    throw NCCodeToolError.invalidValue
                }
                let newValue: Double
                switch change {
                case .spindle: newValue = value
                case .feed:
                    guard let millimetersPerUnit else { throw NCCodeToolError.unitUnknown }
                    newValue = value / millimetersPerUnit
                case .feedPercent: newValue = old * (1 + value / 100)
                }
                guard newValue.isFinite && newValue > 0 && newValue <= 100_000_000 else {
                    throw NCCodeToolError.invalidValue
                }
                let formatted = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), newValue)
                    .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
                guard let rounded = Double(formatted), rounded > 0 else { throw NCCodeToolError.invalidValue }
                replacements.append((NSRange(location: offset + match.range(at: 2).location, length: match.range(at: 2).length), formatted))
            }
            offset += (line as NSString).length + 1
        }
        guard !replacements.isEmpty else { throw NCCodeToolError.noMatches }
        let result = NSMutableString(string: text)
        for (range, replacement) in replacements.reversed() {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    static func changeCoolant(_ text: String, line selectedLine: Int, code: Int, insert: Bool) throws -> String {
        guard [7, 8, 9].contains(code) else { throw NCCodeToolError.invalidValue }
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(selectedLine) else { throw NCCodeToolError.invalidValue }
        var feedModeKnown = false
        for (index, line) in lines.enumerated() {
            let codeText = codeOnly(line)
            let matches = try validate(codeText, line: index + 1, feedModeKnown: &feedModeKnown)
            if insert && index <= selectedLine {
                let source = codeText as NSString
                if codeText.trimmingCharacters(in: .whitespacesAndNewlines) == "%" && index > 0 {
                    throw NCCodeToolError.afterEnd
                }
                if matches.contains(where: {
                    source.substring(with: $0.range(at: 1)).uppercased() == "M"
                        && [2.0, 30.0].contains(Double(source.substring(with: $0.range(at: 2))) ?? -1)
                }) { throw NCCodeToolError.afterEnd }
            }
        }
        if insert {
            let ending = text.contains("\r\n") ? "\r" : ""
            let follows = selectedLine + 1 < lines.count
            if !follows { lines[selectedLine] += ending }
            lines.insert("M\(code)\(follows ? ending : "")", at: selectedLine + 1)
        } else {
            let original = lines[selectedLine]
            let masked = codeOnly(original) as NSString
            let matches = words.matches(in: masked as String, range: NSRange(location: 0, length: masked.length))
            let result = NSMutableString(string: original)
            let targets = matches.filter {
                masked.substring(with: $0.range(at: 1)).uppercased() == "M"
                    && Double(masked.substring(with: $0.range(at: 2))) == Double(code)
            }
            guard !targets.isEmpty else { throw NCCodeToolError.noMatches }
            for match in targets.reversed() { result.deleteCharacters(in: match.range) }
            lines[selectedLine] = result as String
        }
        return lines.joined(separator: "\n")
    }
}

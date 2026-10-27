//
//  SelectionPatternMatcher.swift
//  GMS_Commander
//
//  Etkin paneldeki öğe adlarını joker (glob) veya düzenli ifadeyle
//  eşleştiren yardımcı. Dosya sistemine dokunmaz.
//

import Foundation

/// Desene göre seçim eşleştirmesi.
enum SelectionPatternMatcher {
    /// Desen geçerli bir düzenli ifade mi?
    /// - Parameter pattern: Denetlenecek desen.
    /// - Returns: Desen derlenebiliyorsa `true`.
    static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// Bir adın desene uyup uymadığını döndürür.
    /// Joker (`*`, `?`) içeren desenler tam adla, diğerleri büyük/küçük harf
    /// ve aksan duyarsız alt dize olarak eşleştirilir.
    /// - Parameters:
    ///   - name: Dosya veya klasör adı.
    ///   - pattern: Joker, alt dize veya düzenli ifade.
    ///   - useRegex: `true` ise desen düzenli ifade olarak yorumlanır.
    /// - Returns: Ad desene uyuyorsa `true`.
    static func matches(name: String, pattern: String, useRegex: Bool) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if useRegex {
            guard let regex = try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            return regex.firstMatch(in: name, range: range) != nil
        }

        if trimmed.contains("*") || trimmed.contains("?") {
            return FileSearchService.matchesAnyPattern(name, patterns: [trimmed])
        }

        let needle = FileSearchService.normalize(trimmed)
        return FileSearchService.normalize(name).contains(needle)
    }
}

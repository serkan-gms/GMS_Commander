//
//  FileSearchService.swift
//  GMS_Commander
//
//  Alt klasörlerde dosya adına göre arama yapan servis.
//  Arama sonuçları üst sınırla sınırlandırılır ve kullanıcı iptal edebilir.
//

import Foundation

/// Arama işleminin sonucu.
struct SearchOutcome: Sendable {
    /// Bulunan öğeler.
    let items: [FileItem]

    /// Arama kullanıcı tarafından iptal edildi mi?
    let wasCancelled: Bool

    /// Sonuç üst sınırına ulaşıldı mı?
    let reachedLimit: Bool

    /// İzin hatası nedeniyle atlanan klasör/dosya sayısı.
    var skippedCount: Int = 0
}

/// Alt görevlerde çalışan aramayı iptal etmek için iş parçacığı güvenli bayrak.
final class SearchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    /// Aramayı iptal edilmiş olarak işaretler.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Arama iptal edildi mi?
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

// MARK: - Arama ölçütleri

/// Gelişmiş arama ölçütleri. Boş alanlar o ölçütü devre dışı bırakır.
struct SearchCriteria: Sendable, Equatable {
    /// Dosya adında aranacak metin. `*` ve `?` joker olarak kullanılabilir.
    var nameQuery = ""
    /// Ad ve içerik aramasında düzenli ifade kullanılsın mı?
    var useRegex = false
    /// Yalnızca bu uzantılar (nokta olmadan, küçük harf).
    var extensions: [String] = []
    /// En küçük dosya boyutu (bayt).
    var minimumSize: Int64?
    /// En büyük dosya boyutu (bayt).
    var maximumSize: Int64?
    /// Bu tarihten sonra değiştirilmiş.
    var modifiedAfter: Date?
    /// Bu tarihten önce değiştirilmiş.
    var modifiedBefore: Date?
    /// Dosya içeriğinde aranacak metin.
    var contentQuery = ""
    /// Dosyalar sonuçlara dahil edilsin mi?
    var includeFiles = true
    /// Klasörler sonuçlara dahil edilsin mi?
    var includeFolders = true
    /// Gizli öğeler de taransın mı?
    var includeHidden = false
    /// Alt klasörlere inilsin mi?
    var recursive = true
    /// Ada göre hariç tutma desenleri (`*` ve `?` desteklenir).
    var excludePatterns: [String] = []
    /// İçerik aramasında okunacak en büyük dosya boyutu.
    var maximumContentFileSize: Int64 = 5 * 1024 * 1024
    /// İçerik aramasında büyük dosyalar atlanırken sayılsın mı?
    var skipLargeContentFiles = true

    /// Hiçbir ölçüt girilmemiş mi?
    var isEmpty: Bool {
        nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && extensions.isEmpty && minimumSize == nil && maximumSize == nil
            && modifiedAfter == nil && modifiedBefore == nil
            && contentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Dosya adına göre özyinelemeli arama yapan servis.
struct FileSearchService: Sendable {
    /// Varsayılan sonuç üst sınırı.
    static let defaultLimit = 2000

    /// Bir klasör altında arama yapar.
    /// - Parameters:
    ///   - root: Aramanın başlayacağı klasör.
    ///   - query: Aranan metin (büyük/küçük harf ve Türkçe karakter duyarsız).
    ///   - includeHidden: Gizli öğeler de aransın mı?
    ///   - limit: En fazla sonuç sayısı.
    /// - Returns: Arama sonucu.
    func search(
        root: URL,
        query: String,
        includeHidden: Bool,
        limit: Int = FileSearchService.defaultLimit
    ) async -> SearchOutcome {
        await Task.detached(priority: .userInitiated) {
            Self.searchSync(root: root, query: query, includeHidden: includeHidden, limit: limit)
        }.value
    }

    /// Gelişmiş ölçütlerle arama yapar.
    /// - Parameters:
    ///   - root: Başlangıç klasörü.
    ///   - criteria: Ad, boyut, tarih, uzantı ve içerik ölçütleri.
    ///   - limit: En fazla sonuç sayısı.
    /// - Returns: Arama sonucu.
    func search(
        root: URL,
        criteria: SearchCriteria,
        limit: Int = FileSearchService.defaultLimit,
        cancellation: SearchCancellation? = nil
    ) async -> SearchOutcome {
        await Task.detached(priority: .userInitiated) {
            Self.searchSync(
                root: root,
                criteria: criteria,
                limit: limit,
                cancellation: cancellation
            )
        }.value
    }

    /// Gelişmiş aramanın eşzamanlı çekirdeği.
    static func searchSync(
        root: URL,
        criteria: SearchCriteria,
        limit: Int = FileSearchService.defaultLimit,
        cancellation: SearchCancellation? = nil
    ) -> SearchOutcome {
        guard !criteria.isEmpty else {
            return SearchOutcome(items: [], wasCancelled: false, reachedLimit: false)
        }

        let fileManager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !criteria.includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        var skipped = 0
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileManagerService.resourceKeys),
            options: options,
            errorHandler: { _, _ in
                skipped += 1
                return true
            }
        ) else {
            return SearchOutcome(items: [], wasCancelled: false, reachedLimit: false, skippedCount: 1)
        }

        let nameRegex = try? NSRegularExpression(
            pattern: criteria.nameQuery,
            options: [.caseInsensitive]
        )
        let contentRegex = try? NSRegularExpression(
            pattern: criteria.contentQuery,
            options: [.caseInsensitive]
        )
        let namePatternIsPlain = !criteria.nameQuery.contains("*") && !criteria.nameQuery.contains("?")
        let normalizedName = normalize(criteria.nameQuery)
        let normalizedContent = normalize(criteria.contentQuery)
        let contentActive = !criteria.contentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let extensions = Set(criteria.extensions.map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        })

        let rootPath = root.standardizedFileURL.path
        var results: [FileItem] = []
        var reachedLimit = false

        for case let url as URL in enumerator {
            if Task.isCancelled || cancellation?.isCancelled == true {
                return SearchOutcome(items: [], wasCancelled: true, reachedLimit: false, skippedCount: skipped)
            }
            if results.count >= limit {
                reachedLimit = true
                enumerator.skipDescendants()
                break
            }

            let values = try? url.resourceValues(forKeys: Set(FileManagerService.resourceKeys))
            let isDirectory = values?.isDirectory ?? false

            // Hariç tutma desenleri: klasör eşleşirse altına inilmez.
            if matchesAnyPattern(url.lastPathComponent, patterns: criteria.excludePatterns) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Üst düzey sınırı
            let relativeForDepth = relativePath(of: url, rootPath: rootPath)
            if !criteria.recursive, relativeForDepth.contains("/") {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Uzantı, boyut ve içerik ölçütleri yalnızca dosyalara uygulanır;
            // bu ölçütlerden biri etkinken klasörler sonuçlara katılmaz.
            let hasFileOnlyCriteria = !extensions.isEmpty
                || criteria.minimumSize != nil || criteria.maximumSize != nil
                || contentActive
            if isDirectory {
                if !criteria.includeFolders || hasFileOnlyCriteria { continue }
            } else if !criteria.includeFiles {
                continue
            }

            // Uzantı
            if !isDirectory, !extensions.isEmpty {
                let ext = url.pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
            }

            // Boyut
            if !isDirectory {
                let size = Int64(values?.fileSize ?? 0)
                if let minimum = criteria.minimumSize, size < minimum { continue }
                if let maximum = criteria.maximumSize, size > maximum { continue }
            }

            // Tarih
            if let date = values?.contentModificationDate {
                if let after = criteria.modifiedAfter, date < after { continue }
                if let before = criteria.modifiedBefore, date > before { continue }
            } else if criteria.modifiedAfter != nil || criteria.modifiedBefore != nil {
                continue
            }

            // Ad
            let name = url.lastPathComponent
            if !criteria.nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let nameMatches: Bool
                if criteria.useRegex {
                    guard let nameRegex else { continue }
                    let range = NSRange(name.startIndex..<name.endIndex, in: name)
                    nameMatches = nameRegex.firstMatch(in: name, range: range) != nil
                } else if namePatternIsPlain {
                    nameMatches = normalize(name).contains(normalizedName)
                } else {
                    nameMatches = matchesAnyPattern(name, patterns: [criteria.nameQuery])
                }
                guard nameMatches else { continue }
            }

            // İçerik
            if contentActive, !isDirectory {
                let size = Int64(values?.fileSize ?? 0)
                if criteria.skipLargeContentFiles, size > criteria.maximumContentFileSize {
                    skipped += 1
                    continue
                }
                guard fileContains(
                    url: url,
                    query: normalizedContent,
                    regex: criteria.useRegex ? contentRegex : nil,
                    maximumBytes: criteria.maximumContentFileSize
                ) else { continue }
            }

            guard let item = FileItem.make(url: url, relativePath: relativeForDepth) else {
                continue
            }
            results.append(item)
        }

        results.sort { lhs, rhs in
            let lhsPath = lhs.relativePath ?? lhs.name
            let rhsPath = rhs.relativePath ?? rhs.name
            return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
        }

        return SearchOutcome(
            items: results,
            wasCancelled: Task.isCancelled || cancellation?.isCancelled == true,
            reachedLimit: reachedLimit,
            skippedCount: skipped
        )
    }

    /// Bir dosya adının joker desenlerinden birine uyup uymadığını denetler.
    static func matchesAnyPattern(_ name: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        return patterns.contains { pattern in
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: trimmed)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            return regex.firstMatch(in: name, range: range) != nil
        }
    }

    /// Dosya içeriğinde metin arar. İkili dosyalar sessizce atlanır.
    private static func fileContains(
        url: URL,
        query: String,
        regex: NSRegularExpression?,
        maximumBytes: Int64
    ) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Int(maximumBytes))) ?? Data()
        guard !data.isEmpty, !FileViewerService.isBinary(data) else { return false }

        let encoding: String.Encoding
        if let detected = ViewerEncoding.detect(from: data) {
            encoding = detected.stringEncoding
        } else if String(data: data, encoding: .utf8) != nil {
            encoding = .utf8
        } else {
            encoding = .isoLatin1
        }
        guard let text = String(data: data, encoding: encoding) else { return false }

        if let regex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, range: range) != nil
        }
        return normalize(text).contains(query)
    }

    /// Aramanın eşzamanlı çekirdeği (birim testlerinde doğrudan çağrılır).
    static func searchSync(
        root: URL,
        query: String,
        includeHidden: Bool,
        limit: Int = FileSearchService.defaultLimit
    ) -> SearchOutcome {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return SearchOutcome(items: [], wasCancelled: false, reachedLimit: false)
        }

        let fileManager = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(FileManagerService.resourceKeys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return SearchOutcome(items: [], wasCancelled: false, reachedLimit: false)
        }

        let rootPath = root.standardizedFileURL.path
        var results: [FileItem] = []
        var reachedLimit = false

        for case let url as URL in enumerator {
            if Task.isCancelled {
                return SearchOutcome(items: [], wasCancelled: true, reachedLimit: false)
            }
            if results.count >= limit {
                reachedLimit = true
                enumerator.skipDescendants()
                break
            }

            let name = url.lastPathComponent
            guard normalize(name).contains(normalizedQuery) else { continue }
            guard let item = FileItem.make(url: url, relativePath: relativePath(of: url, rootPath: rootPath)) else {
                continue
            }
            results.append(item)
        }

        results.sort { lhs, rhs in
            let lhsPath = lhs.relativePath ?? lhs.name
            let rhsPath = rhs.relativePath ?? rhs.name
            return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
        }

        return SearchOutcome(
            items: results,
            wasCancelled: Task.isCancelled,
            reachedLimit: reachedLimit
        )
    }

    /// Metni karşılaştırma için sadeleştirir (Türkçe I/İ farklarını da giderir).
    /// Türkçe yereline göre katlama "İ" harfini "ı" yaptığı için tarafsız yerel kullanılır;
    /// ardından noktasız "ı" harfi "i" ile eşitlenir. Böylece "isik" sorgusu "IŞIK"
    /// dosyasını, "istanbul" sorgusu "İSTANBUL" dosyasını bulur.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.replacingOccurrences(of: "ı", with: "i")
    }

    /// Kök klasöre göre göreli yolu üretir.
    private static func relativePath(of url: URL, rootPath: String) -> String {
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(fullPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}

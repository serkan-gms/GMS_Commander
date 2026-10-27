//
//  FileManagerService.swift
//  GMS_Commander
//
//  Dosya sistemi sorgularını ve temel işlemlerini (listeleme, adlandırma,
//  klasör oluşturma, çöp kutusuna taşıma) yürüten servis.
//  Ağır işler ana iş parçacığını bloke etmemek için `Task.detached` içinde çalışır.
//

import Foundation

/// Dosya sistemi işlemlerini sağlayan servis.
struct FileManagerService: Sendable {
    /// Listeleme sırasında okunacak kaynak değerleri.
    static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isReadableKey
    ]

    // MARK: - Listeleme

    /// Bir klasörün içeriğini asenkron olarak listeler.
    /// - Parameters:
    ///   - url: Listelenecek klasör.
    ///   - includeHidden: Gizli öğeler de listelensin mi?
    ///   - includeExtendedMetadata: İzin, sahip ve etiket sütunları için ek
    ///     meta veri okunsun mu? Yalnızca ilgili sütunlar görünürken `true` verin.
    /// - Returns: Klasörün anlık görüntüsü.
    func listDirectory(
        at url: URL,
        includeHidden: Bool,
        includeExtendedMetadata: Bool = false
    ) async throws -> DirectorySnapshot {
        try await Task.detached(priority: .userInitiated) {
            try Self.listDirectorySync(
                at: url,
                includeHidden: includeHidden,
                includeExtendedMetadata: includeExtendedMetadata
            )
        }.value
    }

    /// Listeleme işleminin eşzamanlı çekirdeği. Birim testlerinde doğrudan çağrılır.
    static func listDirectorySync(
        at url: URL,
        includeHidden: Bool,
        includeExtendedMetadata: Bool = false
    ) throws -> DirectorySnapshot {
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileOperationError.sourceMissing(url)
        }
        guard isDirectory.boolValue else {
            throw FileOperationError.notADirectory(url)
        }

        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: options
            )
        } catch {
            throw FileOperationError.accessDenied(url)
        }

        var items: [FileItem] = []
        items.reserveCapacity(contents.count)
        for childURL in contents {
            if let item = FileItem.make(url: childURL, extendedMetadata: includeExtendedMetadata) {
                // Gizli bayrağı `skipsHiddenFiles` ile tutarlı olsun diye ek bir kontrol.
                if !includeHidden && item.isHidden {
                    continue
                }
                items.append(item)
            }
        }

        let capacity = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage

        let parentURL = url.deletingLastPathComponent()
        let normalizedParent: URL? = (parentURL.path == url.path) ? nil : parentURL

        return DirectorySnapshot(
            url: url,
            parentURL: normalizedParent,
            items: items,
            volumeAvailableCapacity: capacity,
            errorMessage: nil
        )
    }

    // MARK: - Klasör oluşturma ve yeniden adlandırma

    /// Klasör içinde çakışmayan yeni bir klasör adı üretir ("Yeni Klasör", "Yeni Klasör 2", ...).
    /// - Parameters:
    ///   - directory: Yeni klasörün oluşturulacağı klasör.
    ///   - preferredName: Tercih edilen ad.
    static func uniqueDirectoryName(in directory: URL, preferredName: String) -> String {
        let fileManager = FileManager.default
        let base = preferredName.isEmpty ? L.t("newFolder.defaultName") : preferredName
        var candidate = base
        var counter = 2
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// Belirtilen klasörde yeni bir klasör oluşturur. Ad çakışırsa numaralandırır.
    /// - Parameters:
    ///   - directory: Üst klasör.
    ///   - preferredName: Tercih edilen klasör adı.
    /// - Returns: Oluşturulan klasörün adresi.
    func createDirectory(in directory: URL, preferredName: String = "") async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.createDirectorySync(in: directory, preferredName: preferredName)
        }.value
    }

    /// Klasör oluşturmanın eşzamanlı çekirdeği.
    static func createDirectorySync(in directory: URL, preferredName: String) throws -> URL {
        let name = uniqueDirectoryName(in: directory, preferredName: preferredName)
        let newURL = directory.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
        } catch {
            throw FileOperationError.accessDenied(newURL)
        }
        return newURL
    }

    /// Bir öğeyi aynı klasör içinde yeniden adlandırır.
    /// - Parameters:
    ///   - url: Yeniden adlandırılacak öğe.
    ///   - newName: Yeni ad. "/" ve ":" karakterleri kabul edilmez.
    /// - Returns: Yeni adres.
    func rename(_ url: URL, to newName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.renameSync(url, to: newName)
        }.value
    }

    /// Yeniden adlandırmanın eşzamanlı çekirdeği.
    static func renameSync(_ url: URL, to newName: String) throws -> URL {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateName(trimmedName)

        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
        if destination.standardizedFileURL == url.standardizedFileURL {
            return url
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw FileOperationError.destinationExists(destination)
        }

        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            throw FileOperationError.moveFailed(url, ErrorMessages.message(for: error))
        }
        return destination
    }

    /// Geçersiz dosya adlarını denetler.
    /// - Parameter name: Denetlenecek ad.
    static func validateName(_ name: String) throws {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        if name.isEmpty
            || name == "."
            || name == ".."
            || name.rangeOfCharacter(from: invalidCharacters) != nil
            || name.contains("\0") {
            throw FileOperationError.invalidName(name)
        }
    }

    // MARK: - Çakışma çözümü

    /// Hedef klasörde aynı ada sahip bir öğe varsa, çakışmayan yeni bir adres üretir.
    /// Örnek: `rapor.txt` → `rapor 2.txt` → `rapor 3.txt`
    /// - Parameters:
    ///   - name: Önerilen dosya adı.
    ///   - directory: Hedef klasör.
    static func uniqueDestination(for name: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let firstCandidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: firstCandidate.path) else {
            return firstCandidate
        }

        let url = URL(fileURLWithPath: name)
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var counter = 2
        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) \(counter)"
            } else {
                candidateName = "\(baseName) \(counter).\(fileExtension)"
            }
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    // MARK: - Silme

    /// Bir öğeyi Çöp Kutusu'na taşır (eşzamanlı çalışır, arka planda çağrılmalıdır).
    /// - Parameter url: Taşınacak öğe.
    /// - Returns: Çöp Kutusu'ndaki yeni adres (bilinmiyorsa `nil`).
    @discardableResult
    static func trashSync(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            throw FileOperationError.trashFailed(url, ErrorMessages.message(for: error))
        }
        return resultingURL as URL?
    }

    /// Bir öğeyi kalıcı olarak siler (eşzamanlı çalışır, arka planda çağrılmalıdır).
    static func deletePermanentlySync(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw FileOperationError.deleteFailed(url, ErrorMessages.message(for: error))
        }
    }

    /// Çöp Kutusu'na taşıma işlemini asenkron yürütür.
    func trash(_ url: URL) async throws -> URL? {
        try await Task.detached(priority: .userInitiated) {
            try Self.trashSync(url)
        }.value
    }

    /// Kalıcı silme işlemini asenkron yürütür.
    func deletePermanently(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.deletePermanentlySync(url)
        }.value
    }

    // MARK: - Yardımcılar

    /// İki adresin aynı dosyayı gösterip göstermediğini denetler.
    static func isSameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    /// `candidate` adresinin `ancestor` klasörünün (alt klasörleri dahil) içinde
    /// olup olmadığını belirtir. Yol bileşeni sınırına dikkat edilir; böylece
    /// `/Klasor2`, `/Klasor` içinde sayılmaz.
    static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        guard candidatePath != ancestorPath else { return false }
        let prefix = ancestorPath == "/" ? "/" : ancestorPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    /// Bir kopyalama/taşıma işleminin güvenli olup olmadığını denetler.
    /// Bir klasörün kendi içine (veya alt klasörüne) kopyalanması/taşınması
    /// sonsuz döngüye ve veri kaybına yol açabileceğinden reddedilir.
    /// - Parameters:
    ///   - sources: Kaynak adresler.
    ///   - destinationDirectory: Hedef klasör.
    static func validateTransfer(sources: [URL], to destinationDirectory: URL) throws {
        for source in sources {
            if isDescendant(destinationDirectory, of: source) {
                throw FileOperationError.destinationInsideSource(source, destinationDirectory)
            }
            if isSameLocation(source, destinationDirectory) {
                throw FileOperationError.sameLocation(source, destinationDirectory)
            }
        }
    }

    /// Bir adresin kök klasör olup olmadığını belirtir.
    /// `URL.deletingLastPathComponent()` kök için "/.." ürettiğinden yol sadeleştirilerek karşılaştırılır.
    static func isRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path != "/" else { return true }
        return url.deletingLastPathComponent().standardizedFileURL.path == path
    }
}

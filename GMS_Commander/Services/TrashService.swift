//
//  TrashService.swift
//  GMS_Commander
//
//  macOS Çöp Kutusu'ndaki öğeleri listeler, seçilenleri istenen klasöre geri
//  yükler ve isteğe bağlı olarak çöp kutusunu boşaltır. Geri yükleme sırasında
//  hedefte aynı ad varsa dosya ezilmez; benzersiz ad üretilir.
//

import Foundation

/// Çöp Kutusu'ndaki tek bir öğe.
struct TrashItem: Identifiable, Hashable, Sendable {
    /// Öğenin çöp kutusundaki tam yolu.
    let url: URL
    /// Görünen ad.
    let name: String
    /// Klasör mü?
    let isDirectory: Bool
    /// Boyut (klasörlerde 0).
    let size: Int64
    /// Çöpe atılma/Değiştirme tarihi.
    let modificationDate: Date?

    var id: URL { url }
}

/// Çöp Kutusu işlemlerinde oluşan hatalar.
enum TrashError: LocalizedError {
    case trashUnavailable(String)
    case sourceNotInTrash(String)
    case restoreFailed(String, String)
    case emptyFailed(String)

    var errorDescription: String? {
        switch self {
        case .trashUnavailable(let path):
            return "Çöp Kutusu bulunamadı: \(path)"
        case .sourceNotInTrash(let name):
            return "“\(name)” Çöp Kutusu içinde değil; geri yüklenemez."
        case .restoreFailed(let name, let detail):
            return "“\(name)” geri yüklenemedi: \(detail)"
        case .emptyFailed(let detail):
            return "Çöp Kutusu boşaltılamadı: \(detail)"
        }
    }
}

/// Çöp Kutusu servisi.
struct TrashService: Sendable {
    /// Testlerde geçici bir çöp kutusu kökü enjekte etmek için kullanılır.
    private let rootOverride: URL?

    /// - Parameter trashRoot: Özel çöp kutusu klasörü; `nil` ise kullanıcının
    ///   gerçek `~/.Trash` klasörü kullanılır.
    init(trashRoot: URL? = nil) {
        self.rootOverride = trashRoot
    }

    /// Kullanıcının kendi çöp kutusu klasörü.
    var trashURL: URL {
        rootOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Çöp Kutusu'ndaki üst düzey öğeleri listeler.
    /// `.DS_Store` gibi sistem dosyaları gizlenir.
    /// - Returns: Değiştirme tarihine göre en yeni önce sıralı öğeler.
    func listItems(fileManager: FileManager = .default) throws -> [TrashItem] {
        let root = trashURL
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isSymbolicLinkKey
        ]

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: keys,
                options: []
            )
        } catch {
            throw TrashError.trashUnavailable(error.localizedDescription)
        }

        let items: [TrashItem] = contents.compactMap { url in
            guard url.lastPathComponent != ".DS_Store" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return TrashItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                modificationDate: values?.contentModificationDate
            )
        }

        return items.sorted { lhs, rhs in
            let lhsDate = lhs.modificationDate ?? .distantPast
            let rhsDate = rhs.modificationDate ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Çöp Kutusu'ndaki öğeleri hedef klasöre geri yükler.
    ///
    /// Öğe gerçekten çöp kutusunun içinde değilse işlem reddedilir. Hedefte
    /// aynı ad varsa dosya ezilmez; "ad 2" biçiminde yeni ad kullanılır.
    /// - Parameters:
    ///   - items: Geri yüklenecek öğeler.
    ///   - destination: Hedef klasör.
    /// - Returns: Geri yüklenen adresler.
    func restore(
        _ items: [TrashItem],
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TrashError.restoreFailed(destination.path, "hedef klasör bulunamadı")
        }

        var restored: [URL] = []
        for item in items {
            guard isInsideTrash(item.url, fileManager: fileManager) else {
                throw TrashError.sourceNotInTrash(item.name)
            }
            let finalURL = FileNaming.uniqueDestination(
                for: item.name,
                in: destination,
                fileManager: fileManager
            )
            do {
                try FileMoveService.moveSync(
                    source: item.url,
                    to: finalURL,
                    overwrite: false,
                    progress: { _ in }
                )
                restored.append(finalURL)
            } catch {
                throw TrashError.restoreFailed(item.name, error.localizedDescription)
            }
        }
        return restored
    }

    /// Çöp Kutusu'ndaki tüm öğeleri kalıcı olarak siler.
    /// - Parameter fileManager: Testlerde değiştirilebilir dosya yöneticisi.
    func empty(fileManager: FileManager = .default) throws {
        let root = trashURL
        guard fileManager.fileExists(atPath: root.path) else { return }

        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []

        var failures: [String] = []
        for url in contents where url.lastPathComponent != ".DS_Store" {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw TrashError.emptyFailed(failures.joined(separator: "; "))
        }
    }

    /// Öğenin çöp kutusu klasörünün altında olduğunu doğrular.
    /// Sembolik bağlantıyla dışarıyı işaret eden bir yol reddedilir.
    private func isInsideTrash(_ url: URL, fileManager: FileManager) -> Bool {
        let root = trashURL.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard candidate.hasPrefix(root + "/") else { return false }

        // Üst düzey öğe olmalı: ara klasörlerden geri yükleme yapılmaz.
        let parent = url.deletingLastPathComponent().standardizedFileURL
            .resolvingSymlinksInPath().path
        let resolvedRoot = trashURL.standardizedFileURL.resolvingSymlinksInPath().path
        return parent == resolvedRoot
    }
}

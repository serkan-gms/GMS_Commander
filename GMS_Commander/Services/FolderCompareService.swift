//
//  FolderCompareService.swift
//  GMS_Commander
//
//  İki klasör ağacını ad, boyut, değiştirme tarihi ve isteğe bağlı SHA-256
//  içeriğine göre karşılaştırır. Yalnızca rapor üretir; hiçbir dosyayı
//  değiştirmez veya silmez.
//

import Foundation

// MARK: - Modeller

/// Karşılaştırma sonucundaki tek bir göreli yolun durumu.
enum CompareStatus: String, CaseIterable, Identifiable, Sendable {
    case identical
    case onlyLeft
    case onlyRight
    case differentSize
    case differentDate
    case differentContent
    case typeMismatch

    var id: String { rawValue }

    /// Durumun Türkçe adı.
    var localizedName: String {
        switch self {
        case .identical: return L.t("compare.status.identical")
        case .onlyLeft: return L.t("compare.status.onlyLeft")
        case .onlyRight: return L.t("compare.status.onlyRight")
        case .differentSize: return L.t("compare.status.differentSize")
        case .differentDate: return L.t("compare.status.differentDate")
        case .differentContent: return L.t("compare.status.differentContent")
        case .typeMismatch: return L.t("compare.status.typeMismatch")
        }
    }

    /// Durumun simgesi (renk tek başına anlam taşımasın).
    var systemImage: String {
        switch self {
        case .identical: return "equal.circle"
        case .onlyLeft: return "arrow.left.circle"
        case .onlyRight: return "arrow.right.circle"
        case .differentSize: return "arrow.up.arrow.down.circle"
        case .differentDate: return "clock.badge.exclamationmark"
        case .differentContent: return "doc.badge.ellipsis"
        case .typeMismatch: return "exclamationmark.triangle"
        }
    }

    /// Yalnızca farklılık mı?
    var isDifference: Bool { self != .identical }
}

/// İki taraftaki tek bir öğenin karşılaştırma satırı.
struct CompareEntry: Identifiable, Hashable, Sendable {
    /// Kök klasörlere göre göreli yol (eğik çizgiyle ayrılmış).
    let relativePath: String
    /// Sol tarafta var mı?
    let leftExists: Bool
    /// Sağ tarafta var mı?
    let rightExists: Bool
    /// Sol öğe klasör mü?
    let leftIsDirectory: Bool
    /// Sağ öğe klasör mü?
    let rightIsDirectory: Bool
    let leftSize: Int64?
    let rightSize: Int64?
    let leftDate: Date?
    let rightDate: Date?
    /// Karşılaştırma sonucu.
    let status: CompareStatus

    var id: String { relativePath }

    /// Görünen ad (son yol bileşeni).
    var name: String {
        (relativePath as NSString).lastPathComponent
    }
}

/// Karşılaştırma seçenekleri.
struct CompareOptions: Sendable, Equatable {
    /// Dosya boyutlarını karşılaştır.
    var compareSize = true
    /// Değiştirme tarihlerini karşılaştır (2 saniye tolerans).
    var compareDate = false
    /// SHA-256 içerik özetini karşılaştır.
    var compareContent = false
    /// Gizli öğeleri dahil et.
    var includeHidden = false
    /// Alt klasörlere in.
    var recursive = true
}

/// Karşılaştırma çıktısı.
struct CompareOutcome: Sendable {
    let entries: [CompareEntry]
    let leftItemCount: Int
    let rightItemCount: Int
    let duration: TimeInterval
    /// İzin/okuma hatası nedeniyle atlanan öğe sayısı.
    let skippedCount: Int
    let wasCancelled: Bool

    /// Durum başına satır sayısı.
    func count(of status: CompareStatus) -> Int {
        entries.reduce(0) { $0 + ($1.status == status ? 1 : 0) }
    }

    /// Farklılık içeren satır sayısı.
    var differenceCount: Int {
        entries.reduce(0) { $0 + ($1.status.isDifference ? 1 : 0) }
    }
}

/// Klasör karşılaştırma hatası.
enum FolderCompareError: LocalizedError {
    case notDirectory(String)
    case sameFolder
    case nestedFolders

    var errorDescription: String? {
        switch self {
        case .notDirectory(let path):
            return "Klasör bulunamadı veya erişilemiyor: \(path)"
        case .sameFolder:
            return "Aynı klasör kendisiyle karşılaştırılamaz."
        case .nestedFolders:
            return "İç içe klasörler karşılaştırılamaz; iki bağımsız klasör seçin."
        }
    }
}

// MARK: - Servis

/// İki klasörü karşılaştıran servis.
struct FolderCompareService: Sendable {
    /// Tarih farkı için tolerans (dosya sistemi çözünürlüğü).
    static let dateTolerance: TimeInterval = 2

    /// İki klasörü karşılaştırır.
    /// - Parameters:
    ///   - left: Sol kök.
    ///   - right: Sağ kök.
    ///   - options: Karşılaştırma seçenekleri.
    ///   - control: İptal denetimi.
    ///   - progress: Taranan öğe sayısı.
    /// - Returns: Ayrıntılı fark listesi.
    func compare(
        left: URL,
        right: URL,
        options: CompareOptions,
        control: TransferControl? = nil,
        progress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> CompareOutcome {
        try await Task.detached(priority: .userInitiated) {
            try Self.compareSync(
                left: left,
                right: right,
                options: options,
                control: control,
                progress: progress
            )
        }.value
    }

    /// Karşılaştırmanın eşzamanlı çekirdeği (testlerde doğrudan çağrılır).
    static func compareSync(
        left: URL,
        right: URL,
        options: CompareOptions,
        control: TransferControl? = nil,
        progress: (@Sendable (Int) -> Void)? = nil
    ) throws -> CompareOutcome {
        let started = Date()
        let fileManager = FileManager.default

        for root in [left, right] {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw FolderCompareError.notDirectory(root.path)
            }
        }

        let leftPath = left.standardizedFileURL.path
        let rightPath = right.standardizedFileURL.path
        if leftPath == rightPath { throw FolderCompareError.sameFolder }
        if leftPath.hasPrefix(rightPath + "/") || rightPath.hasPrefix(leftPath + "/") {
            throw FolderCompareError.nestedFolders
        }

        let (leftItems, leftSkipped) = try scan(
            root: left,
            options: options,
            control: control,
            progress: progress
        )
        let (rightItems, rightSkipped) = try scan(
            root: right,
            options: options,
            control: control,
            progress: progress
        )
        let skipped = leftSkipped + rightSkipped
        try control?.waitIfPaused()

        let allPaths = Set(leftItems.keys).union(rightItems.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var entries: [CompareEntry] = []
        entries.reserveCapacity(allPaths.count)

        for path in allPaths {
            try control?.waitIfPaused()
            let leftInfo = leftItems[path]
            let rightInfo = rightItems[path]

            let status: CompareStatus
            switch (leftInfo, rightInfo) {
            case (.none, .some):
                status = .onlyRight
            case (.some, .none):
                status = .onlyLeft
            case let (.some(lhs), .some(rhs)):
                if lhs.isDirectory != rhs.isDirectory {
                    status = .typeMismatch
                } else if lhs.isDirectory {
                    status = .identical
                } else if options.compareSize, lhs.size != rhs.size {
                    status = .differentSize
                } else if options.compareContent,
                          !Self.contentsMatch(left: left, right: right, path: path, control: control) {
                    status = .differentContent
                } else if options.compareDate,
                          !Self.datesMatch(lhs.date, rhs.date) {
                    status = .differentDate
                } else {
                    status = .identical
                }
            case (.none, .none):
                continue
            }

            entries.append(
                CompareEntry(
                    relativePath: path,
                    leftExists: leftInfo != nil,
                    rightExists: rightInfo != nil,
                    leftIsDirectory: leftInfo?.isDirectory ?? false,
                    rightIsDirectory: rightInfo?.isDirectory ?? false,
                    leftSize: leftInfo?.isDirectory == false ? leftInfo?.size : nil,
                    rightSize: rightInfo?.isDirectory == false ? rightInfo?.size : nil,
                    leftDate: leftInfo?.date,
                    rightDate: rightInfo?.date,
                    status: status
                )
            )
        }

        return CompareOutcome(
            entries: entries,
            leftItemCount: leftItems.count,
            rightItemCount: rightItems.count,
            duration: Date().timeIntervalSince(started),
            skippedCount: skipped,
            wasCancelled: control?.isCancelled == true
        )
    }

    // MARK: - Tarama

    /// Bir tarafın tüm öğelerini göreli yola göre toplar.
    private struct SideInfo: Sendable {
        let isDirectory: Bool
        let size: Int64
        let date: Date?
    }

    private static func scan(
        root: URL,
        options: CompareOptions,
        control: TransferControl?,
        progress: (@Sendable (Int) -> Void)?
    ) throws -> (items: [String: SideInfo], skipped: Int) {
        let fileManager = FileManager.default
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        var result: [String: SideInfo] = [:]
        var skipped = 0
        let rootPath = root.standardizedFileURL.path

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
            ],
            options: enumerationOptions,
            errorHandler: { _, _ in
                skipped += 1
                return true
            }
        ) else {
            return (result, skipped)
        }

        var scanned = 0
        for case let url as URL in enumerator {
            try control?.waitIfPaused()
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
            ])
            let isDirectory = values?.isDirectory ?? false
            let isSymbolicLink = values?.isSymbolicLink ?? false

            let relative = relativePath(of: url, rootPath: rootPath)
            if !options.recursive, relative.contains("/") {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Sembolik bağlantılar hedef ağaca taşmadığı için karşılaştırma dışıdır.
            if isSymbolicLink {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            result[relative] = SideInfo(
                isDirectory: isDirectory,
                size: isDirectory ? 0 : Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate
            )

            scanned += 1
            if scanned % 200 == 0 {
                progress?(scanned)
            }
        }
        progress?(scanned)
        return (result, skipped)
    }

    private static func relativePath(of url: URL, rootPath: String) -> String {
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(fullPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    // MARK: - İçerik ve tarih

    private static func contentsMatch(
        left: URL,
        right: URL,
        path: String,
        control: TransferControl?
    ) -> Bool {
        let leftURL = left.appendingPathComponent(path)
        let rightURL = right.appendingPathComponent(path)
        do {
            let leftDigest = try FileHashService.sha256(of: leftURL, control: control)
            let rightDigest = try FileHashService.sha256(of: rightURL, control: control)
            return leftDigest == rightDigest
        } catch {
            // Okunamayan dosya "farklı" sayılmaz; karşılaştırılamadı olarak
            // işaretlenmesi için içerik farkı döndürüyoruz.
            return false
        }
    }

    private static func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs.timeIntervalSince(rhs)) <= dateTolerance
    }
}

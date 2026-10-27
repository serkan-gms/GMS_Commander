//
//  FileItem.swift
//  GMS_Commander
//
//  Dosya listelerinde gösterilen tek bir dosya veya klasörü temsil eden model.
//  Bu tip; ad, tür, boyut, tarih ve simge için gerekli tüm bilgileri taşır.
//  Arayüzden bağımsızdır; bu sayede birim testlerinde doğrudan kullanılabilir.
//

import Foundation
import UniformTypeIdentifiers

/// Dosya listesinin sıralanabileceği sütunlar.
enum FileSortKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case fileExtension
    case kind
    case size
    case date
    case created
    case permissions
    case owner
    case tags

    var id: String { rawValue }

    /// Menü ve başlıklarda gösterilen Türkçe ad.
    var localizedName: String {
        switch self {
        case .name: return L.t("column.name")
        case .fileExtension: return L.t("column.extension")
        case .kind: return L.t("column.kind")
        case .size: return L.t("column.size")
        case .date: return L.t("column.date")
        case .created: return L.t("column.created")
        case .permissions: return L.t("column.permissions")
        case .owner: return L.t("column.owner")
        case .tags: return L.t("column.tags")
        }
    }
}

/// Dosya panelinde gösterilebilen sütunlar.
enum PanelColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case fileExtension
    case kind
    case size
    case date
    case created
    case permissions
    case owner
    case tags

    var id: String { rawValue }

    /// Sütunun sıralama anahtarı.
    var sortKey: FileSortKey {
        switch self {
        case .name: return .name
        case .fileExtension: return .fileExtension
        case .kind: return .kind
        case .size: return .size
        case .date: return .date
        case .created: return .created
        case .permissions: return .permissions
        case .owner: return .owner
        case .tags: return .tags
        }
    }

    /// Sütun başlığındaki Türkçe ad.
    var title: String { sortKey.localizedName }

    /// Varsayılan görünür sütunlar.
    static let defaultVisible: [PanelColumn] = [.name, .kind, .size, .date]
}

/// Panelin liste görünüm türü.
enum PanelViewMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Ayrıntılı sütunlu liste.
    case details
    /// Daha küçük satır yüksekliğinde kompakt liste.
    case compact
    /// Simge ızgarası.
    case icons

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .details: return L.t("viewMode.details")
        case .compact: return L.t("viewMode.compact")
        case .icons: return L.t("viewMode.icons")
        }
    }

    var systemImage: String {
        switch self {
        case .details: return "list.bullet"
        case .compact: return "list.dash"
        case .icons: return "square.grid.2x2"
        }
    }
}

/// Bir dosya sistem öğesinin (dosya, klasör, paket veya sembolik bağlantı) değişmez tanımı.
struct FileItem: Identifiable, Hashable, Sendable {
    /// Öğenin dosya sistemindeki tam adresi. Aynı zamanda listede benzersiz kimliktir.
    let url: URL

    /// Kullanıcıya gösterilen ad (son yol bileşeni).
    let name: String

    /// Öğe bir klasör mü? Sembolik bağlantılarda hedefin türü dikkate alınır.
    let isDirectory: Bool

    /// Öğe bir sembolik bağlantı mı?
    let isSymbolicLink: Bool

    /// Öğe bir paket (ör. .app, .photoslibrary) mi?
    let isPackage: Bool

    /// Öğe gizli mi? (Nokta ile başlayan adlar ve gizli bayrağı olan öğeler.)
    let isHidden: Bool

    /// Dosya boyutu (bayt). Klasörlerde 0 kabul edilir; arayüzde "—" gösterilir.
    let size: Int64

    /// Son değiştirilme tarihi.
    let modificationDate: Date?

    /// Oluşturulma tarihi.
    let creationDate: Date?

    /// Türkçe tür etiketi (ör. "Klasör", "PNG Dosyası").
    let kind: String

    /// Öğenin okunabilir olup olmadığı. Erişim reddedilen öğeler de listelenir.
    let isReadable: Bool

    /// POSIX izinlerinin kısa gösterimi (ör. "rw-r--r--"). Genişletilmiş
    /// meta veri istenmediyse `nil`.
    let permissionsText: String?

    /// Dosyanın sahibi. Genişletilmiş meta veri istenmediyse `nil`.
    let ownerName: String?

    /// Dosyanın grubu. Genişletilmiş meta veri istenmediyse `nil`.
    let groupName: String?

    /// Finder etiketleri. Etiket yoksa veya genişletilmiş meta veri
    /// istenmediyse boş dizi.
    let tagNames: [String]

    /// Arama sonuçlarında, aramanın başladığı klasöre göre göreli yol.
    /// Normal listelemede `nil` olur.
    let relativePath: String?

    var id: URL { url }

    /// Satır ikonunun dosya sisteminden yüklenmesi için kullanılan yol.
    var path: String { url.path }

    /// Kullanıcı çift tıkladığında klasöre girilip girilemeyeceğini belirtir.
    var isNavigable: Bool { isDirectory }

    /// Dosya uzantısı (küçük harf). Uzantı yoksa boş dizedir.
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
}

// MARK: - Oluşturma

extension FileItem {
    /// Verilen adres için dosya sistemi meta verilerini okuyup bir `FileItem` üretir.
    /// - Parameters:
    ///   - url: Öğenin adresi.
    ///   - relativePath: Arama sonucuysa kök klasöre göre göreli yol.
    ///   - extendedMetadata: İzin, sahip, grup ve etiket bilgileri de okunsun mu?
    ///     Bu alanlar her dosya için ek sistem çağrısı gerektirir; yalnızca ilgili
    ///     sütunlar görünürken istenmelidir.
    /// - Returns: Öğe okunamıyorsa veya mevcut değilse `nil`.
    static func make(
        url: URL,
        relativePath: String? = nil,
        extendedMetadata: Bool = false
    ) -> FileItem? {
        var resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isReadableKey
        ]
        if extendedMetadata {
            resourceKeys.insert(.tagNamesKey)
        }

        let values = try? url.resourceValues(forKeys: resourceKeys)
        let fileManager = FileManager.default

        // Bozuk sembolik bağlantılarda `fileExists` false dönebilir; bu yüzden
        // kaynak değerleri varsa öğeyi yine de listeliyoruz.
        guard values != nil || fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let isSymbolicLink = values?.isSymbolicLink
            ?? ((try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil)
        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        let name = url.lastPathComponent

        // `isHidden` bazen yalnızca nokta ile başlayan adlarda güvenilirdir;
        // bu yüzden iki sinyali birleştiriyoruz.
        let isHidden = name.hasPrefix(".") || (values?.isHidden ?? false)

        let rawSize = Int64(values?.fileSize ?? 0)
        let size = isDirectory ? 0 : max(rawSize, 0)

        // İzin ve sahiplik bilgisi `URLResourceValues` üzerinden doğrudan
        // okunamadığı için `FileManager` özniteliklerini kullanıyoruz.
        // Yalnızca gerektiğinde okunur; binlerce dosyalık klasörlerde
        // gereksiz sistem çağrısı yapılmaz.
        var permissionsText: String?
        var ownerName: String?
        var groupName: String?
        var tagNames: [String] = []
        if extendedMetadata {
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path) {
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    permissionsText = PermissionsFormatter.symbolicString(fromMode: Int(permissions.uint16Value))
                }
                ownerName = attributes[.ownerAccountName] as? String
                groupName = attributes[.groupOwnerAccountName] as? String
            }
            tagNames = values?.tagNames ?? []
        }

        return FileItem(
            url: url,
            name: name,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            isPackage: isPackage,
            isHidden: isHidden,
            size: size,
            modificationDate: values?.contentModificationDate,
            creationDate: values?.creationDate,
            kind: FileKindProvider.kind(
                for: url,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink,
                isPackage: isPackage
            ),
            isReadable: values?.isReadable ?? fileManager.isReadableFile(atPath: url.path),
            permissionsText: permissionsText,
            ownerName: ownerName,
            groupName: groupName,
            tagNames: tagNames,
            relativePath: relativePath
        )
    }
}

// MARK: - Sıralama

extension FileItem {
    /// Öğeleri istenen sütuna göre sıralar. Klasörler (varsayılan olarak) her zaman üstte kalır.
    /// - Parameters:
    ///   - items: Sıralanacak öğeler.
    ///   - key: Sıralama sütunu.
    ///   - ascending: Artan sıralama mı?
    ///   - foldersFirst: Klasörler üstte mi kalsın?
    /// - Returns: Sıralanmış yeni dizi.
    static func sorted(
        _ items: [FileItem],
        by key: FileSortKey,
        ascending: Bool,
        foldersFirst: Bool = true
    ) -> [FileItem] {
        items.sorted { lhs, rhs in
            if foldersFirst, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let comparison = compare(lhs, rhs, by: key)
            if comparison == .orderedSame {
                // Eşit değerlerde ad ile deterministik bir sıra sağlıyoruz.
                let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
                if nameComparison == .orderedSame {
                    return lhs.path < rhs.path
                }
                return nameComparison == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    /// İki öğeyi verilen sütuna göre karşılaştırır.
    private static func compare(_ lhs: FileItem, _ rhs: FileItem, by key: FileSortKey) -> ComparisonResult {
        switch key {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .fileExtension:
            let result = lhs.fileExtension.localizedStandardCompare(rhs.fileExtension)
            return result == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : result
        case .kind:
            let result = lhs.kind.localizedStandardCompare(rhs.kind)
            return result == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : result
        case .size:
            if lhs.size == rhs.size { return .orderedSame }
            return lhs.size < rhs.size ? .orderedAscending : .orderedDescending
        case .date:
            let lhsDate = lhs.modificationDate ?? .distantPast
            let rhsDate = rhs.modificationDate ?? .distantPast
            if lhsDate == rhsDate { return .orderedSame }
            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
        case .created:
            let lhsDate = lhs.creationDate ?? .distantPast
            let rhsDate = rhs.creationDate ?? .distantPast
            if lhsDate == rhsDate { return .orderedSame }
            return lhsDate < rhsDate ? .orderedAscending : .orderedDescending
        case .permissions:
            let result = (lhs.permissionsText ?? "").localizedStandardCompare(rhs.permissionsText ?? "")
            return result == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : result
        case .owner:
            let result = (lhs.ownerName ?? "").localizedStandardCompare(rhs.ownerName ?? "")
            return result == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : result
        case .tags:
            let lhsTags = lhs.tagNames.joined(separator: ", ")
            let rhsTags = rhs.tagNames.joined(separator: ", ")
            let result = lhsTags.localizedStandardCompare(rhsTags)
            return result == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : result
        }
    }
}

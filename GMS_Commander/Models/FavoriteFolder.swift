//
//  FavoriteFolder.swift
//  GMS_Commander
//
//  Sık kullanılan klasör kaydı. Yol ve görünen ad birlikte saklanır; böylece
//  klasör geçici olarak erişilemez olsa bile kenar çubuğundaki ad korunur.
//

import Foundation

/// Kenar çubuğunda listelenen sık kullanılan klasör.
struct FavoriteFolder: Codable, Identifiable, Hashable {
    /// Kalıcı kimlik (Liste yeniden sıralansa da korunur).
    let id: UUID
    /// Klasörün mutlak yolu.
    var path: String
    /// Kenar çubuğunda gösterilen ad.
    var name: String
    /// Kenar çubuğu bölüm kimliği. Eski kayıtlar ilk bölüme taşınır.
    var groupID: UUID?

    init(id: UUID = UUID(), path: String, name: String? = nil, groupID: UUID? = nil) {
        let normalized = Self.normalizedPath(path)
        self.id = id
        self.path = normalized
        self.name = name ?? Self.displayName(for: normalized)
        self.groupID = groupID
    }

    /// Klasör adresi.
    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Kayıt bir klasörü mü gösteriyor? Dosyalar da hızlı erişime eklenebilir.
    var isDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isApplication: Bool {
        url.pathExtension.lowercased() == "app"
    }

    /// Kenar çubuğunda gösterilen simge adı.
    var systemImage: String {
        Self.systemImage(for: path)
    }

    /// Yolu karşılaştırılabilir biçime getirir (sondaki eğik çizgi atılır).
    static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
        let result = url.path
        return result.count > 1 && result.hasSuffix("/") ? String(result.dropLast()) : result
    }

    /// Yoldan görünen ad üretir; kök klasör "/" olarak kalır.
    static func displayName(for path: String) -> String {
        let normalized = normalizedPath(path)
        if normalized == "/" { return "/" }
        let name = (normalized as NSString).lastPathComponent
        let localizedNames = [
            "Desktop": "favorites.folder.desktop",
            "Documents": "favorites.folder.documents",
            "Downloads": "favorites.folder.downloads",
            "Pictures": "favorites.folder.pictures",
            "Music": "favorites.folder.music",
            "Movies": "favorites.folder.movies",
            "Applications": "favorites.folder.applications"
        ]
        guard let key = localizedNames[name] else { return name }
        return L.t(key)
    }

    /// Sık kullanılanlar için kısa simge adı.
    static func systemImage(for path: String) -> String {
        let target = normalizedPath(path)
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let known: [(String, String)] = [
            (home, "house"),
            (home + "/Desktop", "menubar.dock.rectangle"),
            (home + "/Documents", "doc.text"),
            (home + "/Downloads", "arrow.down.circle"),
            (home + "/Pictures", "photo"),
            (home + "/Music", "music.note"),
            (home + "/Movies", "film"),
            ("/Applications", "square.grid.2x2"),
            ("/Users", "person.2"),
            ("/", "internaldrive")
        ]
        for (candidate, image) in known where candidate == target {
            return image
        }
        return "folder"
    }

    /// Adresten kayıt üretir.
    static func make(url: URL) -> FavoriteFolder {
        FavoriteFolder(path: url.path)
    }
}

/// Kullanıcının düzenleyebildiği hızlı erişim bölümü.
struct FavoriteGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var colorHex: UInt32
    var role: FavoriteGroupRole?
    /// Bölümün kabul ettiği kayıt türü (klasör, dosya veya disk).
    var kind: FavoriteGroupKind

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: UInt32,
        role: FavoriteGroupRole? = nil,
        kind: FavoriteGroupKind? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.role = role
        self.kind = kind ?? role?.defaultKind ?? .folder
    }

    /// Eski kayıtlarda `kind` alanı yoktur; bölüm rolünden türetilir.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(UInt32.self, forKey: .colorHex)
        role = try container.decodeIfPresent(FavoriteGroupRole.self, forKey: .role)
        kind = try container.decodeIfPresent(FavoriteGroupKind.self, forKey: .kind)
            ?? role?.defaultKind
            ?? .folder
    }

    static let defaultDefinitions: [(nameKey: String, colorHex: UInt32, role: FavoriteGroupRole)] = [
        ("favorites.group.quickAccess", 0x4F9CF9, .quickAccess),
        ("favorites.group.applications", 0xB18AF5, .applications),
        ("favorites.group.projects", 0x42C98A, .projects),
        ("favorites.group.disks", 0xE0A84B, .disks)
    ]
}

enum FavoriteGroupRole: String, Codable, Sendable {
    case quickAccess
    case applications
    case projects
    case disks

    /// Bölümün varsayılan kayıt türü.
    var defaultKind: FavoriteGroupKind {
        switch self {
        case .quickAccess, .projects: return .folder
        case .applications: return .file
        case .disks: return .disk
        }
    }
}

/// Hızlı erişim bölümlerinin kabul ettiği kayıt türü.
enum FavoriteGroupKind: String, Codable, CaseIterable, Sendable {
    /// Yalnızca klasörler.
    case folder
    /// Dosyalar (uygulama paketleri dâhil).
    case file
    /// Bağlı disk birimleri; bölüm kendiliğinden doldurulur.
    case disk

    /// Kullanıcıya gösterilen ad.
    var localizedTitle: String {
        switch self {
        case .folder: return L.t("favorites.kind.folder")
        case .file: return L.t("favorites.kind.file")
        case .disk: return L.t("favorites.kind.disk")
        }
    }

    /// Yeni bölüm oluştururken sunulan türler.
    static var selectableCases: [FavoriteGroupKind] { [.folder, .file] }
}

//
//  FavoritesViewModel.swift
//  GMS_Commander
//
//  Sık kullanılan klasörleri (kenar çubuğu) yönetir. Liste UserDefaults'ta JSON
//  olarak saklanır; ilk açılışta anlamlı varsayılanlar üretilir.
//

import Foundation
import Combine

/// Sık kullanılan klasör listesi.
final class FavoritesViewModel: ObservableObject {
    /// Uygulama genelinde paylaşılan liste.
    static let shared = FavoritesViewModel()

    /// UserDefaults anahtarı.
    enum Keys {
        static let items = "favorites.items"
        static let groups = "favorites.groups"
        static let mountedVolumesSeeded = "favorites.mountedVolumesSeeded"
    }

    private let defaults: UserDefaults
    private let includeMountedVolumes: Bool

    /// Sıralı kayıt listesi.
    @Published private(set) var items: [FavoriteFolder] = []
    @Published private(set) var groups: [FavoriteGroup] = []

    /// - Parameter defaults: Testlerde özel bir UserDefaults enjekte etmek için.
    init(defaults: UserDefaults = .standard, includeMountedVolumes: Bool = true) {
        self.defaults = defaults
        self.includeMountedVolumes = includeMountedVolumes
        load()
    }

    // MARK: - Varsayılanlar

    /// İlk açılışta kullanılan varsayılan klasörler (yalnızca var olanlar).
    static func defaultItems() -> [FavoriteFolder] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let candidates = [
            home,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
        return candidates.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            return FavoriteFolder.make(url: url)
        }
    }

    // MARK: - Yükleme ve saklama

    /// Bölümleri ve kayıtları yükler; eski kayıtlara ilk bölümü atar.
    func load() {
        groups = defaults.data(forKey: Keys.groups)
            .flatMap { try? JSONDecoder().decode([FavoriteGroup].self, from: $0) }
            ?? Self.defaultGroups()
        restoreDefaultGroupRoles()

        let decodedItems = defaults.data(forKey: Keys.items)
            .flatMap { try? JSONDecoder().decode([FavoriteFolder].self, from: $0) }
            ?? Self.defaultItems()
        let fallbackGroupID = groups.first?.id
        items = decodedItems.map { item in
            let groupID = item.groupID ?? suggestedGroupID(for: item.url) ?? fallbackGroupID
            let defaultName = (item.path as NSString).lastPathComponent
            let name = item.name == defaultName ? FavoriteFolder.displayName(for: item.path) : item.name
            return FavoriteFolder(id: item.id, path: item.path, name: name, groupID: groupID)
        }
        addMountedVolumesIfNeeded()
        save()
    }

    /// Listeyi kalıcı hâle getirir.
    func save() {
        do {
            defaults.set(try JSONEncoder().encode(items), forKey: Keys.items)
            defaults.set(try JSONEncoder().encode(groups), forKey: Keys.groups)
        } catch {
            NSLog("Sık kullanılanlar kaydedilemedi: %@", error.localizedDescription)
        }
    }

    private static func defaultGroups() -> [FavoriteGroup] {
        FavoriteGroup.defaultDefinitions.map { definition in
            FavoriteGroup(name: L.t(definition.nameKey), colorHex: definition.colorHex, role: definition.role)
        }
    }

    private func restoreDefaultGroupRoles() {
        groups = groups.map { group in
            guard group.role == nil,
                  let definition = FavoriteGroup.defaultDefinitions.first(where: {
                      L.t($0.nameKey).localizedCaseInsensitiveCompare(group.name) == .orderedSame
                  }) else { return group }
            return FavoriteGroup(id: group.id, name: group.name, colorHex: group.colorHex, role: definition.role)
        }
    }

    private func addMountedVolumesIfNeeded() {
        guard includeMountedVolumes, !defaults.bool(forKey: Keys.mountedVolumesSeeded) else { return }
        refreshMountedVolumes()
        defaults.set(true, forKey: Keys.mountedVolumesSeeded)
    }

    /// Diskler bölümünü o anda bağlı olan birimlerle eşitler.
    func refreshMountedVolumes() {
        guard includeMountedVolumes, let diskGroupID = groupID(for: .disks) else { return }
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        )?.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        } ?? []
        let mountedPaths = Set(volumes.map { FavoriteFolder.normalizedPath($0.path).lowercased() })
        let oldItems = items
        items.removeAll { item in
            item.groupID == diskGroupID && !mountedPaths.contains(item.path.lowercased())
        }
        for volume in volumes where !contains(url: volume) {
            items.append(FavoriteFolder(path: volume.path, groupID: diskGroupID))
        }
        if oldItems != items {
            save()
        }
    }

    private func groupID(for role: FavoriteGroupRole) -> UUID? {
        groups.first(where: { $0.role == role })?.id
    }

    func suggestedGroupID(for url: URL) -> UUID? {
        let role: FavoriteGroupRole = url.pathExtension.lowercased() == "app" ? .applications : .quickAccess
        return groupID(for: role)
    }

    // MARK: - Sorgular

    /// Adres listede var mı?
    func contains(url: URL) -> Bool {
        let target = FavoriteFolder.normalizedPath(url.path).lowercased()
        return items.contains { $0.path.lowercased() == target }
    }

    /// Listenin boş olup olmadığı.
    var isEmpty: Bool { items.isEmpty }

    // MARK: - Değiştirme

    /// Dosya veya klasörü hızlı erişime ekler.
    @discardableResult
    func add(url: URL, to groupID: UUID? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let targetGroup = groups.contains(where: { $0.id == groupID }) ? groupID : groups.first?.id
        let targetPath = FavoriteFolder.normalizedPath(url.path).lowercased()
        if let existingIndex = items.firstIndex(where: { $0.path.lowercased() == targetPath }) {
            guard items[existingIndex].groupID != targetGroup else { return false }
            items[existingIndex].groupID = targetGroup
            save()
            return true
        }
        items.append(FavoriteFolder(id: UUID(), path: url.path, groupID: targetGroup))
        save()
        return true
    }

    /// Yol metninden klasör ekler.
    @discardableResult
    func add(path: String, to groupID: UUID? = nil) -> Bool {
        add(url: URL(fileURLWithPath: FavoriteFolder.normalizedPath(path)), to: groupID)
    }

    /// Kaydı kimliğine göre kaldırır.
    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        save()
    }

    /// Kaydı adrese göre kaldırır.
    @discardableResult
    func remove(url: URL) -> Bool {
        let target = FavoriteFolder.normalizedPath(url.path).lowercased()
        guard let index = items.firstIndex(where: { $0.path.lowercased() == target }) else { return false }
        items.remove(at: index)
        save()
        return true
    }

    /// Ekle/çıkar: adres listede varsa kaldırır, yoksa ekler.
    @discardableResult
    func toggle(url: URL) -> Bool {
        if remove(url: url) { return false }
        return add(url: url)
    }

    /// Kayıtların görünen adını yeniler (klasör taşınmış olabilir).
    func refreshNames() {
        items = items.map { FavoriteFolder(id: $0.id, path: $0.path, groupID: $0.groupID) }
        save()
    }

    /// Yeni bir özel bölüm oluşturur.
    @discardableResult
    func addGroup(name: String, colorHex: UInt32 = 0x4F9CF9) -> FavoriteGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !groups.contains(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return nil
        }
        let group = FavoriteGroup(name: trimmed, colorHex: colorHex)
        groups.append(group)
        save()
        return group
    }

    /// Bölüm adını ve rengini günceller.
    func updateGroup(_ group: FavoriteGroup) {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = FavoriteGroup(
            id: group.id,
            name: trimmed,
            colorHex: group.colorHex,
            role: groups[index].role
        )
        save()
    }

    /// Bölümü siler; içindeki kayıtları başka bölüme taşır.
    func removeGroup(id: UUID, moveItemsTo destinationID: UUID? = nil) {
        guard groups.count > 1, groups.contains(where: { $0.id == id }) else { return }
        let fallbackID = groups.first(where: { $0.id != id })?.id
        let targetID = destinationID.flatMap { $0 == id ? nil : $0 } ?? fallbackID
        groups.removeAll { $0.id == id }
        items = items.map { item in
            guard item.groupID == id else { return item }
            return FavoriteFolder(id: item.id, path: item.path, name: item.name, groupID: targetID)
        }
        save()
    }

    /// Kaydı başka bölüme taşır.
    func move(id: UUID, to groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].groupID = groupID
        save()
    }

    /// Hızlı erişim kaydının görünen adını değiştirir.
    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        save()
    }

    /// Bölüm sırasını günceller.
    func moveGroup(from source: IndexSet, to destination: Int) {
        guard let index = source.first, groups.indices.contains(index) else { return }
        let group = groups.remove(at: index)
        let target = max(0, min(destination > index ? destination - 1 : destination, groups.count))
        groups.insert(group, at: target)
        save()
    }

    /// Bölüm içindeki kayıt sırasını değiştirir.
    func moveItem(id: UUID, offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let groupID = items[index].groupID
        let groupIndices = items.indices.filter { items[$0].groupID == groupID }
        guard let groupPosition = groupIndices.firstIndex(of: index) else { return }
        let targetPosition = groupPosition + offset
        guard groupIndices.indices.contains(targetPosition) else { return }
        items.swapAt(index, groupIndices[targetPosition])
        save()
    }

    /// Sık kullanılanları varsayılan bölümlere ve klasörlere döndürür.
    func resetToDefaults() {
        groups = Self.defaultGroups()
        let groupID = groups.first?.id
        items = Self.defaultItems().map {
            FavoriteFolder(id: $0.id, path: $0.path, name: $0.name, groupID: groupID)
        }
        save()
    }
}

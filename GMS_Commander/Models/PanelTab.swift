//
//  PanelTab.swift
//  GMS_Commander
//
//  Bir panel sekmesinin kalıcı durumu. Sekme değiştirildiğinde geçerli klasör,
//  geri/ileri geçmişi ve sıralama tercihleri bu yapıya kaydedilir; uygulama
//  yeniden açıldığında aynı sekmeler geri yüklenir.
//

import Foundation

/// Panel sekmesi.
struct PanelTab: Identifiable, Codable, Equatable, Sendable {
    /// Sekmenin benzersiz kimliği.
    var id: UUID

    /// Sekmenin gösterdiği klasör.
    var path: URL

    /// Geri gezinme yığını.
    var backStack: [URL]

    /// İleri gezinme yığını.
    var forwardStack: [URL]

    /// Sekmenin sıralama sütunu.
    var sortKey: FileSortKey

    /// Sıralama artan mı?
    var sortAscending: Bool

    init(
        id: UUID = UUID(),
        path: URL,
        backStack: [URL] = [],
        forwardStack: [URL] = [],
        sortKey: FileSortKey = .name,
        sortAscending: Bool = true
    ) {
        self.id = id
        self.path = path
        self.backStack = backStack
        self.forwardStack = forwardStack
        self.sortKey = sortKey
        self.sortAscending = sortAscending
    }

    /// Sekmede görünen kısa başlık.
    var title: String {
        if path.path == "/" { return "/" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.path == home { return "~" }
        let name = path.lastPathComponent
        return name.isEmpty ? path.path : name
    }
}

/// Bir panelin tüm sekmeleri ve etkin sekme bilgisi.
struct PanelTabsState: Codable, Equatable, Sendable {
    var tabs: [PanelTab]
    var activeTabID: UUID?
}

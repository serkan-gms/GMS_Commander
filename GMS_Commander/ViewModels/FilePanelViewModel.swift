//
//  FilePanelViewModel.swift
//  GMS_Commander
//
//  Tek bir dosya panelinin durumunu yönetir: geçerli klasör, geçmiş, seçim,
//  sıralama, gizli dosya görünürlüğü ve arama. Görünüm katmanı yalnızca bu
//  nesneyi okur; tüm dosya sistemi erişimi servisler üzerinden yapılır.
//

import Foundation
import Combine

/// Bir dosya panelinin görünüm modeli.
@MainActor
final class FilePanelViewModel: ObservableObject, Identifiable {
    // MARK: - Kimlik

    /// Panelin tarafı (sol/sağ).
    let side: PanelSide

    /// SwiftUI kimliği.
    nonisolated var id: String { side.rawValue }

    // MARK: - Yayınlanan durum

    /// Görüntülenen klasör.
    @Published private(set) var currentDirectory: URL

    /// Son listeleme sonucu.
    @Published private(set) var snapshot: DirectorySnapshot?

    /// Listede gösterilen (sıralanmış) öğeler. Arama sırasında arama sonuçlarını içerir.
    @Published private(set) var items: [FileItem] = []

    /// Seçili öğelerin adresleri.
    @Published private(set) var selection: Set<URL> = []

    /// Listeleme sürüyor mu?
    @Published private(set) var isLoading = false

    /// Arama sürüyor mu?
    @Published private(set) var isSearching = false

    /// Arama sonucu üst sınıra ulaştı mı?
    @Published private(set) var searchReachedLimit = false

    /// Arama metni.
    @Published private(set) var searchQuery = "" {
        didSet { scheduleSearch() }
    }

    /// Sıralama sütunu.
    @Published private(set) var sortKey: FileSortKey

    /// Sıralama artan mı?
    @Published private(set) var sortAscending: Bool

    /// Panel sekmeleri.
    @Published private(set) var tabs: [PanelTab]

    /// Etkin sekme kimliği.
    @Published private(set) var activeTabID: UUID

    /// Gösterilecek hata.
    @Published var alert: UserFacingAlert?

    /// Panelin Git durumu.
    @Published private(set) var gitStatus: GitStatus?

    /// Liste içeriğinin sürümü. Görünüm katmanı (NSTableView) yalnızca bu değer
    /// değiştiğinde tabloyu yeniden yükler; seçim değişiklikleri gereksiz yenileme yapmaz.
    @Published private(set) var revision = 0

    // MARK: - Gizli durum

    private let settings: SettingsStore
    private let fileManagerService = FileManagerService()
    private let searchService = FileSearchService()
    private let gitService = GitService()
    private let watcher = FileWatcherService()

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var searchResults: [FileItem]?
    private var searchTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// Yenileme tamamlandığında seçilecek ve görünür alana kaydırılacak öğe.
    private var pendingRevealURL: URL?

    // MARK: - Başlatma

    /// - Parameters:
    ///   - side: Panelin tarafı.
    ///   - settings: Ayar deposu (gizli dosya ve sıralama tercihleri için).
    init(side: PanelSide, settings: SettingsStore) {
        self.side = side
        self.settings = settings

        let storedPath = side == .left ? settings.leftPanelPath : settings.rightPanelPath
        let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        let fallbackURL: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: storedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            fallbackURL = storedURL
        } else {
            fallbackURL = FileManager.default.homeDirectoryForCurrentUser
        }

        // Son oturumdaki sekmeleri geri yükle. Geçersiz (silinmiş) klasörler
        // atlanır; hiç geçerli sekme kalmazsa tek sekme ile başlanır.
        var restoredTabs: [PanelTab] = []
        var restoredActiveID: UUID?
        if settings.restoreTabsOnLaunch, let state = settings.tabsState(for: side) {
            restoredTabs = state.tabs.filter { tab in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: tab.path.path, isDirectory: &isDir)
                    && isDir.boolValue
            }
            restoredActiveID = state.activeTabID
        }
        if restoredTabs.isEmpty {
            restoredTabs = [
                PanelTab(
                    path: fallbackURL,
                    sortKey: settings.sortKey(for: side),
                    sortAscending: settings.sortAscending(for: side)
                )
            ]
            restoredActiveID = nil
        }

        let initialActiveID = restoredActiveID.flatMap { id in
            restoredTabs.contains(where: { $0.id == id }) ? id : nil
        } ?? restoredTabs[0].id
        let activeTab = restoredTabs.first(where: { $0.id == initialActiveID }) ?? restoredTabs[0]

        self.tabs = restoredTabs
        self.activeTabID = initialActiveID
        self.currentDirectory = activeTab.path
        self.backStack = activeTab.backStack
        self.forwardStack = activeTab.forwardStack
        self.sortKey = activeTab.sortKey
        self.sortAscending = activeTab.sortAscending

        // İlk açılışta da sekme durumu kaydedilsin; uygulama yeniden açıldığında
        // aynı sekmeler geri yüklenir.
        settings.setTabsState(
            PanelTabsState(tabs: restoredTabs, activeTabID: initialActiveID),
            for: side
        )
    }

    // MARK: - Türetilmiş değerler

    /// Seçili öğeler.
    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.url) }
    }

    /// Seçili ilk öğe (önizleme ve özellikler için).
    var focusedItem: FileItem? {
        selectedItems.first
    }

    /// Arama modunda mı?
    var isSearchingActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Gizli dosyalar gösteriliyor mu?
    var isShowingHiddenFiles: Bool { settings.showHiddenFiles }

    /// Üst klasöre çıkılabilir mi?
    var canGoUp: Bool {
        !FileManagerService.isRoot(currentDirectory)
    }

    /// Geri gidilebilir mi?
    var canGoBack: Bool { !backStack.isEmpty }

    /// İleri gidilebilir mi?
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Görüntülenen klasörün kullanıcıya gösterilen yolu (~ ile kısaltılır).
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if currentDirectory.path == home { return "~" }
        if currentDirectory.path.hasPrefix(home + "/") {
            return "~" + currentDirectory.path.dropFirst(home.count)
        }
        return currentDirectory.path
    }

    /// Panel başlığı.
    var title: String {
        if FileManagerService.isRoot(currentDirectory) { return currentDirectory.path }
        return currentDirectory.lastPathComponent
    }

    /// Durum çubuğunda gösterilecek öğe sayısı metni.
    var itemCountText: String {
        let folderCount = items.filter(\.isDirectory).count
        let fileCount = items.count - folderCount
        return L.t("status.itemCount", folderCount, fileCount)
    }

    /// Seçim metni.
    var selectionText: String {
        guard !selection.isEmpty else { return L.t("status.noSelection") }
        return L.t("status.selection", selection.count)
    }

    /// Seçili öğelerin toplam boyutu.
    var selectionSizeText: String {
        let selected = selectedItems
        guard !selected.isEmpty else { return "" }
        return FileSizeFormatter.string(forTotalOf: selected)
    }

    /// Boş alan metni.
    var freeSpaceText: String {
        guard let capacity = snapshot?.volumeAvailableCapacity else { return "" }
        return L.t("status.freeSpace", FileSizeFormatter.string(fromBytes: capacity))
    }

    // MARK: - Yükleme

    /// Klasörü yeniden yükler.
    /// - Parameter preserveSelection: Seçim korunsun mu?
    func reload(preserveSelection: Bool = true) async {
        loadGeneration += 1
        let generation = loadGeneration
        let target = currentDirectory

        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            // İzin/sahip/etiket sütunları görünürken ek meta veri okunur.
            let extendedColumns = settings.visibleColumns(for: side).contains {
                $0 == .permissions || $0 == .owner || $0 == .tags
            }
            let newSnapshot = try await fileManagerService.listDirectory(
                at: target,
                includeHidden: settings.showHiddenFiles,
                includeExtendedMetadata: extendedColumns
            )
            guard generation == loadGeneration else { return }

            snapshot = newSnapshot
            searchResults = nil
            searchQuery = ""
            rebuildItems()

            if preserveSelection {
                selection = selection.intersection(Set(items.map(\.url)))
            } else {
                selection = []
            }
            if let pendingRevealURL {
                self.pendingRevealURL = nil
                if let match = items.first(where: {
                    $0.url.standardizedFileURL == pendingRevealURL.standardizedFileURL
                }) {
                    selection = [match.url]
                }
            }
            selectFirstRowIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            snapshot = nil
            // Liste içeriği boşaldığında tablonun da yenilenmesi için sürüm
            // artırılır; aksi hâlde eski satırlar ekranda kalabiliyordu.
            rebuildItems()
            selection = []
            alert = UserFacingAlert(
                title: ErrorMessages.title(for: error),
                message: ErrorMessages.message(for: error)
            )
        }
    }

    /// Paneli ilk kez yükler ve izlemeyi başlatır.
    func activate() async {
        await reload(preserveSelection: false)
        updateWatcher()
        await refreshGitStatus()
    }

    /// Klasör değişikliklerini izlemeyi günceller.
    func updateWatcher() {
        guard settings.refreshAutomatically else {
            watcher.stop()
            return
        }
        watcher.start(watching: currentDirectory) { [weak self] in
            guard let self else { return }
            // Seçim korunur: aksi hâlde her dosya değişiminde imleç ilk satıra
            // dönüyor ve liste göz kırpıyordu.
            Task { await self.reload(preserveSelection: true) }
        }
    }

    // MARK: - Gezinme

    /// Yeni bir klasöre gider ve geçmişi günceller.
    /// - Parameter url: Hedef klasör.
    func navigate(to url: URL) {
        guard url.standardizedFileURL != currentDirectory.standardizedFileURL else {
            Task { await reload(preserveSelection: false) }
            return
        }
        backStack.append(currentDirectory)
        forwardStack.removeAll()
        applyDirectoryChange(to: url)
    }

    /// Üst klasöre çıkar.
    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentDirectory.deletingLastPathComponent())
    }

    /// Geçmişte geri gider.
    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentDirectory)
        applyDirectoryChange(to: previous)
    }

    /// Geçmişte ileri gider.
    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentDirectory)
        applyDirectoryChange(to: next)
    }

    /// Ev klasörüne gider.
    func goHome() {
        navigate(to: FileManager.default.homeDirectoryForCurrentUser)
        reloadAfterNavigation()
    }

    private func applyDirectoryChange(to url: URL) {
        currentDirectory = url
        settings.setPath(url, for: side)
        syncActiveTabState()
        persistTabs()
        searchTask?.cancel()
        searchResults = nil
        searchQuery = ""
        selection = []
        reloadAfterNavigation()
    }

    private func reloadAfterNavigation() {
        Task {
            await reload(preserveSelection: false)
            updateWatcher()
            await refreshGitStatus()
        }
    }

    // MARK: - Sekmeler

    /// Etkin sekmenin kayıtlı durumunu günceller.
    private func syncActiveTabState() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        tabs[index].path = currentDirectory
        tabs[index].backStack = backStack
        tabs[index].forwardStack = forwardStack
        tabs[index].sortKey = sortKey
        tabs[index].sortAscending = sortAscending
    }

    /// Sekme durumunu kalıcı hâle getirir.
    private func persistTabs() {
        settings.setTabsState(
            PanelTabsState(tabs: tabs, activeTabID: activeTabID),
            for: side
        )
    }

    /// Etkin sekmeyi kimliğine göre değiştirir.
    func activateTab(_ id: UUID) {
        guard id != activeTabID,
              let targetIndex = tabs.firstIndex(where: { $0.id == id }) else { return }

        syncActiveTabState()
        applyTab(tabs[targetIndex])
    }

    /// Yeni bir sekme açar; mevcut klasörü devralır.
    func newTab() {
        syncActiveTabState()

        let tab = PanelTab(
            path: currentDirectory,
            backStack: backStack,
            forwardStack: forwardStack,
            sortKey: sortKey,
            sortAscending: sortAscending
        )
        tabs.append(tab)
        activeTabID = tab.id
        settings.setPath(currentDirectory, for: side)
        persistTabs()
        reloadAfterNavigation()
    }

    /// Etkin sekmeyi aynı konumda çoğaltır.
    func duplicateActiveTab() {
        syncActiveTabState()
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let current = tabs[index]
        let duplicate = PanelTab(
            path: current.path,
            backStack: current.backStack,
            forwardStack: current.forwardStack,
            sortKey: current.sortKey,
            sortAscending: current.sortAscending
        )
        tabs.insert(duplicate, at: index + 1)
        activeTabID = duplicate.id
        persistTabs()
        reloadAfterNavigation()
    }

    /// Bir sekmeyi kapatır. Son sekme kapatılamaz.
    /// - Returns: Sekme kapatıldıysa `true`.
    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id }) else { return false }

        let wasActive = id == activeTabID
        if wasActive {
            syncActiveTabState()
        }
        tabs.remove(at: index)

        if wasActive {
            let nextIndex = min(index, tabs.count - 1)
            applyTab(tabs[nextIndex])
        } else {
            persistTabs()
        }
        return true
    }

    /// Etkin sekmeyi kapatır.
    @discardableResult
    func closeActiveTab() -> Bool {
        closeTab(activeTabID)
    }

    /// Etkin sekme dışındaki tüm sekmeleri kapatır.
    func closeOtherTabs() {
        guard tabs.count > 1,
              let active = tabs.first(where: { $0.id == activeTabID }) else { return }
        tabs = [active]
        persistTabs()
    }

    /// Sağdaki sekmeye geçer (son sekmeden ilk sekmeye döner).
    func nextTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let next = tabs[(index + 1) % tabs.count]
        activateTab(next.id)
    }

    /// Soldaki sekmeye geçer (ilk sekmeden son sekmeye döner).
    func previousTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let previous = tabs[(index - 1 + tabs.count) % tabs.count]
        activateTab(previous.id)
    }

    /// Sekmeyi yeni konuma taşır.
    func moveTab(id: UUID, to destinationIndex: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        let target = max(0, min(destinationIndex, tabs.count))
        tabs.insert(tab, at: target)
        persistTabs()
    }

    /// Kayıtlı sekmeyi uygular ve klasörü yeniden yükler.
    private func applyTab(_ tab: PanelTab) {
        activeTabID = tab.id
        currentDirectory = tab.path
        backStack = tab.backStack
        forwardStack = tab.forwardStack
        sortKey = tab.sortKey
        sortAscending = tab.sortAscending
        settings.setPath(tab.path, for: side)
        settings.setSort(key: sortKey, ascending: sortAscending, for: side)

        searchTask?.cancel()
        searchResults = nil
        searchQuery = ""
        selection = []
        persistTabs()
        reloadAfterNavigation()
    }

    // MARK: - Seçim

    /// Bir öğenin seçimini değiştirir.
    func toggleSelection(of url: URL) {
        if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }
    }

    /// Seçimi tek öğeye indirger.
    func select(_ url: URL) {
        selection = [url]
    }

    /// Bir öğenin bulunduğu klasöre gider, öğeyi seçer ve görünür alana kaydırır.
    /// - Parameter url: Gösterilecek dosya veya klasör.
    func reveal(_ url: URL) {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent()
        if parent.path == currentDirectory.standardizedFileURL.path {
            if let match = items.first(where: { $0.url.standardizedFileURL == standardized }) {
                selection = [match.url]
            }
            return
        }
        pendingRevealURL = standardized
        navigate(to: parent)
    }

    /// Tüm öğeleri seçer.
    func selectAll() {
        selection = Set(items.map(\.url))
    }

    /// Seçimi ters çevirir: seçili olmayanlar seçilir, seçililer bırakılır.
    func invertSelection() {
        let all = Set(items.map(\.url))
        selection = all.subtracting(selection)
    }

    /// Seçimi temizler.
    func clearSelection() {
        selection.removeAll()
    }

    /// Seçimi topluca günceller (liste görünümünün bağlaması için).
    func setSelection(_ urls: Set<URL>) {
        selection = urls
    }

    private func selectFirstRowIfNeeded() {
        guard selection.isEmpty else { return }
        if let first = items.first {
            selection = [first.url]
        }
    }

    // MARK: - Sıralama

    /// Sıralama sütununu değiştirir; aynı sütuna basılırsa yön ters çevrilir.
    func sort(by key: FileSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
        settings.setSort(key: sortKey, ascending: sortAscending, for: side)
        syncActiveTabState()
        persistTabs()
        rebuildItems()
    }

    // MARK: - Arama

    /// Arama metnini günceller ve gecikmeli aramayı başlatır.
    func updateSearchQuery(_ query: String) {
        searchQuery = query
    }

    /// Aramayı sonlandırır ve normal listeye döner.
    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchResults = nil
        searchReachedLimit = false
        isSearching = false
        if !searchQuery.isEmpty {
            searchQuery = ""
        }
        rebuildItems()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            searchResults = nil
            searchReachedLimit = false
            isSearching = false
            rebuildItems()
            return
        }

        isSearching = true
        searchResults = nil

        searchTask = Task { [weak self] in
            // Kullanıcı yazmayı sürdürürse gereksiz aramaları engelliyoruz.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }

            let root = self.currentDirectory
            let includeHidden = self.settings.showHiddenFiles
            let outcome = await self.searchService.search(root: root, query: trimmed, includeHidden: includeHidden)
            guard !Task.isCancelled, root == self.currentDirectory else { return }

            self.searchResults = outcome.items
            self.searchReachedLimit = outcome.reachedLimit
            self.isSearching = false
            self.selection = self.selection.intersection(Set(outcome.items.map(\.url)))
            self.rebuildItems()
            self.selectFirstRowIfNeeded()
        }
    }

    // MARK: - Git

    /// Geçerli klasörün Git durumunu yeniler.
    ///
    /// Git entegrasyonu kapalıysa hiçbir süreç başlatılmaz; bu, panel
    /// geçişlerinde görülen takılmaların başlıca kaynağıydı.
    func refreshGitStatus() async {
        guard settings.gitIntegrationEnabled else {
            gitStatus = nil
            return
        }
        let directory = currentDirectory
        let status = await gitService.status(for: directory)
        guard directory == currentDirectory else { return }
        gitStatus = status
    }

    // MARK: - İç yardımcılar

    private func rebuildItems() {
        let base = searchResults ?? snapshot?.items ?? []
        items = FileItem.sorted(
            base,
            by: sortKey,
            ascending: sortAscending,
            foldersFirst: settings.foldersFirst
        )
        revision &+= 1
    }
}

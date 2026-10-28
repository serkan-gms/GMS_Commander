//
//  MainViewModel.swift
//  GMS_Commander
//
//  İki paneli, etkin paneli ve tüm dosya işlemlerini (kopyala, taşı, sil,
//  yeniden adlandır, yeni klasör) yöneten ana görünüm modeli.
//  İşlemler iptal edilebilir; ilerleme ve çakışma kararları arayüze yayınlanır.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Bildirimler

extension Notification.Name {
    /// Panelin yol düzenleme alanını açma isteği.
    static let beginPathEditing = Notification.Name("gms.beginPathEditing")
}

extension Notification {
    /// Yol düzenleme bildiriminde panel tarafını taşıyan anahtar.
    static let beginPathEditingSideKey = "side"
}

// MARK: - Yardımcı istek tipleri

/// Kopyalama/taşıma sırasında kullanıcıya sorulan çakışma isteği.
/// Arayüz, karar verebilmek için kaynak ve hedefin tür, boyut ve tarih
/// bilgilerini de gösterir.
struct ConflictRequest: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let destinationURL: URL
    let sourceName: String
    let destinationName: String
    let destinationDirectory: String
    let sourceIsDirectory: Bool
    let destinationIsDirectory: Bool
    let sourceSize: Int64?
    let destinationSize: Int64?
    let sourceDate: Date?
    let destinationDate: Date?
    /// Karar ve "tümüne uygula" seçeneğini ileten kapanış.
    let resolve: (ConflictDecision, Bool) -> Void
}

/// Çakışma penceresinden dönen karar.
struct ConflictResolution {
    let decision: ConflictDecision
    let applyToAll: Bool
}

/// Kuyruğa alınmış bir kopyalama/taşıma isteği.
struct QueuedTransfer {
    let mode: TransferMode
    let sources: [URL]
    let destinationDirectory: URL
}

/// Kullanıcı onayını bekleyen kopyalama/taşıma isteği.
struct TransferConfirmationRequest: Identifiable {
    let id = UUID()
    let mode: TransferMode
    let sources: [URL]
    let destinationDirectory: URL

    var title: String {
        L.t(mode == .copy ? "transfer.confirm.copy.title" : "transfer.confirm.move.title")
    }

    var message: String {
        L.t(
            "transfer.confirm.message",
            sources.count,
            destinationDirectory.path
        )
    }

    var action: String {
        L.t(mode == .copy ? "transfer.confirm.copy.action" : "transfer.confirm.move.action")
    }
}

/// Kalıcı silme onayı isteği.
struct DeletionRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    let isPermanent: Bool

    var title: String {
        isPermanent ? L.t("delete.confirm.title") : L.t("trash.confirm.title")
    }

    var message: String {
        L.t(isPermanent ? "delete.confirm.message" : "trash.confirm.message", urls.count)
    }

    var action: String {
        L.t(isPermanent ? "delete.confirm.action" : "trash.confirm.action")
    }
}

/// Yeniden adlandırma isteği.
struct RenameRequest: Identifiable {
    let id = UUID()
    let item: FileItem
    var suggestedName: String
}

/// Görüntüleyici/düzenleyici isteği.
struct FilePresentationRequest: Identifiable {
    let id = UUID()
    let url: URL
}

/// Panoya yapıştırırken hedef klasörü belirler.
///
/// Kopyalanan öğeler etkin panelin klasöründeyse aynı klasöre yapıştırmak
/// anlamsızdır; bu durumda hedef etkin olmayan panel olur. Panoya başka bir
/// uygulamadan alınmış yollar varsa hedef her zaman etkin panelin klasörüdür.
struct PasteTargetResolver {
    /// Etkin ve etkin olmayan panel klasörlerine göre hedefi döndürür.
    /// - Parameters:
    ///   - activeDirectory: Etkin panelin klasörü.
    ///   - inactiveDirectory: Etkin olmayan panelin klasörü.
    ///   - sources: Panodaki kaynak öğeler.
    static func destination(
        activeDirectory: URL,
        inactiveDirectory: URL,
        sources: [URL]
    ) -> URL {
        guard !sources.isEmpty else { return activeDirectory }

        let activePath = activeDirectory.standardizedFileURL.path
        let allSourcesInActiveDirectory = sources.allSatisfy { source in
            source.deletingLastPathComponent().standardizedFileURL.path == activePath
        }
        return allSourcesInActiveDirectory ? inactiveDirectory : activeDirectory
    }
}

/// Toplu yeniden adlandırma isteği.
struct BatchRenameRequest: Identifiable {
    let id = UUID()
    /// Yeniden adlandırılacak dosyalar.
    let files: [URL]
}

/// SHA-256 hesaplama isteği.
struct HashRequest: Identifiable {
    let id = UUID()
    /// Özeti hesaplanacak dosyalar.
    let urls: [URL]
}

/// Arşiv tarayıcısı isteği.
struct ArchiveBrowserRequest: Identifiable {
    let id = UUID()
    /// Açılacak arşiv dosyası.
    let archiveURL: URL
    /// Çıkarma hedefi.
    let destinationDirectory: URL
}

// MARK: - Ana görünüm modeli

/// Uygulamanın ana görünüm modeli.
@MainActor
final class MainViewModel: ObservableObject {
    // MARK: - Alt nesneler

    /// Ayar deposu.
    let settings: SettingsStore

    /// Sol panel.
    let leftPanel: FilePanelViewModel

    /// Sağ panel.
    let rightPanel: FilePanelViewModel

    /// Sık kullanılan klasörler.
    let favorites: FavoritesViewModel

    // MARK: - Yayınlanan durum

    /// Etkin panel tarafı.
    @Published private(set) var activeSide: PanelSide = .left

    /// Süren işlem bilgisi; `nil` ise işlem yok.
    @Published private(set) var operationProgress: OperationProgress?

    /// İşlem sürüyor mu?
    @Published private(set) var isOperating = false

    /// Süren aktarım duraklatıldı mı?
    @Published private(set) var isOperationPaused = false

    /// Kuyrukta bekleyen aktarım sayısı.
    @Published private(set) var queuedOperationCount = 0

    /// Son işlemin hızı (bayt/saniye); ilerleme penceresinde gösterilir.
    @Published private(set) var transferBytesPerSecond: Double = 0

    /// Yanıt bekleyen çakışma isteği.
    @Published var pendingConflict: ConflictRequest?

    /// Kalıcı silme onayı.
    @Published var deletionRequest: DeletionRequest?

    /// Kopyalama/taşıma için hedef klasör onayı.
    @Published var transferConfirmation: TransferConfirmationRequest?

    /// Yeniden adlandırma isteği.
    @Published var renameRequest: RenameRequest?

    /// Özellikleri gösterilecek öğe.
    @Published var propertiesItem: FileItem?

    /// Özellik bilgisi (yüklenirken `nil`).
    @Published var properties: FileProperties?

    /// Gösterilecek bildirim/uyarı.
    @Published var alert: UserFacingAlert?

    /// Ayarlar penceresi görünür mü?
    @Published var isShowingSettings = false

    /// Kısayollar penceresi görünür mü?
    @Published var isShowingHelp = false

    /// Gelişmiş arama penceresi görünür mü?
    @Published var isShowingAdvancedSearch = false

    /// Klasör karşılaştırma penceresi görünür mü?
    @Published var isShowingFolderCompare = false

    /// Desene göre seçim penceresi görünür mü?
    @Published var isShowingPatternSelection = false

    /// Açık SHA-256 hesaplama isteği.
    @Published var hashRequest: HashRequest?

    /// Açık arşiv tarayıcısı isteği.
    @Published var archiveBrowser: ArchiveBrowserRequest?

    /// Çöp Kutusu geri yükleme penceresi görünür mü?
    @Published var isShowingTrashRestore = false

    /// Açık toplu yeniden adlandırma isteği.
    @Published var batchRenameRequest: BatchRenameRequest?

    /// Açık dosya görüntüleyici (F3).
    @Published var viewerFile: FilePresentationRequest?
    /// Açık dosya düzenleyici (F4).
    @Published var editorFile: FilePresentationRequest?

    /// Arama alanına odaklanması istenen panel.
    @Published var searchFocusSide: PanelSide?

    /// Bir pencere (sheet) açık mı? Yalın tuşlar bu sırada dosya listesine yönlendirilmez.
    var isModalPresented: Bool {
        isShowingSettings || isShowingHelp || isShowingAdvancedSearch
            || isShowingFolderCompare || isShowingPatternSelection || hashRequest != nil
            || renameRequest != nil || propertiesItem != nil || pendingConflict != nil
            || deletionRequest != nil || transferConfirmation != nil || alert != nil
            || archiveBrowser != nil || isShowingTrashRestore
            || batchRenameRequest != nil
            || viewerFile != nil || editorFile != nil
    }

    // MARK: - Gizli durum

    private let fileManagerService = FileManagerService()
    private let copyService = FileCopyService()
    private let moveService = FileMoveService()
    private let zipArchiveService = ZipArchiveService()

    private var operationTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Süren aktarımın duraklatma/iptal denetimi.
    private var transferControl: TransferControl?
    /// Sırayla yürütülecek aktarımlar.
    private var pendingTransfers: [QueuedTransfer] = []
    /// Hız hesabı için son örnek zamanı ve bayt değeri.
    private var speedSampleDate = Date()
    private var speedSampleBytes: Int64 = 0

    /// Panoya alınan dosyalar ve kesme bilgisi.
    private var clipboardSources: [URL] = []
    private var clipboardMode: TransferMode = .copy

    // MARK: - Başlatma

    init(settings: SettingsStore, favorites: FavoritesViewModel = .shared) {
        self.settings = settings
        self.favorites = favorites
        self.leftPanel = FilePanelViewModel(side: .left, settings: settings)
        self.rightPanel = FilePanelViewModel(side: .right, settings: settings)

        // Panel değişikliklerini ana modele yansıtarak araç çubuğu ve durum
        // çubuğunun güncel kalmasını sağlıyoruz.
        leftPanel.objectWillChange
            .merge(with: rightPanel.objectWillChange)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        favorites.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel erişimi

    /// Etkin panel.
    var activePanel: FilePanelViewModel {
        activeSide == .left ? leftPanel : rightPanel
    }

    /// Etkin olmayan panel.
    var inactivePanel: FilePanelViewModel {
        activeSide == .left ? rightPanel : leftPanel
    }

    /// Panelleri tarafa göre döndürür.
    func panel(for side: PanelSide) -> FilePanelViewModel {
        side == .left ? leftPanel : rightPanel
    }

    /// İlk yüklemeyi yapar.
    func start() async {
        await leftPanel.activate()
        await rightPanel.activate()
        favorites.refreshMountedVolumes()
    }

    /// Etkin paneli değiştirir.
    func activate(side: PanelSide) {
        guard activeSide != side else { return }
        activeSide = side
        // Git durumu her panel geçişinde yeniden hesaplanmaz: süreç başlatmak
        // panel geçişini yavaşlatıyordu. Yalnızca henüz bilinmiyorsa sorgulanır.
        if settings.gitIntegrationEnabled, activePanel.gitStatus == nil {
            Task { await activePanel.refreshGitStatus() }
        }
    }

    /// Etkin paneli diğer panele çevirir.
    func toggleActivePanel() {
        activate(side: activeSide.opposite)
    }

    /// Etkin panelin yol çubuğunda elle düzenleme kipini açar.
    /// Bildirim kullanılır: yayınlanan durum, görünüm yeniden kurulurken
    /// isteği kaybedebiliyordu.
    func beginPathEditing() {
        NotificationCenter.default.post(
            name: .beginPathEditing,
            object: nil,
            userInfo: [Notification.beginPathEditingSideKey: activeSide]
        )
    }

    /// Etkin panelde yeni sekme açar.
    func newTab() {
        activePanel.newTab()
    }

    /// Etkin panelde etkin sekmeyi kapatır.
    func closeActiveTab() {
        activePanel.closeActiveTab()
    }

    /// Etkin panelde sağdaki sekmeye geçer.
    func nextTab() {
        activePanel.nextTab()
    }

    /// Etkin panelde soldaki sekmeye geçer.
    func previousTab() {
        activePanel.previousTab()
    }

    /// Etkin panelde etkin sekmeyi çoğaltır.
    func duplicateActiveTab() {
        activePanel.duplicateActiveTab()
    }

    /// Etkin panelde diğer sekmeleri kapatır.
    func closeOtherTabs() {
        activePanel.closeOtherTabs()
    }

    /// İki panelin klasörlerini karşılıklı olarak değiştirir.
    func swapPanels() {
        guard !isOperating else { return }
        let leftPath = leftPanel.currentDirectory
        let rightPath = rightPanel.currentDirectory
        leftPanel.navigate(to: rightPath)
        rightPanel.navigate(to: leftPath)
    }

    /// Etkin panelin görünüm modunu sırayla değiştirir.
    func cycleViewMode() {
        let current = settings.viewMode(for: activeSide)
        let all = PanelViewMode.allCases
        guard let index = all.firstIndex(of: current) else { return }
        settings.setViewMode(all[(index + 1) % all.count], for: activeSide)
        refreshActivePanel()
    }

    /// Bir sütunun görünürlüğünü değiştirir.
    func toggleColumn(_ column: PanelColumn, for side: PanelSide) {
        guard column != .name else { return }
        var columns = settings.visibleColumns(for: side)
        if let index = columns.firstIndex(of: column) {
            columns.remove(at: index)
        } else {
            // Sütunları kanonik sıraya göre ekle.
            columns.append(column)
            let order = PanelColumn.allCases
            columns.sort { lhs, rhs in
                (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
            }
        }
        settings.setVisibleColumns(columns, for: side)
        Task { await panel(for: side).reload(preserveSelection: true) }
    }

    /// Belirli bir panel sütununun genişliğini ayarlar ve kalıcılaştırır.
    func setColumnWidth(_ width: Double, column: PanelColumn, for side: PanelSide) {
        var widths = settings.columnWidths(for: side)
        widths[column.rawValue] = width
        settings.setColumnWidths(widths, for: side)
    }

    /// İki paneli de yeniler.
    func refreshAll() {
        favorites.refreshMountedVolumes()
        Task {
            await leftPanel.reload(preserveSelection: true)
            await rightPanel.reload(preserveSelection: true)
        }
    }

    /// Etkin paneli yeniler.
    func refreshActivePanel() {
        favorites.refreshMountedVolumes()
        Task {
            await activePanel.reload(preserveSelection: true)
            await activePanel.refreshGitStatus()
        }
    }

    // MARK: - Görünüm ayarları

    /// Gizli dosyaların gösterimini açar/kapatır.
    func toggleHiddenFiles() {
        settings.showHiddenFiles.toggle()
        refreshAll()
    }

    /// Klasörlerin üstte kalmasını açar/kapatır.
    func toggleFoldersFirst() {
        settings.foldersFirst.toggle()
        refreshAll()
    }

    // MARK: - Seçim

    /// Etkin paneldeki tüm öğeleri seçer.
    func selectAll() {
        if forwardToTextEditor(#selector(NSText.selectAll(_:))) { return }
        activePanel.selectAll()
    }

    /// Seçimi temizler.
    func deselectAll() {
        activePanel.clearSelection()
    }

    /// Desene göre seçim penceresini açar.
    func showPatternSelection() {
        guard !activePanel.items.isEmpty else { return }
        isShowingPatternSelection = true
    }

    /// Desene göre seçim sonucunu etkin panele uygular.
    /// - Parameters:
    ///   - urls: Eşleşen öğeler.
    ///   - mode: Seçimi değiştirme biçimi.
    func applyPatternSelection(_ urls: Set<URL>, mode: SelectionApplyMode) {
        switch mode {
        case .replace:
            activePanel.setSelection(urls)
        case .add:
            activePanel.setSelection(activePanel.selection.union(urls))
        case .remove:
            activePanel.setSelection(activePanel.selection.subtracting(urls))
        }
    }

    /// Etkin panelde seçimi ters çevirir.
    func invertSelection() {
        activePanel.invertSelection()
    }

    /// Etkin panelde seçili dosya adresleri (görüntülenme sırasına göre).
    private var selectedURLs: [URL] {
        let panel = activePanel
        return panel.items.filter { panel.selection.contains($0.url) }.map(\.url)
    }

    // MARK: - Açma ve gezinme

    /// Etkin panelde seçili öğeyi açar.
    func openSelection() {
        guard let item = activePanel.focusedItem else { return }
        open(item)
    }

    /// Bir öğeyi açar: klasörse panele girer, dosyaysa varsayılan uygulamayla açar.
    func open(_ item: FileItem) {
        if item.isDirectory && !item.isSymbolicLink {
            activePanel.navigate(to: item.url)
        } else if item.isSymbolicLink && item.isDirectory {
            activePanel.navigate(to: item.url)
        } else if !item.isDirectory, ArchiveFormat.detect(item.url) != nil {
            openArchive(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Arşivi dahili tarayıcıda açar; çıkarma hedefi pasif panelin klasörüdür.
    /// - Parameter url: ZIP/TAR/TAR.GZ dosyası.
    func openArchive(_ url: URL) {
        guard ArchiveFormat.detect(url) != nil else {
            alert = UserFacingAlert(
                title: L.t("archive.title"),
                message: L.t("archive.unsupported", url.lastPathComponent)
            )
            return
        }
        archiveBrowser = ArchiveBrowserRequest(
            archiveURL: url,
            destinationDirectory: inactivePanel.currentDirectory
        )
    }

    /// Etkin panelde seçili dosyayı dahili görüntüleyicide açar (F3).
    func openViewer() {
        guard let item = activePanel.focusedItem else { return }
        if item.isDirectory {
            QuickLookCoordinator.shared.show([item.url])
            return
        }
        viewerFile = FilePresentationRequest(url: item.url)
    }

    /// Etkin panelde seçili dosyayı dahili düzenleyicide açar (F4).
    func openEditor() {
        guard let item = activePanel.focusedItem else { return }
        guard !item.isDirectory else {
            alert = UserFacingAlert(
                title: L.t("editor.title"),
                message: L.t("editor.folderNotEditable")
            )
            return
        }
        editorFile = FilePresentationRequest(url: item.url)
    }

    /// Görüntüleyici/düzenleyici kapandıktan sonra etkin paneli yeniler.
    func refreshAfterEditing() {
        Task { await activePanel.reload(preserveSelection: true) }
    }

    /// Etkin panelde seçili arşivi tarayıcıda açar.
    func openSelectedArchive() {
        guard let url = selectedURLs.first(where: { ArchiveFormat.detect($0) != nil }) else {
            alert = UserFacingAlert(
                title: L.t("archive.title"),
                message: L.t("archive.unsupportedSelection")
            )
            return
        }
        openArchive(url)
    }


    /// Etkin panelde üst klasöre çıkar.
    func goUp() { activePanel.goUp() }

    /// Etkin panelde geri gider.
    func goBack() { activePanel.goBack() }

    /// Etkin panelde ileri gider.
    func goForward() { activePanel.goForward() }

    // MARK: - Paneller arası yol aktarımı

    /// Bir panelin açık klasör yolunu karşı panele aktarır.
    ///
    /// Aktiflik değişmez: komut, yolu gönderen panelin etkin kalmasını sağlar.
    /// - Parameter side: Yolu gönderen panel.
    func transferPath(from side: PanelSide) {
        let target = side.opposite
        panel(for: target).navigate(to: panel(for: side).currentDirectory)
    }

    /// Seçilen klasörü karşı panelde açar ve o paneli etkinleştirir.
    /// - Parameters:
    ///   - item: Açılacak öğe; yalnızca klasörler kabul edilir.
    ///   - side: Öğenin seçildiği panel.
    /// - Returns: Klasör açıldıysa `true`.
    @discardableResult
    func openInOtherPanel(_ item: FileItem, from side: PanelSide) -> Bool {
        guard item.isDirectory else { return false }
        let target = side.opposite
        activate(side: target)
        panel(for: target).navigate(to: item.url)
        return true
    }

    /// Etkin panelde ev klasörüne gider.
    func goHome() { activePanel.goHome() }

    /// Etkin paneldeki geçerli klasörü Finder'da gösterir.
    func revealCurrentDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([activePanel.currentDirectory])
    }

    /// Seçili öğeleri Finder'da gösterir.
    func revealSelection() {
        let urls = selectedURLs
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [activePanel.currentDirectory] : urls)
    }

    /// Seçili öğeyi Quick Look ile önizler.
    func quickLookSelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        QuickLookCoordinator.shared.toggle(urls)
    }

    /// Seçili öğeleri Quick Look'ta açar; görünür önizlemeyi kapatmaz.
    func previewSelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else {
            alert = UserFacingAlert(title: L.t("quickLook.title"), message: L.t("quickLook.noSelection"))
            return
        }
        QuickLookCoordinator.shared.show(urls)
    }

    /// Etkin paneli verilen yol metnine göre yönlendirir.
    /// - Parameter path: "~" ile başlayabilen mutlak yol.
    /// - Returns: Yol geçerli bir klasörse `true`.
    @discardableResult
    func navigateActivePanel(toPath path: String) -> Bool {
        navigatePanel(side: activeSide, toPath: path)
    }

    /// Belirtilen paneli yol metnine göre yönlendirir.
    @discardableResult
    func navigatePanel(side: PanelSide, toPath path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded: String
        if trimmed == "~" {
            expanded = home
        } else if trimmed.hasPrefix("~/") {
            expanded = home + String(trimmed.dropFirst())
        } else {
            expanded = trimmed
        }

        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        activate(side: side)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            alert = UserFacingAlert(
                title: L.t("error.title.path"),
                message: L.t("error.pathNotFound", trimmed)
            )
            return false
        }

        panel(for: side).navigate(to: url)
        return true
    }

    // MARK: - Sık kullanılanlar

    /// Sık kullanılan klasörü panele uygular.
    /// - Parameters:
    ///   - item: Açılacak klasör.
    ///   - side: Hedef panel; `nil` ise etkin panel kullanılır.
    func openFavorite(_ item: FavoriteFolder, side: PanelSide? = nil) {
        let target = side ?? activeSide
        let panel = panel(for: target)
        guard FileManager.default.fileExists(atPath: item.path) else {
            alert = UserFacingAlert(
                title: L.t("error.title.path"),
                message: L.t("error.pathNotFound", item.path)
            )
            favorites.remove(id: item.id)
            return
        }
        if activeSide != target { activate(side: target) }
        if item.isDirectory && !item.isApplication {
            panel.navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Etkin paneldeki seçili dosya ve klasörleri hızlı erişime ekler.
    @discardableResult
    func addSelectionToFavorites(groupID: UUID? = nil) -> Int {
        selectedURLs.reduce(into: 0) { count, url in
            if favorites.add(url: url, to: groupID ?? favorites.suggestedGroupID(for: url)) { count += 1 }
        }
    }

    /// Bir `.app` paketini doğrudan Uygulamalar favori bölümüne ekler.
    @discardableResult
    func addApplicationToFavorites(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        return favorites.add(url: url, to: favorites.suggestedGroupID(for: url))
    }

    /// Etkin panelin klasörünü hızlı erişime ekler.
    @discardableResult
    func addActiveDirectoryToFavorites(groupID: UUID? = nil) -> Bool {
        let url = activePanel.currentDirectory
        return favorites.add(url: url, to: groupID ?? favorites.suggestedGroupID(for: url))
    }

    /// Seçili öğeleri kullanıcıya hedef konum seçtirerek ZIP arşivine ekler.
    func compressSelection() {
        let sources = selectedURLs
        guard !sources.isEmpty else {
            alert = UserFacingAlert(title: L.t("archive.title"), message: L.t("archive.noSelection"))
            return
        }
        guard !isOperating else {
            alert = UserFacingAlert(title: L.t("error.title.busy"), message: L.t("error.busy"))
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = L.t("archive.title")
        savePanel.nameFieldStringValue = "\(sources[0].lastPathComponent)\(sources.count > 1 ? "-\(sources.count)" : "").zip"
        savePanel.directoryURL = activePanel.currentDirectory
        // ZIP varsayılandır; kullanıcı adı ".tar" veya ".tar.gz" olarak
        // değiştirerek diğer biçimleri de seçebilir.
        savePanel.allowedContentTypes = [.zip, .gzip]
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }

        isOperating = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isOperating = false
                self.operationTask = nil
            }
            do {
                try await self.zipArchiveService.compress(sources: sources, to: destination)
                await self.activePanel.reload(preserveSelection: true)
            } catch is CancellationError {
                return
            } catch {
                self.alert = UserFacingAlert(
                    title: L.t("archive.failedTitle"),
                    message: ErrorMessages.message(for: error)
                )
            }
        }
    }

    /// Seçili öğeler için toplu yeniden adlandırma penceresini açar.
    func beginBatchRename() {
        let urls = selectedURLs
        guard !urls.isEmpty else {
            alert = UserFacingAlert(
                title: L.t("batch.title"),
                message: L.t("batch.noSelection")
            )
            return
        }
        batchRenameRequest = BatchRenameRequest(files: urls)
    }

    /// Seçili dosyalar için SHA-256 hesaplama penceresini açar.
    func beginHashCalculation() {
        let urls = selectedURLs.filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return !isDirectory
        }
        guard !urls.isEmpty else {
            alert = UserFacingAlert(
                title: L.t("hash.title"),
                message: L.t("hash.noFiles")
            )
            return
        }
        hashRequest = HashRequest(urls: urls)
    }

    /// İki panelin klasörlerini karşılaştırma penceresini açar.
    func showFolderCompare() {
        guard !isOperating else { return }
        isShowingFolderCompare = true
    }

    /// Karşılaştırma sonucundaki yolu ilgili panelde gösterir.
    /// - Parameters:
    ///   - url: Gösterilecek dosya veya klasör.
    ///   - side: Panel tarafı.
    func revealCompareItem(_ url: URL, side: PanelSide) {
        activate(side: side)
        panel(for: side).reveal(url)
    }

    /// Toplu yeniden adlandırma sonrasında panelleri yeniler.
    func refreshAfterBatchRename() {
        Task {
            await leftPanel.reload(preserveSelection: true)
            await rightPanel.reload(preserveSelection: true)
        }
    }

    /// Çöp Kutusu geri yükleme penceresini açar.
    func showTrashRestore() {
        isShowingTrashRestore = true
    }

    /// Çöp Kutusu işleminden sonra iki paneli de yeniler.
    func refreshAfterTrashOperation() {
        Task {
            await leftPanel.reload(preserveSelection: true)
            await rightPanel.reload(preserveSelection: true)
        }
    }

    /// Arşiv çıkarma sonrasında iki paneli de yeniler.
    func refreshAfterArchiveExtraction() {
        Task {
            await leftPanel.reload(preserveSelection: true)
            await rightPanel.reload(preserveSelection: true)
        }
    }

    /// Sık kullanılanlar kenar çubuğunu gösterir/gizler.
    func toggleFavoritesSidebar() {
        settings.showFavoritesSidebar.toggle()
    }

    /// Etkin panelin arama alanına odaklanır.
    func focusSearch() {
        searchFocusSide = activeSide
    }

    /// Etkin panelin klasöründen başlayan gelişmiş arama penceresini açar.
    func showAdvancedSearch() {
        guard !isOperating else { return }
        isShowingAdvancedSearch = true
    }

    /// Gelişmiş arama sonucunu etkin panelde gösterir.
    /// - Parameter item: Gösterilecek öğe.
    func revealSearchResult(_ item: FileItem) {
        activePanel.reveal(item.url)
    }

    /// Seçili öğeleri kullanıcıya uygulama seçtirerek açar.
    func openSelectionWithApplication() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = L.t("openWith.title")
        panel.prompt = L.t("openWith.prompt")
        panel.message = L.t("openWith.message")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }

        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.alert = UserFacingAlert(
                    title: ErrorMessages.title(for: error),
                    message: ErrorMessages.message(for: error)
                )
            }
        }
    }

    // MARK: - Pano işlemleri

    /// Yol alanı gibi bir metin düzenleyici etkinse standart metin komutunu
    /// ona yönlendirir. Menüdeki ⌘C/⌘V/⌘A kısayolları aksi hâlde metin
    /// alanı yerine dosya işlemlerini çalıştırıyordu.
    private func forwardToTextEditor(_ action: Selector) -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return editor.tryToPerform(action, with: nil)
    }

    /// Seçili öğeleri panoya kopyalar.
    func copySelection() {
        if forwardToTextEditor(#selector(NSText.copy(_:))) { return }
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        clipboardSources = urls
        clipboardMode = .copy
        writeToPasteboard(urls)
    }

    /// Seçili öğeleri panoya keser.
    func cutSelection() {
        if forwardToTextEditor(#selector(NSText.cut(_:))) { return }
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        clipboardSources = urls
        clipboardMode = .move
        writeToPasteboard(urls)
    }

    /// Panodaki dosyaları hedef panelin geçerli klasörüne aktarır.
    func paste() {
        if forwardToTextEditor(#selector(NSText.paste(_:))) { return }
        guard !isOperating else {
            alert = UserFacingAlert(title: L.t("error.title.busy"), message: L.t("error.busy"))
            return
        }

        let urls = readFileURLsFromPasteboard()
        guard !urls.isEmpty else {
            alert = UserFacingAlert(title: L.t("paste.empty.title"), message: L.t("paste.empty.message"))
            return
        }

        let mode: TransferMode = (clipboardMode == .move && Set(urls) == Set(clipboardSources)) ? .move : .copy
        let destination = PasteTargetResolver.destination(
            activeDirectory: activePanel.currentDirectory,
            inactiveDirectory: inactivePanel.currentDirectory,
            sources: urls
        )
        transfer(mode: mode, sources: urls, to: destination)
    }

    /// Etkin paneldeki seçili öğelerin yolunu metin olarak kopyalar.
    func copyPathSelection() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let text = urls.map(\.path).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func writeToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    private func readFileURLsFromPasteboard() -> [URL] {
        let pasteboard = NSPasteboard.general
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return objects ?? []
    }

    // MARK: - Aktarım (kopyala/taşı)

    /// Etkin paneldeki seçili öğeleri diğer panele kopyalamak için onay ister.
    func copyToOtherPanel() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        startTransfer(mode: .copy, sources: urls)
    }

    /// Etkin paneldeki seçili öğeleri diğer panele taşımak için onay ister.
    func moveToOtherPanel() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        startTransfer(mode: .move, sources: urls)
    }

    /// Etkin paneldeki seçili öğeleri diğer panele aktarmak için onay ister.
    /// - Parameters:
    ///   - mode: Kopyala veya taşı.
    ///   - sources: Kaynak dosya ve klasörler.
    func startTransfer(mode: TransferMode, sources: [URL]) {
        transfer(mode: mode, sources: sources, to: inactivePanel.currentDirectory)
    }

    /// Belirtilen klasöre aktarım için kullanıcı onayı ister.
    /// - Parameters:
    ///   - mode: Kopyala veya taşı.
    ///   - sources: Kaynak dosya ve klasörler.
    ///   - destinationDirectory: Hedef klasör.
    func transfer(mode: TransferMode, sources: [URL], to destinationDirectory: URL) {
        guard !sources.isEmpty else { return }
        transferConfirmation = TransferConfirmationRequest(
            mode: mode,
            sources: sources,
            destinationDirectory: destinationDirectory
        )
    }

    /// Kullanıcının onayladığı aktarımı kuyruğa ekler veya başlatır.
    func confirmTransfer() {
        guard let request = transferConfirmation else { return }
        transferConfirmation = nil
        let queued = QueuedTransfer(
            mode: request.mode,
            sources: request.sources,
            destinationDirectory: request.destinationDirectory
        )

        if isOperating {
            // Büyük işlemler birbirini kesmesin; sırayla ve veri kaybı olmadan
            // yürütülmek üzere kuyruğa alınır.
            pendingTransfers.append(queued)
            queuedOperationCount = pendingTransfers.count
            return
        }

        beginTransfer(queued)
    }

    /// Aktarımı gerçekten başlatır (kuyruk boşken çağrılır).
    private func beginTransfer(_ transfer: QueuedTransfer) {
        let control = TransferControl()
        transferControl = control
        isOperationPaused = false
        transferBytesPerSecond = 0
        speedSampleDate = Date()
        speedSampleBytes = 0
        isOperating = true
        operationTask = Task { [weak self] in
            await self?.runTransfer(
                mode: transfer.mode,
                sources: transfer.sources,
                destinationDirectory: transfer.destinationDirectory,
                control: control
            )
        }
    }

    /// Kuyruktaki bir sonraki aktarımı başlatır; yoksa işlem durumunu kapatır.
    private func finishTransferAndStartNext() {
        guard let next = pendingTransfers.first else {
            isOperating = false
            operationTask = nil
            transferControl = nil
            queuedOperationCount = 0
            return
        }
        pendingTransfers.removeFirst()
        queuedOperationCount = pendingTransfers.count
        beginTransfer(next)
    }

    /// Kuyrukta bekleyen tüm aktarımları iptal eder.
    func cancelQueuedOperations() {
        pendingTransfers.removeAll()
        queuedOperationCount = 0
    }

    /// Süren işlemi duraklatır.
    func pauseOperation() {
        guard isOperating else { return }
        transferControl?.pause()
        isOperationPaused = true
    }

    /// Duraklatılmış işlemi sürdürür.
    func resumeOperation() {
        guard isOperating else { return }
        transferControl?.resume()
        isOperationPaused = false
    }

    /// Süren işlemi iptal eder. Kuyruktaki işlemler korunur.
    func cancelOperation() {
        if let pending = pendingConflict {
            pendingConflict = nil
            pending.resolve(.cancel, false)
        }
        transferControl?.cancel()
        operationTask?.cancel()
        isOperationPaused = false
    }

    /// Çakışma isteğini yanıtlar.
    /// - Parameters:
    ///   - decision: Seçilen çakışma kararı.
    ///   - applyToAll: Aynı karar bu aktarımdaki tüm çakışmalara uygulanacak mı?
    func resolveConflict(_ decision: ConflictDecision, applyToAll: Bool = false) {
        guard let pending = pendingConflict else { return }
        pendingConflict = nil
        pending.resolve(decision, applyToAll)
    }

    /// Çakışma çözümlerinde "tümüne uygula" için kullanılan karar.
    private var applyToAllConflictDecision: ConflictDecision?

    private func runTransfer(
        mode: TransferMode,
        sources: [URL],
        destinationDirectory: URL,
        control: TransferControl
    ) async {
        let kind = mode.operationKind
        applyToAllConflictDecision = nil

        // Boyut tahmini ilerleme çubuğunun toplamını belirler.
        var perSourceBytes: [URL: Int64] = [:]
        var totalBytes: Int64 = 0
        var totalItems = 0
        for source in sources {
            let estimate = await copyService.estimate(source: source)
            perSourceBytes[source] = estimate.bytes
            totalBytes += estimate.bytes
            totalItems += max(estimate.itemCount, 1)
        }

        var progress = OperationProgress(
            kind: kind,
            currentItemName: "",
            completedItems: 0,
            totalItems: totalItems,
            completedBytes: 0,
            totalBytes: totalBytes
        )
        operationProgress = progress

        var failures: [FileOperationFailure] = []
        var completedCount = 0
        var wasCancelled = false

        for source in sources {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            progress.currentItemName = source.lastPathComponent
            progress.completedItems = completedCount
            operationProgress = progress

            var destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)

            if FileManagerService.isSameLocation(source, destination) {
                failures.append(
                    FileOperationFailure(
                        url: source,
                        message: L.t("error.sameLocation", source.lastPathComponent, destination.path)
                    )
                )
                continue
            }

            // Bir klasörü kendi içine (veya alt klasörüne) kopyalamak/taşımak
            // sonsuz döngüye ve veri kaybına yol açabilir. Hem kopyalama hem
            // taşıma için aynı güvenlik denetimi uygulanır.
            if FileManagerService.isDescendant(destination, of: source) {
                failures.append(
                    FileOperationFailure(
                        url: source,
                        message: L.t("error.intoItself", source.lastPathComponent)
                    )
                )
                continue
            }

            var overwrite = false
            if FileManager.default.fileExists(atPath: destination.path) {
                let decision: ConflictDecision
                if let automatic = settings.conflictPolicy.automaticDecision {
                    decision = automatic
                } else if let applyAll = applyToAllConflictDecision {
                    decision = applyAll
                } else {
                    let resolution = await askConflict(source: source, destination: destination)
                    decision = resolution.decision
                    if resolution.applyToAll {
                        applyToAllConflictDecision = decision
                    }
                }

                switch decision {
                case .cancel:
                    wasCancelled = true
                case .skip:
                    continue
                case .keepBoth:
                    destination = FileManagerService.uniqueDestination(
                        for: source.lastPathComponent,
                        in: destinationDirectory
                    )
                case .overwrite:
                    overwrite = true
                }

                if wasCancelled { break }
            }

            let baseBytes = progress.completedBytes
            let sourceName = source.lastPathComponent
            let progressHandler: @Sendable (Int64) -> Void = { [weak self] bytes in
                Task { @MainActor in
                    self?.updateProgress(completedBytes: baseBytes + bytes, currentItemName: sourceName)
                }
            }

            do {
                switch mode {
                case .copy:
                    try await copyService.copy(
                        source: source,
                        to: destination,
                        overwrite: overwrite,
                        control: control,
                        progress: progressHandler
                    )
                case .move:
                    try await moveService.move(
                        source: source,
                        to: destination,
                        overwrite: overwrite,
                        control: control,
                        progress: progressHandler
                    )
                }

                completedCount += 1
                progress.completedBytes = baseBytes + (perSourceBytes[source] ?? 0)
                progress.completedItems = completedCount
                operationProgress = progress
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                failures.append(ErrorMessages.failure(for: source, error: error))
            }
        }

        operationProgress = nil
        transferBytesPerSecond = 0
        isOperationPaused = false

        if mode == .move, !wasCancelled {
            clipboardSources.removeAll()
        }

        // Panelleri tazele.
        await leftPanel.reload(preserveSelection: true)
        await rightPanel.reload(preserveSelection: true)
        await activePanel.refreshGitStatus()

        let result = OperationResult(
            kind: kind,
            completedCount: completedCount,
            failures: failures,
            wasCancelled: wasCancelled
        )
        presentSummary(for: result, mode: mode)

        // Sıradaki aktarım varsa onu başlat; yoksa işlem durumunu kapat.
        finishTransferAndStartNext()
    }

    private func updateProgress(completedBytes: Int64, currentItemName: String) {
        guard var progress = operationProgress else { return }
        progress.completedBytes = max(progress.completedBytes, completedBytes)
        progress.currentItemName = currentItemName
        operationProgress = progress

        // Hızı yaklaşık yarım saniyelik aralıklarla örnekleyerek hesaplıyoruz.
        let now = Date()
        let elapsed = now.timeIntervalSince(speedSampleDate)
        if elapsed >= 0.5 {
            let delta = completedBytes - speedSampleBytes
            if delta >= 0 {
                transferBytesPerSecond = Double(delta) / elapsed
            }
            speedSampleDate = now
            speedSampleBytes = completedBytes
        }
    }

    private func askConflict(source: URL, destination: URL) async -> ConflictResolution {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let sourceValues = try? source.resourceValues(forKeys: keys)
        let destinationValues = try? destination.resourceValues(forKeys: keys)

        return await withCheckedContinuation { continuation in
            pendingConflict = ConflictRequest(
                sourceURL: source,
                destinationURL: destination,
                sourceName: source.lastPathComponent,
                destinationName: destination.lastPathComponent,
                destinationDirectory: destination.deletingLastPathComponent().path,
                sourceIsDirectory: sourceValues?.isDirectory ?? false,
                destinationIsDirectory: destinationValues?.isDirectory ?? false,
                sourceSize: sourceValues?.fileSize.map(Int64.init),
                destinationSize: destinationValues?.fileSize.map(Int64.init),
                sourceDate: sourceValues?.contentModificationDate,
                destinationDate: destinationValues?.contentModificationDate
            ) { decision, applyToAll in
                continuation.resume(returning: ConflictResolution(decision: decision, applyToAll: applyToAll))
            }
        }
    }

    private func presentSummary(for result: OperationResult, mode: TransferMode) {
        guard !result.failures.isEmpty || result.wasCancelled else { return }

        var lines: [String] = []
        if result.wasCancelled {
            lines.append(L.t("operation.cancelled"))
        }
        if !result.failures.isEmpty {
            lines.append(L.t("operation.failures", result.failures.count))
            lines.append(contentsOf: result.failures.prefix(8).map { failure in
                "• \(failure.url.lastPathComponent): \(failure.message)"
            })
            if result.failures.count > 8 {
                lines.append(L.t("operation.moreFailures", result.failures.count - 8))
            }
        }

        alert = UserFacingAlert(
            title: result.wasCancelled ? L.t("operation.cancelledTitle") : L.t("operation.failedTitle"),
            message: lines.joined(separator: "\n")
        )
    }

    // MARK: - Silme

    /// Etkin paneldeki seçili öğeleri Çöp Kutusu'na taşır.
    func trashSelection() {
        requestTrashConfirmation()
    }

    /// Etkin paneldeki seçili öğeler için kalıcı silme onayı ister.
    func requestPermanentDelete() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        deletionRequest = DeletionRequest(urls: urls, isPermanent: true)
    }

    /// F8 için Çöp Kutusu'na taşıma onayı ister.
    func requestTrashConfirmation() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        deletionRequest = DeletionRequest(urls: urls, isPermanent: false)
    }

    /// Silme onayını yanıtlar.
    func confirmDeletion() {
        guard let request = deletionRequest else { return }
        deletionRequest = nil
        performDeletion(urls: request.urls, permanently: request.isPermanent)
    }

    /// Silme işlemini yürütür.
    private func performDeletion(urls: [URL], permanently: Bool) {
        guard !isOperating else {
            alert = UserFacingAlert(title: L.t("error.title.busy"), message: L.t("error.busy"))
            return
        }

        isOperating = true
        let kind: OperationKind = permanently ? .delete : .trash
        operationProgress = OperationProgress(
            kind: kind,
            currentItemName: "",
            completedItems: 0,
            totalItems: urls.count,
            completedBytes: 0,
            totalBytes: 0
        )

        operationTask = Task { [weak self] in
            guard let self else { return }
            var failures: [FileOperationFailure] = []
            var completed = 0
            var wasCancelled = false

            for url in urls {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
                self.operationProgress?.currentItemName = url.lastPathComponent
                do {
                    if permanently {
                        try await self.fileManagerService.deletePermanently(url)
                    } else {
                        _ = try await self.fileManagerService.trash(url)
                    }
                    completed += 1
                    self.operationProgress?.completedItems = completed
                    self.operationProgress?.completedBytes = Int64(completed)
                } catch {
                    failures.append(ErrorMessages.failure(for: url, error: error))
                }
            }

            self.operationProgress = nil
            self.isOperating = false
            self.operationTask = nil

            await self.activePanel.reload(preserveSelection: true)
            await self.inactivePanel.reload(preserveSelection: true)
            await self.activePanel.refreshGitStatus()

            if !failures.isEmpty || wasCancelled {
                self.alert = UserFacingAlert(
                    title: L.t("operation.failedTitle"),
                    message: failures.prefix(8).map { "• \($0.url.lastPathComponent): \($0.message)" }
                        .joined(separator: "\n")
                )
            }
        }
    }

    // MARK: - Oluşturma ve yeniden adlandırma

    /// Etkin panelde yeni bir klasör oluşturur.
    func createNewFolder() {
        let directory = activePanel.currentDirectory
        Task { [weak self] in
            guard let self else { return }
            do {
                let newURL = try await self.fileManagerService.createDirectory(
                    in: directory,
                    preferredName: L.t("newFolder.defaultName")
                )
                await self.activePanel.reload(preserveSelection: false)
                self.activePanel.select(newURL)
            } catch {
                self.alert = UserFacingAlert(
                    title: ErrorMessages.title(for: error),
                    message: ErrorMessages.message(for: error)
                )
            }
        }
    }

    /// Seçili öğe için yeniden adlandırma isteği başlatır.
    func beginRename() {
        guard let item = activePanel.focusedItem else { return }
        renameRequest = RenameRequest(item: item, suggestedName: item.name)
    }

    /// Yeniden adlandırmayı uygular.
    /// - Parameters:
    ///   - item: Yeniden adlandırılacak öğe.
    ///   - newName: Yeni ad.
    func rename(_ item: FileItem, to newName: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let newURL = try await self.fileManagerService.rename(item.url, to: newName)
                await self.activePanel.reload(preserveSelection: false)
                self.activePanel.select(newURL)
            } catch {
                self.alert = UserFacingAlert(
                    title: ErrorMessages.title(for: error),
                    message: ErrorMessages.message(for: error)
                )
            }
        }
    }

    // MARK: - Terminal

    /// Sistem Terminalini etkin panelin klasöründe açar.
    ///
    /// Seçili tek bir klasör varsa Terminal o klasörde açılır; aksi halde panelin
    /// geçerli klasörü kullanılır.
    func openTerminal() {
        let target: URL
        if let item = activePanel.focusedItem, item.isDirectory, activePanel.selection.count == 1 {
            target = item.url
        } else {
            target = activePanel.currentDirectory
        }

        openTerminal(at: target)
    }

    /// Verilen klasörde sistem Terminalini açar.
    func openTerminal(at target: URL) {
        guard TerminalService.open(at: target) else {
            alert = UserFacingAlert(
                title: L.t("terminal.errorTitle"),
                message: L.t("terminal.errorMessage", target.path)
            )
            return
        }
    }

    // MARK: - Özellikler

    /// Seçili öğenin özelliklerini yükler ve pencereyi açar.
    func showProperties() {
        guard let item = activePanel.focusedItem else { return }
        propertiesItem = item
        properties = nil

        Task { [weak self] in
            guard let self else { return }
            let url = item.url
            let loaded = await Task.detached(priority: .userInitiated) {
                FileProperties.load(for: url)
            }.value
            guard self.propertiesItem?.url == url else { return }
            self.properties = loaded
        }
    }

    // MARK: - Git

    /// Etkin panelin Git durumunu yeniler.
    func refreshGitStatus() {
        Task { await activePanel.refreshGitStatus() }
    }

    /// Git deposunun kökünü Finder'da gösterir.
    func revealRepository() {
        guard let root = activePanel.gitStatus?.repositoryRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// Etkin paneldeki dal adını panoya kopyalar.
    func copyBranchName() {
        guard let branch = activePanel.gitStatus?.branch else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(branch, forType: .string)
    }
}

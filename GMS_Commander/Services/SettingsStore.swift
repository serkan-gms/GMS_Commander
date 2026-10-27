//
//  SettingsStore.swift
//  GMS_Commander
//
//  Kullanıcı tercihlerini UserDefaults üzerinde saklayan ayar deposu.
//  Değişiklikler anında kaydedilir; uygulama yeniden açıldığında korunur.
//

import Foundation
import Combine

/// Uygulama ayarları.
@MainActor
final class SettingsStore: ObservableObject {
    /// UserDefaults anahtarları.
    enum Keys {
        static let showHiddenFiles = "settings.showHiddenFiles"
        static let foldersFirst = "settings.foldersFirst"
        static let conflictPolicy = "settings.conflictPolicy"
        static let refreshAutomatically = "settings.refreshAutomatically"
        static let showRelativePathInSearch = "settings.showRelativePathInSearch"
        static let gitIntegration = "settings.gitIntegration"
        static let leftPath = "settings.leftPanelPath"
        static let rightPath = "settings.rightPanelPath"
        static let leftSortKey = "settings.leftSortKey"
        static let rightSortKey = "settings.rightSortKey"
        static let leftSortAscending = "settings.leftSortAscending"
        static let rightSortAscending = "settings.rightSortAscending"
        static let showFavoritesSidebar = "settings.showFavoritesSidebar"
        static let showFunctionKeyBar = "settings.showFunctionKeyBar"
        static let showStatusBar = "settings.showStatusBar"
        static let showFileInfo = "settings.showFileInfo"
        static let leftTabs = "settings.leftTabs"
        static let rightTabs = "settings.rightTabs"
        static let leftVisibleColumns = "settings.leftVisibleColumns"
        static let rightVisibleColumns = "settings.rightVisibleColumns"
        static let leftColumnWidths = "settings.leftColumnWidths"
        static let rightColumnWidths = "settings.rightColumnWidths"
        static let leftViewMode = "settings.leftViewMode"
        static let rightViewMode = "settings.rightViewMode"
        static let singlePanelMode = "settings.singlePanelMode"
        static let verticalSplit = "settings.verticalSplit"
        static let restoreTabs = "settings.restoreTabs"
        static let showPreviewPane = "settings.showPreviewPane"
        static let functionKeyBindings = "settings.functionKeyBindings"
    }

    private let defaults: UserDefaults

    /// Gizli dosyalar gösterilsin mi?
    @Published var showHiddenFiles: Bool {
        didSet { defaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles) }
    }

    /// Klasörler listede üstte mi kalsın?
    @Published var foldersFirst: Bool {
        didSet { defaults.set(foldersFirst, forKey: Keys.foldersFirst) }
    }

    /// Çakışma politikası.
    @Published var conflictPolicy: ConflictPolicy {
        didSet { defaults.set(conflictPolicy.rawValue, forKey: Keys.conflictPolicy) }
    }

    /// Klasör değişikliklerinde panel kendiliğinden yenilensin mi?
    @Published var refreshAutomatically: Bool {
        didSet { defaults.set(refreshAutomatically, forKey: Keys.refreshAutomatically) }
    }

    /// Arama sonuçlarında göreli yol gösterilsin mi?
    @Published var showRelativePathInSearch: Bool {
        didSet { defaults.set(showRelativePathInSearch, forKey: Keys.showRelativePathInSearch) }
    }

    /// Git durumu araç çubuğunda gösterilsin mi?
    @Published var gitIntegrationEnabled: Bool {
        didSet { defaults.set(gitIntegrationEnabled, forKey: Keys.gitIntegration) }
    }

    /// Sık kullanılanlar kenar çubuğu görünsün mü?
    @Published var showFavoritesSidebar: Bool {
        didSet { defaults.set(showFavoritesSidebar, forKey: Keys.showFavoritesSidebar) }
    }

    /// Alt işlev tuşu çubuğu görünsün mü?
    @Published var showFunctionKeyBar: Bool {
        didSet { defaults.set(showFunctionKeyBar, forKey: Keys.showFunctionKeyBar) }
    }

    /// Alt durum çubuğu görünsün mü?
    @Published var showStatusBar: Bool {
        didSet { defaults.set(showStatusBar, forKey: Keys.showStatusBar) }
    }

    /// Panel alt bilgi satırı görünsün mü?
    @Published var showFileInfo: Bool {
        didSet { defaults.set(showFileInfo, forKey: Keys.showFileInfo) }
    }

    /// Tek panel modu: yalnızca etkin panel gösterilir.
    @Published var singlePanelMode: Bool {
        didSet { defaults.set(singlePanelMode, forKey: Keys.singlePanelMode) }
    }

    /// İki panel yan yana mı (false) alt alta mı (true) gösterilsin?
    @Published var verticalSplit: Bool {
        didSet { defaults.set(verticalSplit, forKey: Keys.verticalSplit) }
    }

    /// Açılışta son sekmeler geri yüklensin mi?
    @Published var restoreTabsOnLaunch: Bool {
        didSet { defaults.set(restoreTabsOnLaunch, forKey: Keys.restoreTabs) }
    }

    /// Panelin yanında önizleme bölmesi görünsün mü?
    @Published var showPreviewPane: Bool {
        didSet { defaults.set(showPreviewPane, forKey: Keys.showPreviewPane) }
    }

    /// Kullanıcının işlev tuşu atamaları (eylem → tuş).
    @Published private(set) var functionKeyBindings: [String: String]

    /// Başlangıçta sol panelde açılacak klasör.
    @Published var leftPanelPath: String {
        didSet { defaults.set(leftPanelPath, forKey: Keys.leftPath) }
    }

    /// Başlangıçta sağ panelde açılacak klasör.
    @Published var rightPanelPath: String {
        didSet { defaults.set(rightPanelPath, forKey: Keys.rightPath) }
    }

    /// - Parameter defaults: Testlerde özel bir UserDefaults enjekte etmek için kullanılır.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.showHiddenFiles = defaults.object(forKey: Keys.showHiddenFiles) as? Bool ?? false
        self.foldersFirst = defaults.object(forKey: Keys.foldersFirst) as? Bool ?? true
        self.refreshAutomatically = defaults.object(forKey: Keys.refreshAutomatically) as? Bool ?? true
        self.showRelativePathInSearch = defaults.object(forKey: Keys.showRelativePathInSearch) as? Bool ?? true
        self.gitIntegrationEnabled = defaults.object(forKey: Keys.gitIntegration) as? Bool ?? false
        self.showFavoritesSidebar = defaults.object(forKey: Keys.showFavoritesSidebar) as? Bool ?? true
        self.showFunctionKeyBar = defaults.object(forKey: Keys.showFunctionKeyBar) as? Bool ?? true
        self.showStatusBar = defaults.object(forKey: Keys.showStatusBar) as? Bool ?? true
        self.showFileInfo = defaults.object(forKey: Keys.showFileInfo) as? Bool ?? true
        self.singlePanelMode = defaults.object(forKey: Keys.singlePanelMode) as? Bool ?? false
        self.verticalSplit = defaults.object(forKey: Keys.verticalSplit) as? Bool ?? false
        self.restoreTabsOnLaunch = defaults.object(forKey: Keys.restoreTabs) as? Bool ?? true
        self.showPreviewPane = defaults.object(forKey: Keys.showPreviewPane) as? Bool ?? false

        let storedBindings = defaults.dictionary(forKey: Keys.functionKeyBindings) as? [String: String] ?? [:]
        self.functionKeyBindings = KeyboardShortcutManager.FunctionKeyBindings(
            dictionary: storedBindings
        ).dictionary

        let policyRaw = defaults.string(forKey: Keys.conflictPolicy) ?? ""
        self.conflictPolicy = ConflictPolicy(rawValue: policyRaw) ?? .ask

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.leftPanelPath = defaults.string(forKey: Keys.leftPath) ?? home
        self.rightPanelPath = defaults.string(forKey: Keys.rightPath) ?? home

        if defaults.object(forKey: Keys.leftSortKey) == nil {
            defaults.set(FileSortKey.name.rawValue, forKey: Keys.leftSortKey)
        }
        if defaults.object(forKey: Keys.rightSortKey) == nil {
            defaults.set(FileSortKey.name.rawValue, forKey: Keys.rightSortKey)
        }
        if defaults.object(forKey: Keys.leftSortAscending) == nil {
            defaults.set(true, forKey: Keys.leftSortAscending)
        }
        if defaults.object(forKey: Keys.rightSortAscending) == nil {
            defaults.set(true, forKey: Keys.rightSortAscending)
        }
    }

    // MARK: - Klavye profili

    /// Çözümlenmiş işlev tuşu atamaları.
    var keyBindings: KeyboardShortcutManager.FunctionKeyBindings {
        KeyboardShortcutManager.FunctionKeyBindings(dictionary: functionKeyBindings)
    }

    /// Bir eyleme tuş atar. Tuş başka bir eylemde kullanılıyorsa atama yapılmaz
    /// ve çakışan eylem döndürülür.
    /// - Parameters:
    ///   - key: Yeni işlev tuşu.
    ///   - action: Atanacak eylem.
    /// - Returns: Çakışan eylem veya başarıda `nil`.
    @discardableResult
    func setFunctionKey(
        _ key: KeyboardShortcutManager.FunctionKey,
        for action: KeyboardShortcutManager.FunctionKeyAction
    ) -> KeyboardShortcutManager.FunctionKeyAction? {
        let bindings = keyBindings
        if let existing = bindings.action(for: key), existing != action {
            return existing
        }
        var updated = functionKeyBindings
        updated[action.rawValue] = key.rawValue
        functionKeyBindings = updated
        defaults.set(updated, forKey: Keys.functionKeyBindings)
        return nil
    }

    /// İşlev tuşlarını Norton Commander varsayılanlarına döndürür.
    func resetFunctionKeyBindings() {
        let defaultsDictionary = KeyboardShortcutManager.FunctionKeyBindings.default.dictionary
        functionKeyBindings = defaultsDictionary
        defaults.set(defaultsDictionary, forKey: Keys.functionKeyBindings)
    }

    /// Panel için saklanmış sıralama anahtarı.
    func sortKey(for panel: PanelSide) -> FileSortKey {
        let raw = defaults.string(forKey: sortKeyDefaultsKey(for: panel)) ?? ""
        return FileSortKey(rawValue: raw) ?? .name
    }

    /// Panel için saklanmış sıralama yönü.
    func sortAscending(for panel: PanelSide) -> Bool {
        defaults.object(forKey: ascendingDefaultsKey(for: panel)) as? Bool ?? true
    }

    /// Panel sıralamasını kaydeder.
    func setSort(key: FileSortKey, ascending: Bool, for panel: PanelSide) {
        defaults.set(key.rawValue, forKey: sortKeyDefaultsKey(for: panel))
        defaults.set(ascending, forKey: ascendingDefaultsKey(for: panel))
    }

    /// Panelin son açık klasörünü kaydeder.
    func setPath(_ url: URL, for panel: PanelSide) {
        switch panel {
        case .left: leftPanelPath = url.path
        case .right: rightPanelPath = url.path
        }
    }

    // MARK: - Sekmeler

    /// Panelin kayıtlı sekmelerini döndürür.
    func tabsState(for panel: PanelSide) -> PanelTabsState? {
        guard let data = defaults.data(forKey: tabsDefaultsKey(for: panel)) else { return nil }
        return try? JSONDecoder().decode(PanelTabsState.self, from: data)
    }

    /// Panelin sekmelerini kaydeder.
    func setTabsState(_ state: PanelTabsState, for panel: PanelSide) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: tabsDefaultsKey(for: panel))
    }

    // MARK: - Sütunlar

    /// Panelde görünen sütunlar (sıralı).
    func visibleColumns(for panel: PanelSide) -> [PanelColumn] {
        let raw = defaults.stringArray(forKey: columnsDefaultsKey(for: panel)) ?? []
        let columns = raw.compactMap(PanelColumn.init(rawValue:))
        return columns.isEmpty ? PanelColumn.defaultVisible : columns
    }

    /// Görünen sütunları ve sıralarını kaydeder.
    func setVisibleColumns(_ columns: [PanelColumn], for panel: PanelSide) {
        // Ad sütunu her zaman bulunmalıdır; aksi hâlde liste okunamaz.
        var ordered = columns
        if !ordered.contains(.name) {
            ordered.insert(.name, at: 0)
        }
        defaults.set(ordered.map(\.rawValue), forKey: columnsDefaultsKey(for: panel))
    }

    /// Panel sütun genişlikleri (sütun ham değeri → genişlik).
    func columnWidths(for panel: PanelSide) -> [String: Double] {
        (defaults.dictionary(forKey: widthsDefaultsKey(for: panel)) as? [String: NSNumber])?
            .mapValues(\.doubleValue) ?? [:]
    }

    /// Sütun genişliklerini kaydeder.
    func setColumnWidths(_ widths: [String: Double], for panel: PanelSide) {
        defaults.set(widths.mapValues { NSNumber(value: $0) }, forKey: widthsDefaultsKey(for: panel))
    }

    // MARK: - Görünüm modu

    func viewMode(for panel: PanelSide) -> PanelViewMode {
        let raw = defaults.string(forKey: viewModeDefaultsKey(for: panel)) ?? ""
        return PanelViewMode(rawValue: raw) ?? .details
    }

    func setViewMode(_ mode: PanelViewMode, for panel: PanelSide) {
        defaults.set(mode.rawValue, forKey: viewModeDefaultsKey(for: panel))
    }

    private func tabsDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftTabs : Keys.rightTabs
    }

    private func columnsDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftVisibleColumns : Keys.rightVisibleColumns
    }

    private func widthsDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftColumnWidths : Keys.rightColumnWidths
    }

    private func viewModeDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftViewMode : Keys.rightViewMode
    }

    private func sortKeyDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftSortKey : Keys.rightSortKey
    }

    private func ascendingDefaultsKey(for panel: PanelSide) -> String {
        panel == .left ? Keys.leftSortAscending : Keys.rightSortAscending
    }
}

/// İki panelin tarafları.
enum PanelSide: String, Sendable, CaseIterable {
    case left
    case right

    /// Diğer panel.
    var opposite: PanelSide {
        self == .left ? .right : .left
    }
}

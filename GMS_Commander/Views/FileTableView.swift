//
//  FileTableView.swift
//  GMS_Commander
//
//  Dosya listesi: Norton Commander düzeninde, sütun hizalı bir NSTableView.
//
//  Neden AppKit tablosu?
//  SwiftUI `List(selection:)` ile `.simultaneousGesture(TapGesture(count: 2))`
//  birlikte kullanıldığında çift tıklama tanıyıcısı tek tıklamayı yutuyor ve
//  seçim başka satıra taşınmıyordu. NSTableView seçimi kendi yönetir; tek tıklama
//  her zaman seçimi değiştirir, çift tıklama ayrıca açar. Görünüm de NC'ye yaklaşır.
//

import SwiftUI
import AppKit

/// Dosya tablosunun görünüm yapılandırması. Tema, sütunlar, genişlikler ve
/// görünüm modu değiştiğinde tablo yeniden kurulur.
struct FileTableConfiguration: Equatable {
    var appearance: AppearanceSignature
    var columns: [PanelColumn]
    var widths: [String: Double]
    var viewMode: PanelViewMode

    /// Kompakt görünümde satır yüksekliği azaltılır.
    var effectiveRowHeight: CGFloat {
        viewMode == .compact ? max(Appearance.rowHeight - 5, 15) : Appearance.rowHeight
    }
}

/// NSTableView tabanlı dosya listesi.
struct FileTableView: NSViewRepresentable {
    /// Panel görünüm modeli.
    @ObservedObject var panel: FilePanelViewModel
    /// Uygulama görünüm modeli (satır menüsü eylemleri için).
    @ObservedObject var viewModel: MainViewModel
    /// Panel yönü.
    let side: PanelSide
    /// Panel etkin mi?
    let isActive: Bool
    /// Tema, sütun ve görünüm yapılandırması.
    let configuration: FileTableConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(panel: panel, viewModel: viewModel, side: side, configuration: configuration)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileListNSTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        context.coordinator.tableView = tableView
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        // Ad sütunu her zaman ilk sırada ve kalan genişliği o doldurur.
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = configuration.effectiveRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = Palette.panel
        tableView.gridStyleMask = []
        tableView.headerView = NSTableHeaderView()
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.verticalMotionCanBeginDrag = false
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.menu = context.coordinator.makeContextMenu()
        tableView.parentRowIndex = context.coordinator.parentRowIndex

        context.coordinator.rebuildColumns(tableView: tableView)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.panel
        scrollView.scrollerStyle = .overlay
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel
        coordinator.side = side

        guard let tableView = scrollView.documentView as? FileListNSTableView else { return }
        tableView.parentRowIndex = coordinator.parentRowIndex
        tableView.backgroundColor = isActive ? Palette.panelActive : Palette.panel
        scrollView.backgroundColor = isActive ? Palette.panelActive : Palette.panel
        coordinator.isActive = isActive

        if coordinator.configuration != configuration {
            let appearanceChanged = coordinator.configuration.appearance != configuration.appearance
            let columnsChanged = coordinator.configuration.columns != configuration.columns
                || coordinator.configuration.widths != configuration.widths
                || coordinator.configuration.viewMode != configuration.viewMode
            coordinator.configuration = configuration

            if columnsChanged {
                coordinator.rebuildColumns(tableView: tableView)
            } else if appearanceChanged {
                coordinator.applyAppearance(tableView: tableView)
            }
        }
        coordinator.reload(tableView: tableView)
    }

    /// Yazı boyutuna göre sütun genişliği ölçeği.
    static var widthScale: CGFloat {
        CGFloat(Appearance.fontSize / ThemeManager.defaultFontSize)
    }

    // MARK: - Koordinatör

    /// Tablo verisi, seçim ve menü eylemlerini yönetir.
    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var panel: FilePanelViewModel
        var viewModel: MainViewModel
        var side: PanelSide
        weak var tableView: FileListNSTableView?
        var isActive = true
        /// Uygulanmış görünüm yapılandırması.
        var configuration: FileTableConfiguration

        /// Son yüklenen içerik sürümü.
        private var loadedRevision = -1
        /// Programatik seçim güncellemesi sırasında delegate çağrılarını yutar.
        private var isApplyingSelection = false
        /// Programatik sıralama güncellemesi sırasında delegate çağrılarını yutar.
        private var isApplyingSort = false

        /// Üst klasör satırı arama dışında ve kök klasör haricinde gösterilir.
        var parentRowIndex: Int? {
            panel.canGoUp && !panel.isSearchingActive ? 0 : nil
        }

        init(
            panel: FilePanelViewModel,
            viewModel: MainViewModel,
            side: PanelSide,
            configuration: FileTableConfiguration
        ) {
            self.panel = panel
            self.viewModel = viewModel
            self.side = side
            self.configuration = configuration
        }

        /// Tema veya yazı boyutu değiştiğinde tablo ölçülerini yeniler.
        func applyAppearance(tableView: NSTableView) {
            tableView.rowHeight = configuration.effectiveRowHeight
            tableView.backgroundColor = isActive ? Palette.panelActive : Palette.panel
            (tableView.enclosingScrollView)?.backgroundColor = isActive ? Palette.panelActive : Palette.panel

            for column in tableView.tableColumns {
                column.headerCell.font = Appearance.headerFont
                guard let spec = Self.columnSpecs[column.identifier.rawValue] else { continue }
                let scale = CGFloat(Appearance.fontSize / ThemeManager.defaultFontSize)
                column.minWidth = spec.minWidth * scale
            }

            // Hücreler yeniden oluşturulurken yeni yazı tipi ve simge boyutu kullanılır.
            loadedRevision = -1
        }

        /// Görünür sütunları yapılandırmaya göre yeniden kurar.
        /// Kullanıcı genişlikleri korunur; sütun sırası her zaman Ad ile başlar.
        func rebuildColumns(tableView: NSTableView) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let scale = CGFloat(Appearance.fontSize / ThemeManager.defaultFontSize)
            var ordered = configuration.columns
            if !ordered.contains(.name) {
                ordered.insert(.name, at: 0)
            }

            for panelColumn in ordered {
                guard let spec = Self.columnSpecs[panelColumn.rawValue] else { continue }
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(panelColumn.rawValue))
                column.title = panelColumn.title
                column.minWidth = spec.minWidth * scale
                column.width = configuration.widths[panelColumn.rawValue].map { CGFloat($0) }
                    ?? spec.defaultWidth * scale
                column.headerCell.font = Appearance.headerFont
                column.headerCell.alignment = spec.alignment
                column.sortDescriptorPrototype = NSSortDescriptor(
                    key: panelColumn.rawValue,
                    ascending: true
                )
                tableView.addTableColumn(column)
            }

            tableView.rowHeight = configuration.effectiveRowHeight
            tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
            tableView.headerView?.needsDisplay = true
            applySortDescriptor(tableView: tableView)
            loadedRevision = -1
        }

        /// Panelin sıralamasını başlık göstergesine yansıtır.
        private func applySortDescriptor(tableView: NSTableView) {
            let key = panel.sortKey.rawValue
            guard tableView.tableColumns.contains(where: { $0.identifier.rawValue == key }) else { return }
            let current = tableView.sortDescriptors.first
            guard current?.key != key || current?.ascending != panel.sortAscending else { return }
            isApplyingSort = true
            tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: panel.sortAscending)]
            isApplyingSort = false
        }

        /// Sütun tanımları.
        private struct ColumnSpec {
            let minWidth: CGFloat
            let defaultWidth: CGFloat
            let alignment: NSTextAlignment
        }

        private static let columnSpecs: [String: ColumnSpec] = [
            "name": ColumnSpec(minWidth: 140, defaultWidth: 260, alignment: .left),
            "fileExtension": ColumnSpec(minWidth: 48, defaultWidth: 64, alignment: .left),
            "kind": ColumnSpec(minWidth: 70, defaultWidth: 120, alignment: .left),
            "size": ColumnSpec(minWidth: 60, defaultWidth: 80, alignment: .right),
            "date": ColumnSpec(minWidth: 90, defaultWidth: 118, alignment: .left),
            "created": ColumnSpec(minWidth: 90, defaultWidth: 118, alignment: .left),
            "permissions": ColumnSpec(minWidth: 76, defaultWidth: 90, alignment: .left),
            "owner": ColumnSpec(minWidth: 70, defaultWidth: 90, alignment: .left),
            "tags": ColumnSpec(minWidth: 80, defaultWidth: 120, alignment: .left)
        ]

        // MARK: Yenileme

        /// İçerik sürümü değiştiyse tabloyu yeniden yükler.
        func reload(tableView: NSTableView) {
            applySortDescriptor(tableView: tableView)
            if loadedRevision != panel.revision {
                loadedRevision = panel.revision
                tableView.reloadData()
            }
            applySelection(to: tableView)
        }

        /// Model seçimini tabloya yansıtır (yalnızca farklıysa).
        private func applySelection(to tableView: NSTableView) {
            let items = panel.items
            let rowOffset = parentRowIndex == nil ? 0 : 1
            let target = IndexSet(items.indices.compactMap { index in
                panel.selection.contains(items[index].url) ? index + rowOffset : nil
            })
            guard target != tableView.selectedRowIndexes else { return }

            isApplyingSelection = true
            tableView.selectRowIndexes(target, byExtendingSelection: false)
            isApplyingSelection = false

            if let first = target.first {
                tableView.scrollRowToVisible(first)
            }
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            panel.items.count + (parentRowIndex == nil ? 0 : 1)
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let cell = makeCell(tableView: tableView, identifier: tableColumn.identifier)
            if row == parentRowIndex {
                let column = tableColumn.identifier.rawValue
                let text: String
                switch column {
                case "name": text = ".."
                case "kind": text = L.t("kind.parentFolder")
                case "size", "date": text = L.t("list.unknownDate")
                default: text = ""
                }
                cell.textField?.attributedStringValue = NSAttributedString(
                    string: text,
                    attributes: [
                        .font: Appearance.mono(.medium),
                        .foregroundColor: Palette.textSecondary
                    ]
                )
                cell.imageView?.image = column == "name"
                    ? NSImage(systemSymbolName: "arrow.turn.up.left", accessibilityDescription: L.t("kind.parentFolder"))
                    : nil
                return cell
            }

            let itemIndex = row - (parentRowIndex == nil ? 0 : 1)
            guard panel.items.indices.contains(itemIndex) else { return nil }
            let item = panel.items[itemIndex]
            let isSelected = panel.selection.contains(item.url)

            cell.textField?.attributedStringValue = attributedText(
                for: item,
                column: tableColumn.identifier.rawValue,
                isSelected: isSelected
            )
            cell.imageView?.image = tableColumn.identifier.rawValue == "name" ? icon(for: item) : nil
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let tableView = notification.object as? NSTableView else { return }
            let rowOffset = parentRowIndex == nil ? 0 : 1
            let selected = Set(tableView.selectedRowIndexes.compactMap { index -> URL? in
                let itemIndex = index - rowOffset
                guard panel.items.indices.contains(itemIndex) else { return nil }
                return panel.items[itemIndex].url
            })
            if selected != panel.selection {
                panel.setSelection(selected)
            }
            viewModel.activate(side: side)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingSort,
                  let key = tableView.sortDescriptors.first?.key,
                  let sortKey = Self.sortKey(forDescriptor: key) else { return }
            panel.sort(by: sortKey)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            var widths = configuration.widths
            for column in tableView.tableColumns {
                widths[column.identifier.rawValue] = Double(column.width)
            }
            configuration.widths = widths
            viewModel.settings.setColumnWidths(widths, for: side)
        }

        /// Sütun tanımlayıcısını sıralama anahtarına çevirir.
        private static func sortKey(forDescriptor key: String) -> FileSortKey? {
            FileSortKey(rawValue: key)
        }

        // MARK: Sürükle ve bırak

        /// Seçili satırları dosya adresi olarak sürükleme kaynağına ekler.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard let item = item(atRow: row) else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
            return pasteboardItem
        }

        /// Bırakılacak hedefi doğrular ve satırı uygun klasöre yönlendirir.
        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard !draggedFileURLs(from: info.draggingPasteboard).isEmpty,
                  let target = dropTarget(forRow: row) else {
                return []
            }

            let operation = preferredDropOperation(for: info)
            guard operation != [] else { return [] }

            // Dosya satırlarının ve boş alanın üzerine bırakmak, panelin
            // geçerli klasörüne yapıştırmak anlamına gelir. Klasör satırları
            // ise doğrudan o klasörün içine bırakılır.
            if dropOperation != .on || row != target.row {
                tableView.setDropRow(target.row, dropOperation: .on)
            }
            return operation
        }

        /// Bırakılan dosyaları hedef klasöre kopyalar veya taşır.
        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let sources = draggedFileURLs(from: info.draggingPasteboard)
            guard !sources.isEmpty, let target = dropTarget(forRow: row) else { return false }

            let operation = preferredDropOperation(for: info)
            let mode: TransferMode
            if operation == .move {
                mode = .move
            } else if operation == .copy || operation == .generic {
                mode = .copy
            } else {
                return false
            }

            viewModel.activate(side: side)
            viewModel.transfer(mode: mode, sources: sources, to: target.directory)
            return true
        }

        /// Tablo satırını dosya öğesine çevirir; üst klasör satırı `nil` döner.
        private func item(atRow row: Int) -> FileItem? {
            guard row != parentRowIndex else { return nil }
            let itemIndex = row - (parentRowIndex == nil ? 0 : 1)
            guard panel.items.indices.contains(itemIndex) else { return nil }
            return panel.items[itemIndex]
        }

        /// Bırakma satırını ve hedef klasörü belirler.
        /// - Returns: `-1` satırı panelin geçerli klasörünü, klasör satırı ise
        ///   o klasörün kendisini hedefler.
        private func dropTarget(forRow row: Int) -> (row: Int, directory: URL)? {
            if row == parentRowIndex, panel.canGoUp {
                return (row, panel.currentDirectory.deletingLastPathComponent())
            }
            if let item = item(atRow: row), item.isDirectory {
                return (row, item.url)
            }
            return (-1, panel.currentDirectory)
        }

        /// Kopyalama mı taşıma mı yapılacağını kaynak maskesi ve tuşlara göre seçer.
        private func preferredDropOperation(for info: NSDraggingInfo) -> NSDragOperation {
            let available = info.draggingSourceOperationMask
            let modifiers = NSEvent.modifierFlags
            let isLocal = info.draggingSource is NSTableView

            if modifiers.contains(.option), available.contains(.copy) {
                return .copy
            }
            if modifiers.contains(.command), available.contains(.move) {
                return .move
            }

            if isLocal {
                // Uygulama içinde varsayılan davranış taşımadır.
                if available.contains(.move) { return .move }
                if available.contains(.copy) { return .copy }
            } else {
                // Dışarıdan (örneğin Finder'dan) gelen sürüklemede varsayılan
                // davranış kopyalamadır; böylece yanlışlıkla veri taşınmaz.
                if available.contains(.copy) { return .copy }
                if available.contains(.move) { return .move }
            }
            return available.contains(.generic) ? .generic : []
        }

        /// Pano veya sürükleme öğesinden dosya adreslerini okur.
        private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty {
                return urls
            }

            // Eski Finder sürüklemeleri için dosya adları listesini de destekle.
            let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            if let paths = pasteboard.propertyList(forType: legacyType) as? [String] {
                return paths.map { URL(fileURLWithPath: $0) }
            }
            return []
        }

        // MARK: Eylemler

        /// Çift tıklama: klasöre gir veya dosyayı aç.
        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView = sender as? NSTableView else { return }
            let row = tableView.clickedRow
            guard row >= 0 else { return }
            if row == parentRowIndex {
                viewModel.activate(side: side)
                panel.goUp()
                return
            }
            let itemIndex = row - (parentRowIndex == nil ? 0 : 1)
            guard panel.items.indices.contains(itemIndex) else { return }
            let item = panel.items[itemIndex]
            panel.setSelection([item.url])
            viewModel.activate(side: side)
            viewModel.open(item)
        }

        /// Boş alana tıklanınca seçim temizlenir (NSTableView bunu kendisi yapar).
        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            // Sağ tık menüsündeki kopyala/yapıştır gibi eylemler tıklanan
            // panelde çalışsın diye paneli etkinleştiriyoruz.
            viewModel.activate(side: side)
            if let tableView {
                let clickedRow = tableView.clickedRow
                if clickedRow >= 0,
                   clickedRow != parentRowIndex,
                   !tableView.selectedRowIndexes.contains(clickedRow) {
                    tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                }
            }

            let hasSelection = !panel.selection.isEmpty
            let hasSingle = panel.selection.count == 1

            menu.addItem(menuItem("menu.file.open", #selector(openSelection), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.file.quickLook", #selector(quickLookSelection), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.file.openWith", #selector(openWith), enabled: hasSelection, key: ""))
            let hasArchive = panel.selectedItems.contains { ArchiveFormat.detect($0.url) != nil }
            menu.addItem(menuItem("menu.tools.openArchive", #selector(openArchive), enabled: hasArchive, key: ""))

            menu.addItem(.separator())
            menu.addItem(menuItem("menu.edit.copy", #selector(copySelection), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.edit.cut", #selector(cutSelection), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.edit.paste", #selector(pasteSelection), enabled: true, key: ""))
            if hasSelection, !viewModel.favorites.groups.isEmpty {
                menu.addItem(menuItem("favorites.addSelection", #selector(addSelectionToFavorites), enabled: true, key: ""))
            }

            menu.addItem(.separator())
            menu.addItem(menuItem("menu.file.newFolder", #selector(newFolder), enabled: true, key: ""))
            menu.addItem(menuItem("menu.tools.openTerminal", #selector(openTerminal), enabled: true, key: ""))
            menu.addItem(menuItem("menu.edit.rename", #selector(renameSelection), enabled: hasSingle, key: ""))
            menu.addItem(menuItem("menu.edit.batchRename", #selector(batchRename), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.file.copyPath", #selector(copyPath), enabled: hasSelection, key: ""))

            menu.addItem(.separator())
            menu.addItem(menuItem("menu.tools.properties", #selector(showProperties), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.file.reveal", #selector(revealInFinder), enabled: true, key: ""))
            menu.addItem(menuItem("menu.tools.revealCurrent", #selector(revealDirectoryInFinder), enabled: true, key: ""))

            menu.addItem(.separator())
            menu.addItem(menuItem("menu.file.trash", #selector(trashSelection), enabled: hasSelection, key: ""))
            menu.addItem(menuItem("menu.file.deletePermanently", #selector(deletePermanently), enabled: hasSelection, key: ""))

            menu.addItem(.separator())
            menu.addItem(menuItem("menu.view.refresh", #selector(refresh), enabled: true, key: ""))
            menu.addItem(
                menuItem(
                    panel.isShowingHiddenFiles ? "menu.file.hideHidden" : "menu.file.showHidden",
                    #selector(toggleHidden),
                    enabled: true,
                    key: ""
                )
            )
        }

        private func menuItem(_ titleKey: String, _ action: Selector, enabled: Bool, key: String) -> NSMenuItem {
            let item = NSMenuItem(title: L.t(titleKey), action: action, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            return item
        }

        @objc private func openSelection() { viewModel.openSelection() }
        @objc private func quickLookSelection() { viewModel.quickLookSelection() }
        @objc private func openWith() { viewModel.openSelectionWithApplication() }
        @objc private func openArchive() { viewModel.openSelectedArchive() }
        @objc private func copySelection() { viewModel.copySelection() }
        @objc private func cutSelection() { viewModel.cutSelection() }
        @objc private func pasteSelection() { viewModel.paste() }
        @objc private func addSelectionToFavorites() {
            viewModel.activate(side: side)
            guard viewModel.addSelectionToFavorites() == 0 else { return }
            viewModel.alert = UserFacingAlert(
                title: L.t("favorites.add.title"),
                message: L.t("favorites.add.exists")
            )
        }
        @objc private func renameSelection() { viewModel.beginRename() }
        @objc private func batchRename() { viewModel.beginBatchRename() }
        @objc private func copyPath() { viewModel.copyPathSelection() }
        @objc private func showProperties() { viewModel.showProperties() }
        @objc private func revealInFinder() { viewModel.revealSelection() }
        @objc private func revealDirectoryInFinder() { viewModel.revealCurrentDirectory() }
        @objc private func trashSelection() { viewModel.trashSelection() }
        @objc private func deletePermanently() { viewModel.requestPermanentDelete() }
        @objc private func refresh() { viewModel.refreshActivePanel() }
        @objc private func toggleHidden() { viewModel.toggleHiddenFiles() }

        @objc private func newFolder() {
            viewModel.activate(side: side)
            viewModel.createNewFolder()
        }

        @objc private func openTerminal() {
            viewModel.activate(side: side)
            viewModel.openTerminal()
        }

        // MARK: Hücre kurulumu

        private func makeCell(tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier) -> FileCellView {
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? FileCellView {
                existing.applyIconSize(Appearance.iconSize)
                return existing
            }

            let cell = FileCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = Appearance.mono()
            textField.cell?.usesSingleLineMode = true

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown

            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.textField = textField
            cell.imageView = imageView

            let iconWidth = imageView.widthAnchor.constraint(equalToConstant: Appearance.iconSize)
            let iconHeight = imageView.heightAnchor.constraint(equalToConstant: Appearance.iconSize)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iconWidth,
                iconHeight,
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            cell.iconWidth = iconWidth
            cell.iconHeight = iconHeight
            return cell
        }

        private func attributedText(for item: FileItem, column: String, isSelected: Bool) -> NSAttributedString {
            let text: String
            switch column {
            case "name":
                text = item.name
            case "fileExtension":
                text = item.fileExtension
            case "kind":
                text = item.kind
            case "size":
                text = FileSizeFormatter.string(for: item)
            case "date":
                text = item.modificationDate.map { Self.dateFormatter.string(from: $0) }
                    ?? L.t("list.unknownDate")
            case "created":
                text = item.creationDate.map { Self.dateFormatter.string(from: $0) }
                    ?? L.t("list.unknownDate")
            case "permissions":
                text = item.permissionsText ?? "—"
            case "owner":
                text = item.ownerName ?? "—"
            case "tags":
                text = item.tagNames.isEmpty ? "—" : item.tagNames.joined(separator: ", ")
            default:
                text = ""
            }

            let isFolder = item.isDirectory
            let color: NSColor
            if isSelected {
                color = NSColor.white
            } else if item.isHidden {
                color = Palette.textSecondary
            } else if isFolder {
                color = Palette.folder
            } else {
                color = Palette.textPrimary
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            paragraph.alignment = column == "size" ? .right : .left

            let font: NSFont
            if column == "name" {
                font = Appearance.mono(isFolder ? .medium : .regular)
            } else {
                font = NSFont.monospacedSystemFont(
                    ofSize: max(Appearance.tableFontSize - 0.5, 9),
                    weight: .regular
                )
            }

            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
        }

        private func icon(for item: FileItem) -> NSImage? {
            let size = Appearance.iconSize
            let image = NSWorkspace.shared.icon(forFile: item.url.path)
            image.size = NSSize(width: size, height: size)
            return image
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            return formatter
        }()
    }
}

/// Simge boyutu yazı ölçeğiyle değişebilen hücre görünümü.
@MainActor
final class FileCellView: NSTableCellView {
    var iconWidth: NSLayoutConstraint?
    var iconHeight: NSLayoutConstraint?

    /// Simge kutusunu verilen kenar uzunluğuna ayarlar.
    func applyIconSize(_ size: CGFloat) {
        iconWidth?.constant = size
        iconHeight?.constant = size
    }
}

/// Boş alana yapılan tıklamada seçimi temizleyen, `Return`/`Space` tuşlarını
/// yönlendiriciye bırakan tablo görünümü.
final class FileListNSTableView: NSTableView {
    var parentRowIndex: Int?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row == parentRowIndex {
            return NSMenu()
        }
        if row >= 0 {
            // Sağ tıklanan satır seçili değilse seçimi ona taşı.
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        return super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) < 0 {
            deselectAll(nil)
        }
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

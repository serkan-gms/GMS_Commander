//
//  FilePanelView.swift
//  GMS_Commander
//
//  Tek bir dosya panelini Norton Commander düzeninde gösterir: üstte yol ve
//  etkinlik göstergesi, ortada sütun başlıklı dosya listesi, altta özet bilgi.
//  Etkin panel vurgu rengiyle çerçevelenir.
//

import AppKit
import SwiftUI

/// Dosya paneli görünümü.
struct FilePanelView: View {
    @ObservedObject var panel: FilePanelViewModel
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var settings: SettingsStore
    let isActive: Bool
    /// Panel alt bilgi satırı gösterilsin mi?
    var showsFileInfo: Bool = true

    @EnvironmentObject private var theme: ThemeManager
    @FocusState private var searchFieldFocused: Bool

    /// Önizleme bölmesinin geçerli genişliği. Kenarındaki tutamaçla değiştirilir.
    @State private var previewWidth: CGFloat = 240
    /// Sürükleme başlarken önizleme bölmesinin genişliği.
    @State private var previewDragStart: CGFloat = 240
    @State private var isDraggingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(isActive ? Theme.accent : Theme.border)
                .frame(height: 1)
            if settings.showPreviewPane {
                // Önizleme bölmesi, soldaki tutamaç fareyle sürüklenerek
                // büyütülüp küçültülebilir.
                HStack(spacing: 0) {
                    fileList
                        .frame(minWidth: 220, maxWidth: .infinity)
                    previewHandle
                    FilePreviewPane(panel: panel, viewModel: viewModel)
                        .frame(width: previewWidth)
                }
            } else {
                fileList
            }
            if showsFileInfo {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                footer
            }
        }
        .background(isActive ? Theme.panelActive : Theme.panel)
        .overlay {
            Rectangle()
                .strokeBorder(isActive ? Theme.accent.opacity(0.65) : Theme.border.opacity(0.5), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                viewModel.activate(side: panel.side)
            }
        )
        .onChange(of: viewModel.searchFocusSide) { _, newValue in
            guard newValue == panel.side else { return }
            searchFieldFocused = true
            viewModel.searchFocusSide = nil
        }
        .contextMenu {
            Button(L.t("menu.file.newFolder")) {
                viewModel.activate(side: panel.side)
                viewModel.createNewFolder()
            }
            Button(L.t("menu.tools.openTerminal")) {
                viewModel.activate(side: panel.side)
                viewModel.openTerminal(at: panel.currentDirectory)
            }
            Divider()
            Button(L.t("menu.edit.paste")) { viewModel.paste() }
            Button(L.t("menu.view.refresh")) { viewModel.refreshActivePanel() }
            Divider()
            Button(L.t(panel.isShowingHiddenFiles ? "menu.file.hideHidden" : "menu.file.showHidden")) {
                viewModel.toggleHiddenFiles()
            }
            Button(L.t("menu.view.addFavorite")) {
                viewModel.activate(side: panel.side)
                viewModel.addActiveDirectoryToFavorites()
            }
            Button(L.t("menu.tools.revealCurrent")) { viewModel.revealCurrentDirectory() }
        }
    }

    /// Önizleme bölmesinin sol kenarındaki sürükleme tutamacı.
    ///
    /// Görünen çizgi 1 pt olsa da tıklama alanı 9 pt'dir; böylece fareyle
    /// yakalamak kolaydır. Tutamaç sola sürüklenince önizleme büyür.
    private var previewHandle: some View {
        ZStack {
            Theme.border
                .frame(width: 1)
            Color.clear
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDraggingPreview {
                        isDraggingPreview = true
                        previewDragStart = previewWidth
                    }
                    // Sola sürükleme (negatif genişleme) bölmeyi büyütür.
                    let proposed = previewDragStart - value.translation.width
                    previewWidth = min(max(proposed, 170), 900)
                }
                .onEnded { _ in
                    isDraggingPreview = false
                }
        )
        .help(L.t("toolbar.resizePreview"))
    }

    /// Panelin dosya listesi veya simge ızgarası.
    @ViewBuilder
    private var fileList: some View {
        if viewModel.settings.viewMode(for: panel.side) == .icons {
            FileIconGridView(
                panel: panel,
                viewModel: viewModel,
                isActive: isActive
            )
        } else {
            FileTableView(
                panel: panel,
                viewModel: viewModel,
                side: panel.side,
                isActive: isActive,
                configuration: FileTableConfiguration(
                    appearance: theme.signature,
                    columns: viewModel.settings.visibleColumns(for: panel.side),
                    widths: viewModel.settings.columnWidths(for: panel.side),
                    viewMode: viewModel.settings.viewMode(for: panel.side)
                )
            )
        }
    }

    // MARK: - Sekmeler

    /// Panelin sekmelerini gösteren ince şerit.
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(panel.tabs) { tab in
                    tabChip(tab)
                }
                Button {
                    viewModel.activate(side: panel.side)
                    panel.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L.t("tab.new"))
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 20)
    }

    private func tabChip(_ tab: PanelTab) -> some View {
        let isSelected = tab.id == panel.activeTabID
        return HStack(spacing: 4) {
            Image(systemName: tab.path.pathExtension.lowercased() == "app" ? "app" : "folder")
                .font(.system(size: 8))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)

            Text(tab.title)
                .font(.system(size: max(Appearance.secondaryFontSize - 2, 8), weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: 130, alignment: .leading)

            if panel.tabs.count > 1 {
                Button {
                    panel.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L.t("tab.close"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? Theme.accent.opacity(0.18) : Theme.keyChip.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.activate(side: panel.side)
            panel.activateTab(tab.id)
        }
        .help(tab.path.path)
        .contextMenu {
            Button(L.t("tab.duplicate")) {
                viewModel.activate(side: panel.side)
                panel.activateTab(tab.id)
                panel.duplicateActiveTab()
            }
            Button(L.t("tab.close")) {
                panel.closeTab(tab.id)
            }
            .disabled(panel.tabs.count <= 1)
            Button(L.t("tab.closeOthers")) {
                panel.activateTab(tab.id)
                panel.closeOtherTabs()
            }
            .disabled(panel.tabs.count <= 1)
            Divider()
            Button(L.t("tab.new")) {
                viewModel.activate(side: panel.side)
                panel.newTab()
            }
        }
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(spacing: 4) {
            tabBar

            HStack(spacing: 4) {
                // Sağ panelde yol aktarma oku, adres satırının sol ucunda
                // (birleşim kenarına yakın) durur; sol panelde sağ uçtadır.
                if showsTransferButton && panel.side == .right {
                    transferButton
                }

                navigationButton("chevron.left", help: L.t("toolbar.back"), enabled: panel.canGoBack, action: panel.goBack)
                navigationButton("chevron.right", help: L.t("toolbar.forward"), enabled: panel.canGoForward, action: panel.goForward)
                navigationButton("arrow.up", help: L.t("toolbar.up"), enabled: panel.canGoUp, action: panel.goUp)

                Text(panel.side == .left ? "SOL" : "SAĞ")
                    .font(.system(size: max(Appearance.keyFontSize - 3, 8), weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isActive ? Theme.accent.opacity(0.18) : Theme.keyChip)
                    )

                PanelPathView(panel: panel, viewModel: viewModel, isActive: isActive)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                if panel.isSearching {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                }

                if let git = panel.gitStatus, git.isRepository {
                    label(git.branch ?? "Git", systemImage: "arrow.triangle.branch")
                        .help(git.state.localizedTitle)
                }

                viewModeMenu
                columnsMenu

                if showsTransferButton && panel.side == .left {
                    transferButton
                }
            }

            searchField
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(isActive ? Theme.header : Theme.panel)
    }

    /// Yol aktarma oku yalnızca iki panel yan yana gösterilirken anlamlıdır.
    private var showsTransferButton: Bool {
        !settings.singlePanelMode && !settings.verticalSplit
    }

    /// Bu panelin açık klasör yolunu karşı panele aktaran düğme. Panel
    /// etkinken mavi, etkin değilken gri görünür.
    private var transferButton: some View {
        Button {
            viewModel.transferPath(from: panel.side)
        } label: {
            Image(systemName: panel.side == .left ? "arrow.right" : "arrow.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isActive ? Color.white : Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(isActive ? Theme.accent : Theme.statusBar)
                )
                .overlay(
                    Circle().strokeBorder(isActive ? Theme.accent : Theme.border)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L.t("panel.transferPath"))
    }

    /// Her panelin kendi yolunu gösteren breadcrumb ve mutlak yol düzenleyicisi.
    private struct PanelPathView: View {
        @ObservedObject var panel: FilePanelViewModel
        @ObservedObject var viewModel: MainViewModel
        let isActive: Bool

        @State private var pathText = ""
        @State private var isEditing = false
        /// Düzenleme sırasındaki metni SwiftUI durumuna yazmadan tutar;
        /// böylece her tuş vuruşunda panel yeniden çizilmez.
        @State private var fieldState = PathFieldState()

        private var breadcrumbs: [PathBreadcrumb] {
            PathBreadcrumb.make(for: panel.currentDirectory)
        }

        private var mountedVolumes: [URL] {
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey],
                options: [.skipHiddenVolumes]
            )?.sorted {
                volumeName(for: $0).localizedStandardCompare(volumeName(for: $1)) == .orderedAscending
            } ?? []
        }

        /// Kök klasörün görünen disk adı.
        private var rootVolumeName: String {
            volumeName(for: URL(fileURLWithPath: "/", isDirectory: true))
        }

        var body: some View {
            HStack(spacing: 5) {
                diskMenu

                if isEditing {
                    pathEditor
                } else {
                    breadcrumbList
                }

                pathActionButton
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .onAppear(perform: syncPathText)
            .onReceive(NotificationCenter.default.publisher(for: .beginPathEditing)) { notification in
                guard let side = notification.userInfo?[Notification.beginPathEditingSideKey] as? PanelSide,
                      side == panel.side else { return }
                beginEditing()
            }
            .contextMenu {
                Button(L.t("menu.tools.openTerminal")) {
                    viewModel.activate(side: panel.side)
                    viewModel.openTerminal(at: panel.currentDirectory)
                }
                Button(L.t("menu.tools.revealCurrent")) {
                    viewModel.activate(side: panel.side)
                    viewModel.revealCurrentDirectory()
                }
            }
        }

        /// Bağlı diskleri seçtiren sabit genişlikli menü. Menü etiketinin
        /// genişlemesi yol kırıntılarını sağa itmesin diye `fixedSize` kullanılır.
        private var diskMenu: some View {
            Menu {
                ForEach(mountedVolumes, id: \.path) { volume in
                    Button(volumeName(for: volume)) {
                        viewModel.navigatePanel(side: panel.side, toPath: volume.path)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L.t("toolbar.chooseDisk"))
        }

        /// Tıklanabilir yol kırıntıları. Disk simgesinin hemen yanından başlar.
        private var breadcrumbList: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(breadcrumbs.enumerated()), id: \.element.id) { index, breadcrumb in
                            if index > 0 {
                                Text("/")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Button {
                                viewModel.navigatePanel(side: panel.side, toPath: breadcrumb.url.path)
                            } label: {
                                Text(displayName(for: breadcrumb))
                                    .font(Theme.monoControl)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(index == breadcrumbs.count - 1
                                        ? (isActive ? Theme.textPrimary : Theme.textSecondary)
                                        : Theme.accent)
                                    .padding(.horizontal, 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(breadcrumb.url.path)
                            .id(breadcrumb.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { scrollToCurrent(proxy) }
                .onChange(of: panel.currentDirectory) { _, _ in
                    syncPathText()
                    scrollToCurrent(proxy)
                }
            }
            .layoutPriority(1)
        }

        /// Elle yol yazma alanı ve panodan yol yapıştırma düğmesi.
        private var pathEditor: some View {
            HStack(spacing: 4) {
                PathTextField(
                    state: fieldState,
                    onSubmit: { commitEditing(path: $0) },
                    onCancel: cancelEditing
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, minHeight: 22)
                .help(pathText)

                Button {
                    if let url = NSPasteboard.general.readObjects(
                        forClasses: [NSURL.self],
                        options: [.urlReadingFileURLsOnly: true]
                    )?.first as? URL {
                        setPath(url.path)
                    } else if let string = NSPasteboard.general.string(forType: .string) {
                        setPath(string.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L.t("toolbar.pastePath"))
            }
        }

        /// Yol düzenlemeyi başlatan veya yazılan yolu uygulayan düğme.
        private var pathActionButton: some View {
            Button {
                if isEditing {
                    commitEditing()
                } else {
                    beginEditing()
                }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(L.t(isEditing ? "toolbar.applyPath" : "toolbar.editPath"))
        }

        /// Yol düzenleme kipine geçer; alan görünür olur olmaz odağı alır.
        private func beginEditing() {
            viewModel.activate(side: panel.side)
            syncPathText()
            isEditing = true
        }

        /// Yazılan yolu uygular; yol geçersizse düzenleme kipinde kalır.
        private func commitEditing() {
            commitEditing(path: fieldState.text)
        }

        /// Verilen yolu uygular.
        private func commitEditing(path: String) {
            guard viewModel.navigatePanel(side: panel.side, toPath: path) else { return }
            syncPathText()
            isEditing = false
        }

        /// Yol düzenlemesini değişiklik yapmadan kapatır.
        private func cancelEditing() {
            syncPathText()
            isEditing = false
        }

        /// Yol metnini ve alandaki taslağı günceller.
        private func syncPathText() {
            let path = panel.currentDirectory.path
            pathText = path
            fieldState.text = path
        }

        /// Panoya kopyalanan yolu alana yazar.
        private func setPath(_ path: String) {
            fieldState.text = path
            pathText = path
        }

        private func displayName(for breadcrumb: PathBreadcrumb) -> String {
            breadcrumb.name == "/" ? rootVolumeName : breadcrumb.name
        }

        private func volumeName(for url: URL) -> String {
            (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                ?? (url.path == "/" ? "/" : url.lastPathComponent)
        }

        private func scrollToCurrent(_ proxy: ScrollViewProxy) {
            guard let last = breadcrumbs.last else { return }
            proxy.scrollTo(last.id, anchor: .trailing)
        }
    }

    /// Yol alanının düzenleme sırasındaki metnini gözlem tetiklemeden tutar.
    private final class PathFieldState {
        var text: String = ""
    }

    /// Yol düzenleme alanı. SwiftUI `TextField` yerine AppKit alanı kullanılır:
    /// görünür olduğunda odağı güvenilir biçimde alır, Return ile yolu uygular
    /// ve Esc ile düzenlemeyi kapatır.
    private struct PathTextField: NSViewRepresentable {
        let state: PathFieldState
        let onSubmit: (String) -> Void
        let onCancel: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> NSTextField {
            let field = FocusOnAttachTextField(string: state.text)
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.cell?.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.lineBreakMode = .byTruncatingHead
            field.font = .monospacedSystemFont(
                ofSize: max(Appearance.tableFontSize - 1, 9),
                weight: .regular
            )
            field.textColor = Palette.textPrimary
            field.placeholderString = L.t("toolbar.pathPlaceholder")
            field.delegate = context.coordinator
            field.onAttach = { [weak field] in
                guard let field, let window = field.window,
                      window.firstResponder !== field.currentEditor() else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
            return field
        }

        func updateNSView(_ field: NSTextField, context: Context) {
            context.coordinator.parent = self
            // Kullanıcı yazarken alanın içeriği korunur; yalnızca odak
            // alanda değilken dışarıdan gelen metin uygulanır.
            if field.window?.firstResponder !== field.currentEditor(),
               field.stringValue != state.text {
                field.stringValue = state.text
            }
        }

        /// Pencereye eklendiğinde odağı alan metin alanı. `updateNSView`
        /// pencereye eklenmeden çağrılabildiği için odak burada verilir.
        final class FocusOnAttachTextField: NSTextField {
            var onAttach: (() -> Void)?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onAttach?()
                }
            }
        }

        /// Metin değişikliklerini bağlama ve Return/Esc komutlarını yönetir.
        final class Coordinator: NSObject, NSTextFieldDelegate {
            var parent: PathTextField

            init(parent: PathTextField) {
                self.parent = parent
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSTextField else { return }
                parent.state.text = field.stringValue
            }

            func control(
                _ control: NSControl,
                textView: NSTextView,
                doCommandBy selector: Selector
            ) -> Bool {
                switch selector {
                case #selector(NSResponder.insertNewline(_:)):
                    parent.onSubmit(textView.string)
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    parent.onCancel()
                    return true
                default:
                    return false
                }
            }
        }
    }
    private func navigationButton(
        _ systemImage: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(Appearance.keyFontSize - 3, 8), weight: .bold))
                .frame(width: 16, height: 16)
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textSecondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    /// Panelin liste görünüm türünü seçtiren menü.
    private var viewModeMenu: some View {
        let current = viewModel.settings.viewMode(for: panel.side)
        return Menu {
            ForEach(PanelViewMode.allCases) { mode in
                Button {
                    viewModel.activate(side: panel.side)
                    viewModel.settings.setViewMode(mode, for: panel.side)
                    Task { await panel.reload(preserveSelection: true) }
                } label: {
                    Label(
                        mode.localizedName,
                        systemImage: mode == current ? "checkmark" : mode.systemImage
                    )
                }
            }
        } label: {
            Image(systemName: current.systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help(L.t("viewMode.menuHelp"))
    }

    /// Görünür sütunları seçtiren menü.
    private var columnsMenu: some View {
        let visible = viewModel.settings.visibleColumns(for: panel.side)
        return Menu {
            ForEach(PanelColumn.allCases) { column in
                Button {
                    viewModel.activate(side: panel.side)
                    viewModel.toggleColumn(column, for: panel.side)
                } label: {
                    Label(
                        column.title,
                        systemImage: visible.contains(column) ? "checkmark" : "square"
                    )
                }
                .disabled(column == .name)
            }
            Divider()
            columnWidthMenu(for: .fileExtension)
            columnWidthMenu(for: .size)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help(L.t("columns.menuHelp"))
    }

    /// Uzantı ve boyut sütunları için hızlı genişlik seçenekleri.
    private func columnWidthMenu(for column: PanelColumn) -> some View {
        Menu(L.t("columns.width.title", column.title)) {
            Button(L.t("columns.width.narrow")) {
                viewModel.setColumnWidth(column == .fileExtension ? 48 : 62, column: column, for: panel.side)
            }
            Button(L.t("columns.width.normal")) {
                viewModel.setColumnWidth(column == .fileExtension ? 72 : 86, column: column, for: panel.side)
            }
            Button(L.t("columns.width.wide")) {
                viewModel.setColumnWidth(column == .fileExtension ? 110 : 125, column: column, for: panel.side)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: max(Appearance.secondaryFontSize - 1, 8)))
                .foregroundStyle(Theme.textSecondary)

            TextField(
                L.t("search.placeholder"),
                text: Binding(
                    get: { panel.searchQuery },
                    set: { panel.updateSearchQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .font(Theme.monoControl)
            .foregroundStyle(Theme.textPrimary)
            .focused($searchFieldFocused)

            if panel.isSearchingActive {
                Button(action: panel.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: max(Appearance.secondaryFontSize - 1, 8)))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(L.t("search.clear"))
            }

            if panel.searchReachedLimit {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: max(Appearance.secondaryFontSize - 1, 8)))
                    .foregroundStyle(.orange)
                    .help(L.t("status.searchLimit"))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.border)
        )
    }

    // MARK: - Alt bilgi

    private var footer: some View {
        HStack(spacing: 8) {
            Text(panel.itemCountText)
            Text("·")
            Text(panel.selectionText)
            if !panel.selectionSizeText.isEmpty {
                Text(panel.selectionSizeText)
            }
            Spacer(minLength: 4)
            Text(panel.freeSpaceText)
        }
        .font(Theme.monoSmall)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isActive ? Theme.header : Theme.statusBar)
    }

    private func label(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Theme.monoSmall)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.keyChip, in: Capsule())
    }
}

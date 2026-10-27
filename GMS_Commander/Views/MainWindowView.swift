//
//  MainWindowView.swift
//  GMS_Commander
//
//  Ana pencere: komut çubuğu, iki dosya paneli, işlem ilerlemesi, durum satırı ve
//  Norton Commander düzenindeki işlev tuşu şeridi. Pencereler arası tüm iletişim
//  `MainViewModel` üzerinden yürür.
//

import SwiftUI
import AppKit

/// Ana pencere görünümü.
struct MainWindowView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var settings: SettingsStore

    @State private var keyRouter = KeyboardEventRouter()

    var body: some View {
        VStack(spacing: 0) {
            MainToolbarView(viewModel: viewModel)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HSplitView {
                if settings.showFavoritesSidebar {
                    FavoritesSidebarView(
                        viewModel: viewModel,
                        favorites: viewModel.favorites
                    )
                }
                if settings.singlePanelMode {
                    FilePanelView(
                        panel: viewModel.activePanel,
                        viewModel: viewModel,
                        isActive: true,
                        showsFileInfo: settings.showFileInfo
                    )
                    .frame(minWidth: 340)
                } else {
                    BalancedPaneSplitView(
                        left: AnyView(
                            FilePanelView(
                                panel: viewModel.leftPanel,
                                viewModel: viewModel,
                                isActive: viewModel.activeSide == .left,
                                showsFileInfo: settings.showFileInfo
                            )
                            .frame(minWidth: 300)
                        ),
                        right: AnyView(
                            FilePanelView(
                                panel: viewModel.rightPanel,
                                viewModel: viewModel,
                                isActive: viewModel.activeSide == .right,
                                showsFileInfo: settings.showFileInfo
                            )
                            .frame(minWidth: 300)
                        ),
                        isVertical: !settings.verticalSplit
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let progress = viewModel.operationProgress {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                OperationProgressView(
                    progress: progress,
                    isPaused: viewModel.isOperationPaused,
                    bytesPerSecond: viewModel.transferBytesPerSecond,
                    onPause: viewModel.pauseOperation,
                    onResume: viewModel.resumeOperation,
                    onCancel: viewModel.cancelOperation
                )
            }

            if settings.showStatusBar {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                StatusBarView(viewModel: viewModel)
            }

            if settings.showFunctionKeyBar {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                FunctionKeyBar(viewModel: viewModel)
            }
        }
        .background(Theme.window)
        .frame(minWidth: 960, minHeight: 600)
        .background(
            WindowAccessor { window in
                MainWindowPlacement.centerIfNeeded(window)
            }
        )
        .task {
            await viewModel.start()
        }
        .onAppear {
            startKeyboardRouting()
        }
        .onDisappear {
            keyRouter.stop()
        }
        .onChange(of: settings.functionKeyBindings) { _, _ in
            startKeyboardRouting()
        }
        .onChange(of: settings.showHiddenFiles) { _, _ in
            viewModel.refreshAll()
        }
        .onChange(of: settings.foldersFirst) { _, _ in
            viewModel.refreshAll()
        }
        .sheet(item: $viewModel.renameRequest) { request in
            RenameSheet(request: request) { newName in
                viewModel.rename(request.item, to: newName)
            }
        }
        .sheet(item: $viewModel.propertiesItem) { item in
            PropertiesSheet(item: item, viewModel: viewModel)
        }
        .sheet(item: $viewModel.pendingConflict) { request in
            ConflictSheet(request: request) { decision, applyToAll in
                viewModel.resolveConflict(decision, applyToAll: applyToAll)
            }
        }
        .sheet(isPresented: $viewModel.isShowingHelp) {
            HelpView(bindings: settings.keyBindings)
        }
        .sheet(isPresented: $viewModel.isShowingAdvancedSearch) {
            AdvancedSearchSheet(root: viewModel.activePanel.currentDirectory) { item in
                viewModel.revealSearchResult(item)
            }
        }
        .sheet(isPresented: $viewModel.isShowingFolderCompare) {
            FolderCompareSheet(
                leftRoot: viewModel.leftPanel.currentDirectory,
                rightRoot: viewModel.rightPanel.currentDirectory
            ) { url, side in
                viewModel.revealCompareItem(url, side: side)
            }
        }
        .sheet(item: $viewModel.hashRequest) { request in
            FileHashSheet(urls: request.urls)
        }
        .sheet(isPresented: $viewModel.isShowingPatternSelection) {
            SelectionPatternSheet(
                items: viewModel.activePanel.items,
                initialSelection: viewModel.activePanel.selection
            ) { urls, mode in
                viewModel.applyPatternSelection(urls, mode: mode)
            }
        }
        .sheet(item: $viewModel.viewerFile, onDismiss: viewModel.refreshAfterEditing) { request in
            FileViewerSheet(url: request.url)
        }
        .sheet(item: $viewModel.editorFile, onDismiss: viewModel.refreshAfterEditing) { request in
            FileEditorSheet(url: request.url)
        }
        .sheet(item: $viewModel.batchRenameRequest) { request in
            BatchRenameSheet(files: request.files) { _ in
                viewModel.refreshAfterBatchRename()
            }
        }
        .sheet(isPresented: $viewModel.isShowingTrashRestore) {
            TrashRestoreView(destination: viewModel.activePanel.currentDirectory) {
                viewModel.refreshAfterTrashOperation()
            }
        }
        .sheet(item: $viewModel.archiveBrowser) { request in
            ArchiveBrowserView(
                archiveURL: request.archiveURL,
                destinationDirectory: request.destinationDirectory
            ) {
                viewModel.refreshAfterArchiveExtraction()
            }
        }
        .confirmationDialog(
            viewModel.deletionRequest?.title ?? L.t("delete.confirm.title"),
            isPresented: deletionBinding,
            titleVisibility: .visible,
            presenting: viewModel.deletionRequest
        ) { request in
            Button(request.action, role: .destructive) {
                viewModel.confirmDeletion()
            }
            Button(L.t("common.cancel"), role: .cancel) {
                viewModel.deletionRequest = nil
            }
        } message: { request in
            Text(request.message)
        }
        .alert(
            viewModel.alert?.title ?? L.t("error.title.generic"),
            isPresented: alertBinding,
            presenting: viewModel.alert
        ) { _ in
            Button(L.t("common.ok"), role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    /// İşlev tuşu eylemini çalıştırır. `false` dönerse tuş yutulmaz.
    @MainActor
    /// Klavye izleyicisini güncel işlev tuşu atamalarıyla kurar.
    private func startKeyboardRouting() {
        keyRouter.stop()
        keyRouter.start(bindings: settings.keyBindings) { command in
            guard !viewModel.isModalPresented else { return false }

            switch command {
            case .bare(let action):
                switch action {
                case .quickLook:
                    viewModel.quickLookSelection()
                case .open:
                    guard !viewModel.activePanel.selection.isEmpty else { return false }
                    viewModel.openSelection()
                case .goUp:
                    viewModel.goUp()
                case .switchPanel:
                    viewModel.toggleActivePanel()
                }
            case .function(let action):
                return MainWindowView.perform(action, on: viewModel)
            }
            return true
        }
    }

    static func perform(_ action: KeyboardShortcutManager.FunctionKeyAction, on viewModel: MainViewModel) -> Bool {
        switch action {
        case .view:
            guard !viewModel.activePanel.selection.isEmpty else { return false }
            viewModel.openViewer()
        case .edit:
            guard !viewModel.activePanel.selection.isEmpty else { return false }
            viewModel.openEditor()
        case .copy:
            guard !viewModel.activePanel.selection.isEmpty else { return false }
            viewModel.copyToOtherPanel()
        case .move:
            guard !viewModel.activePanel.selection.isEmpty else { return false }
            viewModel.moveToOtherPanel()
        case .newFolder:
            viewModel.createNewFolder()
        case .delete:
            guard !viewModel.activePanel.selection.isEmpty else { return false }
            viewModel.requestTrashConfirmation()
        case .terminal:
            viewModel.openTerminal()
        case .quit:
            NSApplication.shared.terminate(nil)
        case .compress:
            viewModel.compressSelection()
        }
        return true
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deletionRequest != nil },
            set: { isPresented in
                if !isPresented { viewModel.deletionRequest = nil }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alert != nil },
            set: { isPresented in
                if !isPresented { viewModel.alert = nil }
            }
        )
    }
}

private struct BalancedPaneSplitView: NSViewRepresentable {
    let left: AnyView
    let right: AnyView
    /// `true` ise paneller yan yana, `false` ise alt alta yerleşir.
    var isVertical: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CenteringSplitView {
        let splitView = CenteringSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thin

        let leftHost = NSHostingView(rootView: left)
        let rightHost = NSHostingView(rootView: right)
        splitView.addArrangedSubview(leftHost)
        splitView.addArrangedSubview(rightHost)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        context.coordinator.leftHost = leftHost
        context.coordinator.rightHost = rightHost
        context.coordinator.splitView = splitView
        return splitView
    }

    func updateNSView(_ splitView: CenteringSplitView, context: Context) {
        if splitView.isVertical != isVertical {
            splitView.isVertical = isVertical
            splitView.adjustSubviews()
        }
        context.coordinator.leftHost?.rootView = left
        context.coordinator.rightHost?.rootView = right
    }

    final class Coordinator {
        weak var splitView: CenteringSplitView?
        var leftHost: NSHostingView<AnyView>?
        var rightHost: NSHostingView<AnyView>?
    }
}

private final class CenteringSplitView: NSSplitView {
    /// Açılışta panelleri bir kez eşit genişliğe getirir.
    private var didBalanceInitially = false

    override func layout() {
        super.layout()
        balanceInitiallyIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dividerPosition = isVertical
            ? subviews.first?.frame.maxX ?? 0
            : subviews.first?.frame.maxY ?? 0
        let dividerHitWidth = max(dividerThickness, 6)
        let distance = isVertical
            ? abs(point.x - dividerPosition)
            : abs(point.y - dividerPosition)
        if event.clickCount == 2,
           subviews.count > 1,
           distance <= dividerHitWidth,
           bounds.contains(point) {
            setPosition(halfExtent, ofDividerAt: 0)
            return
        }
        super.mouseDown(with: event)
    }

    /// İlk yerleşimde bölücüyü tam ortaya koyar; sonraki kullanıcı
    /// ayarlarına dokunmaz.
    private func balanceInitiallyIfNeeded() {
        guard !didBalanceInitially, subviews.count > 1, halfExtent > 100 else { return }
        didBalanceInitially = true
        setPosition(halfExtent, ofDividerAt: 0)
    }

    /// Bölme yönüne göre toplam uzunluğun yarısı.
    private var halfExtent: CGFloat {
        (isVertical ? bounds.width : bounds.height) / 2
    }
}

/// Üst komut çubuğu: gezinme, yol girişi ve hızlı eylemler.
struct MainToolbarView: View {
    @ObservedObject var viewModel: MainViewModel
    private var panel: FilePanelViewModel { viewModel.activePanel }

    var body: some View {
        HStack(spacing: 6) {
            iconButton("chevron.left", help: L.t("toolbar.back"), disabled: !panel.canGoBack) {
                viewModel.goBack()
            }
            iconButton("chevron.right", help: L.t("toolbar.forward"), disabled: !panel.canGoForward) {
                viewModel.goForward()
            }
            iconButton("arrow.up", help: L.t("toolbar.up"), disabled: !panel.canGoUp) {
                viewModel.goUp()
            }
            iconButton("arrow.clockwise", help: L.t("toolbar.refresh")) {
                viewModel.refreshActivePanel()
            }

            Spacer(minLength: 8)

            iconButton("folder.badge.plus", help: L.t("toolbar.newFolder")) {
                viewModel.createNewFolder()
            }
            iconButton("terminal", help: L.t("menu.tools.openTerminal")) {
                viewModel.openTerminal()
            }
            iconButton("doc.on.doc", help: L.t("toolbar.copyToOther")) {
                viewModel.copyToOtherPanel()
            }
            iconButton("arrow.right.square", help: L.t("toolbar.moveToOther")) {
                viewModel.moveToOtherPanel()
            }
            iconButton("trash", help: L.t("toolbar.trash")) {
                viewModel.trashSelection()
            }

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1, height: 16)

            iconButton(
                viewModel.settings.showHiddenFiles ? "eye.slash" : "eye",
                help: L.t("toolbar.toggleHidden")
            ) {
                viewModel.toggleHiddenFiles()
            }
            iconButton("magnifyingglass", help: L.t("toolbar.search")) {
                viewModel.focusSearch()
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(L.t("toolbar.settings"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.header)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 18, height: 18)
                .foregroundStyle(disabled ? Theme.textSecondary.opacity(0.4) : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}

/// Alt durum satırı.
struct StatusBarView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        let panel = viewModel.activePanel

        HStack(spacing: 10) {
            Text(panel.isSearchingActive ? L.t("status.searchResults", panel.items.count) : panel.itemCountText)
            Text(panel.selectionText)
            if !panel.selectionSizeText.isEmpty {
                Text(panel.selectionSizeText)
            }
            Spacer()
            if viewModel.isOperating {
                Label(L.t("status.operating"), systemImage: "arrow.triangle.2.circlepath")
            }
            if let git = panel.gitStatus, git.isRepository {
                Label("\(git.branch ?? "Git") • \(git.state.localizedTitle)", systemImage: "arrow.triangle.branch")
                    .lineLimit(1)
            }
            Text(panel.freeSpaceText)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Theme.statusBar)
    }
}

/// Norton Commander düzenindeki işlev tuşu şeridi (F3…F10).
struct FunctionKeyBar: View {
    @ObservedObject var viewModel: MainViewModel
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(KeyboardShortcutManager.FunctionKeyAction.allCases) { action in
                button(for: action)
                if action != KeyboardShortcutManager.FunctionKeyAction.allCases.last {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1, height: 14)
                }
            }
            Spacer(minLength: 0)
            Text(L.t("fkey.panelHint", viewModel.activeSide == .left ? L.t("panel.left") : L.t("panel.right")))
                .font(.system(size: max(theme.functionKeyFontSize - 2, 8), design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Theme.header)
    }

    private func button(for action: KeyboardShortcutManager.FunctionKeyAction) -> some View {
        Button {
            viewModel.activate(side: viewModel.activeSide)
            _ = MainWindowView.perform(action, on: viewModel)
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.settings.keyBindings.label(for: action))
                    .font(.system(size: max(theme.functionKeyFontSize - 1, 8), weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.keyChip, in: RoundedRectangle(cornerRadius: 3))

                Text(action.title)
                    .font(.system(size: theme.functionKeyFontSize))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 6 * theme.functionKeyButtonScale)
            .padding(.vertical, 4 * theme.functionKeyButtonScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.title)
    }
}

/// Süren işlemin ilerleme şeridi. Duraklatma/sürdürme ve hız/kalan süre
/// bilgilerini gösterir.
struct OperationProgressView: View {
    let progress: OperationProgress
    let isPaused: Bool
    let bytesPerSecond: Double
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    private var model: FileOperationViewModel {
        FileOperationViewModel(progress: progress, bytesPerSecond: bytesPerSecond)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(model.title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)

            Text(model.currentItemName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)

            ProgressView(value: model.fraction)
                .frame(maxWidth: 200)

            Text(model.percentText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            if model.showsByteCount {
                Text(model.byteCountText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            if let speed = model.speedText {
                Text(speed)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            if !isPaused, let remaining = model.remainingTimeText {
                Text(remaining)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            if isPaused {
                Text(L.t("operation.paused"))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(isPaused ? L.t("operation.resume") : L.t("operation.pause")) {
                isPaused ? onResume() : onPause()
            }
            .controlSize(.small)
            .disabled(progress.kind == .delete || progress.kind == .trash)

            Button(L.t("common.cancel"), action: onCancel)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.statusBar)
    }
}

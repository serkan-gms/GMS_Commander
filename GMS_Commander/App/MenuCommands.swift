//
//  MenuCommands.swift
//  GMS_Commander
//
//  Türkçe menü komutları ve klavye kısayolları.
//

import SwiftUI

/// Uygulama menüleri: Dosya, Düzen, Görünüm, Git, Araçlar, Yardım.
struct CommanderCommands: Commands {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var settings: SettingsStore

    var body: some Commands {
        // MARK: Dosya
        CommandGroup(replacing: .newItem) {
            Button(L.t("menu.file.newFolder")) {
                viewModel.createNewFolder()
            }
            .keyboardShortcut("N", modifiers: [.command, .shift])

            Divider()

            Button(L.t("menu.file.open")) {
                viewModel.openSelection()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(L.t("menu.file.quickLook")) {
                viewModel.quickLookSelection()
            }
            .keyboardShortcut("y", modifiers: .command)

            Button(L.t("menu.file.view")) {
                viewModel.openViewer()
            }

            Button(L.t("menu.file.edit")) {
                viewModel.openEditor()
            }

            Button(L.t("menu.file.openWith")) {
                viewModel.openSelectionWithApplication()
            }

            Divider()

            Button(L.t("menu.file.reveal")) {
                viewModel.revealSelection()
            }

            Divider()

            Button(L.t("menu.file.trash")) {
                viewModel.trashSelection()
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Button(L.t("menu.file.deletePermanently")) {
                viewModel.requestPermanentDelete()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])

            Button(L.t("menu.file.restoreFromTrash")) {
                viewModel.showTrashRestore()
            }

            Divider()

            Button(
                settings.showHiddenFiles
                    ? L.t("menu.file.hideHidden")
                    : L.t("menu.file.showHidden")
            ) {
                viewModel.toggleHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
        }

        // MARK: Düzen
        CommandGroup(replacing: .pasteboard) {
            Button(L.t("menu.edit.cut")) {
                viewModel.cutSelection()
            }
            .keyboardShortcut("x", modifiers: .command)

            Button(L.t("menu.edit.copy")) {
                viewModel.copySelection()
            }
            .keyboardShortcut("c", modifiers: .command)

            Button(L.t("menu.edit.paste")) {
                viewModel.paste()
            }
            .keyboardShortcut("v", modifiers: .command)

            Divider()

            Button(L.t("menu.edit.copyPath")) {
                viewModel.copyPathSelection()
            }

            Button(L.t("menu.edit.editPath")) {
                viewModel.beginPathEditing()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button(L.t("menu.edit.rename")) {
                viewModel.beginRename()
            }

            Button(L.t("menu.edit.batchRename")) {
                viewModel.beginBatchRename()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            Button(L.t("menu.edit.selectAll")) {
                viewModel.selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button(L.t("menu.edit.deselectAll")) {
                viewModel.deselectAll()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button(L.t("menu.edit.selectPattern")) {
                viewModel.showPatternSelection()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button(L.t("menu.edit.invertSelection")) {
                viewModel.invertSelection()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // MARK: Görünüm
        CommandGroup(after: .sidebar) {
            Button(L.t("menu.view.switchPanel")) {
                viewModel.toggleActivePanel()
            }
            .keyboardShortcut(.tab, modifiers: [])

            Button(L.t("menu.view.refresh")) {
                viewModel.refreshActivePanel()
            }

            Button(L.t("menu.view.goUp")) {
                viewModel.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button(L.t("menu.view.goHome")) {
                viewModel.goHome()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button(L.t("menu.view.search")) {
                viewModel.focusSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(L.t("menu.view.advancedSearch")) {
                viewModel.showAdvancedSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button(L.t("menu.view.clearSearch")) {
                viewModel.activePanel.clearSearch()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Divider()

            Menu(L.t("menu.view.sort")) {
                ForEach(FileSortKey.allCases, id: \.self) { key in
                    Button(key.localizedName) {
                        viewModel.activePanel.sort(by: key)
                    }
                }
            }

            Button(L.t("menu.view.foldersFirst")) {
                viewModel.toggleFoldersFirst()
            }

            Divider()

            // Sekmeler
            Button(L.t("tab.new")) {
                viewModel.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button(L.t("tab.close")) {
                viewModel.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button(L.t("tab.next")) {
                viewModel.nextTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control])

            Button(L.t("tab.previous")) {
                viewModel.previousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])

            Button(L.t("tab.duplicate")) {
                viewModel.duplicateActiveTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Menu(L.t("menu.view.viewMode")) {
                ForEach(PanelViewMode.allCases) { mode in
                    Button(mode.localizedName) {
                        settings.setViewMode(mode, for: viewModel.activeSide)
                        viewModel.refreshActivePanel()
                    }
                }
            }

            Menu(L.t("menu.view.columns")) {
                let visible = settings.visibleColumns(for: viewModel.activeSide)
                ForEach(PanelColumn.allCases) { column in
                    Button {
                        viewModel.toggleColumn(column, for: viewModel.activeSide)
                    } label: {
                        if visible.contains(column) {
                            Label(column.title, systemImage: "checkmark")
                        } else {
                            Text(column.title)
                        }
                    }
                    .disabled(column == .name)
                }
            }

            Button(L.t("menu.view.previewPane")) {
                settings.showPreviewPane.toggle()
            }

            Divider()

            Button(L.t("menu.view.swapPanels")) {
                viewModel.swapPanels()
            }

            Button(settings.singlePanelMode ? L.t("menu.view.showTwoPanels") : L.t("menu.view.singlePanel")) {
                settings.singlePanelMode.toggle()
            }
        }

        // MARK: Git
        CommandMenu(L.t("menu.git")) {
            Button(L.t("git.refresh")) {
                viewModel.refreshGitStatus()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(L.t("git.revealRepository")) {
                viewModel.revealRepository()
            }

            Button(L.t("git.copyBranch")) {
                viewModel.copyBranchName()
            }
            .disabled(viewModel.activePanel.gitStatus?.branch == nil)
        }

        // MARK: Araçlar
        CommandMenu(L.t("menu.tools")) {
            Button(L.t("menu.tools.properties")) {
                viewModel.showProperties()
            }

            Button(L.t("menu.tools.openArchive")) {
                viewModel.openSelectedArchive()
            }

            Button(L.t("menu.tools.folderCompare")) {
                viewModel.showFolderCompare()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Button(L.t("menu.tools.hash")) {
                viewModel.beginHashCalculation()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Divider()

            // F5/F6 tuşları KeyboardShortcutManager üzerinden yönlendirilir.
            Button(L.t("menu.tools.copyToOther")) {
                viewModel.copyToOtherPanel()
            }

            Button(L.t("menu.tools.moveToOther")) {
                viewModel.moveToOtherPanel()
            }

            Divider()

            Button(L.t("menu.tools.openTerminal")) {
                viewModel.openTerminal()
            }

            Divider()

            Button(L.t("menu.tools.revealCurrent")) {
                viewModel.revealCurrentDirectory()
            }
        }

        // MARK: Yardım
        CommandGroup(replacing: .help) {
            Button(L.t("menu.help.shortcuts")) {
                viewModel.isShowingHelp = true
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }
}

//
//  FilePanelViewModelTests.swift
//  GMSCommanderTests
//
//  Panel görünüm modelinin gezinme, sıralama ve seçim davranışları.
//

import Foundation
import XCTest
@testable import GMS_Commander

@MainActor
final class FilePanelViewModelTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
        suiteName = "com.gms.commander.panel.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        try TestSupport.writeFile(named: "b.txt", contents: "bb", in: directory)
        try TestSupport.writeFile(named: "a.txt", contents: "a", in: directory)
        try TestSupport.makeDirectory(named: "Alt", in: directory)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        TestSupport.remove(directory)
    }

    func testActivateLoadsDirectory() async throws {
        let panel = makePanel()
        await panel.activate()

        XCTAssertEqual(panel.currentDirectory.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(panel.items.count, 3)
        XCTAssertEqual(panel.items.first?.name, "Alt", "Klasörler önce gelmeli")
        XCTAssertFalse(panel.isLoading)
    }

    func testNavigateUpdatesHistory() async throws {
        let panel = makePanel()
        await panel.activate()

        let sub = directory.appendingPathComponent("Alt", isDirectory: true)
        panel.navigate(to: sub)
        await waitForLoad(panel)
        XCTAssertEqual(panel.currentDirectory.standardizedFileURL, sub.standardizedFileURL)
        XCTAssertTrue(panel.canGoBack)

        panel.goBack()
        await waitForLoad(panel)
        XCTAssertEqual(panel.currentDirectory.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(panel.canGoForward)

        panel.goForward()
        await waitForLoad(panel)
        XCTAssertEqual(panel.currentDirectory.standardizedFileURL, sub.standardizedFileURL)
    }

    func testGoUpFromDirectory() async throws {
        let panel = makePanel()
        panel.navigate(to: directory.appendingPathComponent("Alt", isDirectory: true))
        await waitForLoad(panel)

        XCTAssertTrue(panel.canGoUp)
        panel.goUp()
        await waitForLoad(panel)
        XCTAssertEqual(panel.currentDirectory.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(panel.focusedItem?.name, "Alt", "Çıkılan alt klasör üst dizinde seçili kalmalı")
    }

    func testSortTogglesDirection() async throws {
        let panel = makePanel()
        await panel.activate()

        XCTAssertEqual(panel.sortKey, .name)
        XCTAssertTrue(panel.sortAscending)

        panel.sort(by: .name)
        XCTAssertEqual(panel.sortKey, .name)
        XCTAssertFalse(panel.sortAscending)
        XCTAssertEqual(panel.items.first?.name, "Alt", "Klasörler her yönde önce gelmeli")
        XCTAssertEqual(panel.items.last?.name, "a.txt")

        panel.sort(by: .size)
        XCTAssertEqual(panel.sortKey, .size)
        XCTAssertTrue(panel.sortAscending)
    }

    func testSelectionTextReflectsSelection() async throws {
        let panel = makePanel()
        await panel.activate()

        panel.clearSelection()
        XCTAssertEqual(panel.selectionText, L.t("status.noSelection"))

        let url = directory.appendingPathComponent("a.txt")
        panel.setSelection([url])
        XCTAssertEqual(panel.selection.count, 1)
        XCTAssertEqual(panel.selectionText, L.t("status.selection", 1))
        XCTAssertEqual(panel.focusedItem?.name, "a.txt")
    }

    func testDisplayPathUsesHomeAbbreviation() async throws {
        let panel = makePanel()
        await panel.activate()

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(panel.displayPath.hasPrefix(home) || panel.displayPath.hasPrefix("~"))
        XCTAssertFalse(panel.title.isEmpty)
        XCTAssertTrue(panel.itemCountText.contains("2"))
    }

    func testPathBreadcrumbsNavigateByAncestor() {
        let target = URL(fileURLWithPath: "/Users/testuser/Documents/GMS_PROJE/TEKNIK DOKUMANLAR", isDirectory: true)
        let breadcrumbs = PathBreadcrumb.make(for: target)

        XCTAssertEqual(
            breadcrumbs.map(\.name),
            ["/", "Users", "testuser", "Documents", "GMS_PROJE", "TEKNIK DOKUMANLAR"]
        )
        XCTAssertEqual(breadcrumbs[3].url.path, "/Users/testuser/Documents")
        XCTAssertEqual(breadcrumbs.last?.url.standardizedFileURL, target.standardizedFileURL)
    }

    func testPathBreadcrumbsIncludeRootOutsideHome() {
        let target = URL(fileURLWithPath: "/Volumes/Data/Project", isDirectory: true)
        let breadcrumbs = PathBreadcrumb.make(for: target)

        XCTAssertEqual(breadcrumbs.map(\.name), ["/", "Volumes", "Data", "Project"])
        XCTAssertEqual(breadcrumbs[2].url.path, "/Volumes/Data")
    }

    func testNavigateToInvalidPathShowsAlert() async throws {
        let panel = makePanel()
        await panel.activate()

        panel.navigate(to: directory.appendingPathComponent("yok", isDirectory: true))
        for _ in 0..<50 where panel.alert == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertNotNil(panel.alert)
        XCTAssertTrue(panel.items.isEmpty)
    }

    private func makePanel() -> FilePanelViewModel {
        let settings = SettingsStore(defaults: defaults)
        settings.refreshAutomatically = false
        settings.gitIntegrationEnabled = false
        settings.setPath(directory, for: .left)
        return FilePanelViewModel(side: .left, settings: settings)
    }

    private func waitForLoad(_ panel: FilePanelViewModel) async {
        try? await Task.sleep(nanoseconds: 60_000_000)
        for _ in 0..<100 {
            if !panel.isLoading { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

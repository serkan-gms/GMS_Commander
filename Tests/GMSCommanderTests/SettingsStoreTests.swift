//
//  SettingsStoreTests.swift
//  GMSCommanderTests
//
//  Kullanıcı ayarlarının kalıcılığı testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "com.gms.commander.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaultValues() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.showHiddenFiles)
        XCTAssertTrue(store.foldersFirst)
        XCTAssertEqual(store.conflictPolicy, .ask)
        XCTAssertTrue(store.gitIntegrationEnabled)
        XCTAssertEqual(store.sortKey(for: .left), .name)
        XCTAssertTrue(store.sortAscending(for: .left))
    }

    func testValuesPersistAcrossInstances() {
        let store = SettingsStore(defaults: defaults)
        store.showHiddenFiles = true
        store.foldersFirst = false
        store.conflictPolicy = .keepBoth

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.showHiddenFiles)
        XCTAssertFalse(reloaded.foldersFirst)
        XCTAssertEqual(reloaded.conflictPolicy, .keepBoth)
    }

    func testSortSettingsArePerPanel() {
        let store = SettingsStore(defaults: defaults)
        store.setSort(key: .size, ascending: false, for: .left)

        XCTAssertEqual(store.sortKey(for: .left), .size)
        XCTAssertFalse(store.sortAscending(for: .left))
        XCTAssertEqual(store.sortKey(for: .right), .name)
        XCTAssertTrue(store.sortAscending(for: .right))
    }

    func testPathIsPersistedPerPanel() {
        let store = SettingsStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/Users/Shared")
        store.setPath(url, for: .right)

        XCTAssertEqual(store.rightPanelPath, "/Users/Shared")
        XCTAssertNotEqual(store.leftPanelPath, "/Users/Shared")
    }

    func testPanelSideOpposite() {
        XCTAssertEqual(PanelSide.left.opposite, .right)
        XCTAssertEqual(PanelSide.right.opposite, .left)
    }
}

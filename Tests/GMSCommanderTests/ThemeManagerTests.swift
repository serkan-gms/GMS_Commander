//
//  ThemeManagerTests.swift
//  GMSCommanderTests
//
//  Tema ve yazı boyutu tercihlerinin kalıcılık testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

@MainActor
final class ThemeManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "com.gms.commander.theme.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        ThemeManager.shared.themeID = .voidCommander
        ThemeManager.shared.resetFontSize()
        ThemeManager.shared.resetFontStyle()
    }

    func testThemeAndFontSizePersistAcrossInstances() {
        let theme = ThemeManager(defaults: defaults)
        theme.themeID = .graphite
        theme.fontSize = 16
        theme.fontStyle = .classicDOS

        let reloaded = ThemeManager(defaults: defaults)
        XCTAssertEqual(reloaded.themeID, .graphite)
        XCTAssertEqual(reloaded.fontSize, 16)
        XCTAssertEqual(reloaded.fontStyle, .classicDOS)
        XCTAssertEqual(reloaded.signature.themeID, .graphite)
        XCTAssertEqual(reloaded.signature.fontSize, 16)
        XCTAssertEqual(reloaded.signature.fontStyle, .classicDOS)
    }

    func testFontSizeIsClampedToSupportedRange() {
        XCTAssertEqual(ThemeManager.clampFontSize(-1), ThemeManager.fontSizeRange.lowerBound)
        XCTAssertEqual(ThemeManager.clampFontSize(99), ThemeManager.fontSizeRange.upperBound)
    }

    func testLightThemeIsIdentified() {
        XCTAssertTrue(ThemeID.daylight.isLight)
        XCTAssertFalse(ThemeID.graphite.isLight)
    }
}

//
//  OperationViewModelTests.swift
//  GMSCommanderTests
//
//  İlerleme sunucusu ve kısayol kataloğu testleri.
//

import XCTest
@testable import GMS_Commander

final class OperationViewModelTests: XCTestCase {
    private func makeProgress(
        kind: OperationKind = .copy,
        completedItems: Int = 2,
        totalItems: Int = 4,
        completedBytes: Int64 = 500,
        totalBytes: Int64 = 2000
    ) -> OperationProgress {
        OperationProgress(
            kind: kind,
            currentItemName: "belge.pdf",
            completedItems: completedItems,
            totalItems: totalItems,
            completedBytes: completedBytes,
            totalBytes: totalBytes
        )
    }

    func testFractionUsesBytesWhenAvailable() {
        let model = FileOperationViewModel(progress: makeProgress())
        XCTAssertEqual(model.fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(model.percentText, "25%")
    }

    func testByteCountTextOnlyWhenTotalKnown() {
        let known = FileOperationViewModel(progress: makeProgress())
        XCTAssertTrue(known.showsByteCount)
        XCTAssertTrue(known.byteCountText.contains(" / "))

        let unknown = FileOperationViewModel(progress: makeProgress(totalBytes: 0))
        XCTAssertFalse(unknown.showsByteCount)
    }

    func testFractionFallsBackToItemCount() {
        let model = FileOperationViewModel(progress: makeProgress(completedItems: 1, totalItems: 4, totalBytes: 0))
        XCTAssertEqual(model.fraction, 0.25, accuracy: 0.0001)
    }

    func testEmptyProgressIsZero() {
        let model = FileOperationViewModel(progress: makeProgress(completedItems: 0, totalItems: 0, completedBytes: 0, totalBytes: 0))
        XCTAssertEqual(model.fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(model.percentText, "0%")
    }

    func testTitleFollowsOperationKind() {
        let progress = makeProgress(kind: .trash)
        let model = FileOperationViewModel(progress: progress)
        XCTAssertEqual(model.title, progress.kind.localizedTitle)
        XCTAssertEqual(model.currentItemName, "belge.pdf")
    }

    func testShortcutCatalogIsConsistent() {
        let shortcuts = KeyboardShortcutManager.all
        XCTAssertEqual(shortcuts.count, 20)
        XCTAssertTrue(shortcuts.allSatisfy { !$0.keys.isEmpty && !$0.titleKey.isEmpty })
        XCTAssertEqual(Set(shortcuts.map(\.id)).count, shortcuts.count)
        XCTAssertTrue(shortcuts.contains { $0.keys == "Space" })
        XCTAssertTrue(shortcuts.contains { $0.keys == "⌘⌫" })
    }

    func testBareKeyMapping() {
        XCTAssertEqual(KeyboardShortcutManager.action(keyCode: 49, modifiers: []), .quickLook)
        XCTAssertEqual(KeyboardShortcutManager.action(keyCode: 36, modifiers: []), .open)
        XCTAssertEqual(KeyboardShortcutManager.action(keyCode: 76, modifiers: []), .open)
        XCTAssertEqual(KeyboardShortcutManager.action(keyCode: 51, modifiers: []), .goUp)
        XCTAssertNil(KeyboardShortcutManager.action(keyCode: 51, modifiers: .command))
        XCTAssertNil(KeyboardShortcutManager.action(keyCode: 0, modifiers: []))
    }
}

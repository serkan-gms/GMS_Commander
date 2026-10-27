//
//  FormatterTests.swift
//  GMSCommanderTests
//
//  Türkçe biçimlendiricilerin (boyut, izin, tarih, hata) testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FormatterTests: XCTestCase {
    func testFileSizeFormatterScalesUnits() {
        XCTAssertEqual(FileSizeFormatter.string(fromBytes: 0), "0 bayt")
        XCTAssertEqual(FileSizeFormatter.string(fromBytes: 512).contains("bayt"), true)
        XCTAssertTrue(FileSizeFormatter.string(fromBytes: 2_048).contains("KB"))
        XCTAssertTrue(FileSizeFormatter.string(fromBytes: 5 * 1_048_576).contains("MB"))
        XCTAssertTrue(FileSizeFormatter.string(fromBytes: 3 * 1_073_741_824).contains("GB"))
    }

    func testFileSizeFormatterForTotalSkipsDirectories() throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        try TestSupport.makeDirectory(named: "Klasör", in: directory)
        try TestSupport.writeFile(named: "a.txt", contents: "12345", in: directory)

        let snapshot = try FileManagerService.listDirectorySync(at: directory, includeHidden: false)
        let total = FileSizeFormatter.string(forTotalOf: snapshot.items)

        XCTAssertTrue(total.contains("5"))
    }

    func testPermissionsFormatterSymbolicAndOctal() {
        XCTAssertEqual(PermissionsFormatter.symbolicString(fromMode: 0o755), "rwxr-xr-x")
        XCTAssertEqual(PermissionsFormatter.symbolicString(fromMode: 0o644), "rw-r--r--")
        XCTAssertEqual(PermissionsFormatter.octalString(fromMode: 0o644), "644")
    }

    func testDateFormatterHandlesNil() {
        XCTAssertEqual(DateFormatterHelper.listString(from: nil), "—")
        XCTAssertEqual(DateFormatterHelper.detailedString(from: nil), "—")
        XCTAssertFalse(DateFormatterHelper.listString(from: Date()).isEmpty)
    }

    func testErrorMessagesAreLocalizedTurkish() {
        let errors: [Error] = [
            FileOperationError.destinationExists(URL(fileURLWithPath: "/tmp/a")),
            FileOperationError.invalidName("x"),
            FileOperationError.sourceMissing(URL(fileURLWithPath: "/tmp/b")),
            FileOperationError.accessDenied(URL(fileURLWithPath: "/tmp/c")),
            FileOperationError.sameLocation,
            FileOperationError.cancelled
        ]

        for error in errors {
            let title = ErrorMessages.title(for: error)
            let message = ErrorMessages.message(for: error)
            XCTAssertFalse(title.isEmpty, "Başlık boş: \(error)")
            XCTAssertFalse(message.isEmpty, "Mesaj boş: \(error)")
        }
    }

    func testOperationProgressFraction() {
        var progress = OperationProgress(
            kind: .copy,
            currentItemName: "a",
            completedItems: 1,
            totalItems: 4,
            completedBytes: 50,
            totalBytes: 200
        )
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)

        progress.totalBytes = 0
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)

        progress.totalItems = 0
        XCTAssertEqual(progress.fraction, 0)
    }

    func testConflictPolicyAutomaticDecision() {
        XCTAssertNil(ConflictPolicy.ask.automaticDecision)
        XCTAssertEqual(ConflictPolicy.overwrite.automaticDecision, .overwrite)
        XCTAssertEqual(ConflictPolicy.skip.automaticDecision, .skip)
        XCTAssertEqual(ConflictPolicy.keepBoth.automaticDecision, .keepBoth)
    }

    func testTransferModeKind() {
        XCTAssertEqual(TransferMode.copy.operationKind, .copy)
        XCTAssertEqual(TransferMode.move.operationKind, .move)
    }
}

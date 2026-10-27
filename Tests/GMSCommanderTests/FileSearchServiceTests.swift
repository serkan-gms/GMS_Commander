//
//  FileSearchServiceTests.swift
//  GMSCommanderTests
//
//  Ada göre özyinelemeli arama testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FileSearchServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.remove(directory)
    }

    func testFindsNestedFiles() throws {
        let nested = try TestSupport.makeDirectory(named: "Alt", in: directory)
        let deeper = try TestSupport.makeDirectory(named: "Daha Derin", in: nested)
        try TestSupport.writeFile(named: "rapor-2025.txt", in: deeper)
        try TestSupport.writeFile(named: "baska.txt", in: directory)

        let outcome = FileSearchService.searchSync(root: directory, query: "rapor", includeHidden: false)

        XCTAssertEqual(outcome.items.count, 1)
        XCTAssertEqual(outcome.items.first?.name, "rapor-2025.txt")
        XCTAssertNotNil(outcome.items.first?.relativePath)
        XCTAssertFalse(outcome.reachedLimit)
    }

    func testSearchIsCaseAndTurkishInsensitive() throws {
        try TestSupport.writeFile(named: "İSTANBUL Raporu.txt", in: directory)
        try TestSupport.writeFile(named: "ıspanak.txt", in: directory)

        let upper = FileSearchService.searchSync(root: directory, query: "istanbul", includeHidden: false)
        XCTAssertEqual(upper.items.count, 1)

        let dotless = FileSearchService.searchSync(root: directory, query: "ISPANAK".lowercased(), includeHidden: false)
        XCTAssertEqual(dotless.items.count, 1)
    }

    func testSearchSkipsHiddenWhenDisabled() throws {
        try TestSupport.writeFile(named: ".gizli-rapor.txt", in: directory)
        try TestSupport.writeFile(named: "rapor.txt", in: directory)

        let withoutHidden = FileSearchService.searchSync(root: directory, query: "rapor", includeHidden: false)
        let withHidden = FileSearchService.searchSync(root: directory, query: "rapor", includeHidden: true)

        XCTAssertEqual(withoutHidden.items.count, 1)
        XCTAssertEqual(withHidden.items.count, 2)
    }

    func testSearchRespectsLimit() throws {
        for index in 0..<6 {
            try TestSupport.writeFile(named: "kayit-\(index).txt", in: directory)
        }

        let outcome = FileSearchService.searchSync(root: directory, query: "kayit", includeHidden: false, limit: 3)

        XCTAssertEqual(outcome.items.count, 3)
        XCTAssertTrue(outcome.reachedLimit)
    }

    func testEmptyQueryReturnsNothing() throws {
        try TestSupport.writeFile(named: "a.txt", in: directory)
        let outcome = FileSearchService.searchSync(root: directory, query: "   ", includeHidden: false)
        XCTAssertTrue(outcome.items.isEmpty)
    }

    func testNormalizeLowercasesAndFoldsTurkishCharacters() {
        XCTAssertEqual(FileSearchService.normalize("İSTANBUL"), "istanbul")
        XCTAssertEqual(FileSearchService.normalize("IŞIK"), "isik")
    }
}

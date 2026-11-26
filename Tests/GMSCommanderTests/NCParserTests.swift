import XCTest
import SwiftUI
@testable import GMS_Commander

final class NCParserTests: XCTestCase {
    func testModalMovesAndUnits() {
        let program = NCParser.parse("""
        G21 G90 G0 X0 Y0 Z0
        G1 X10
        Y5
        G91 X-2 Z1
        G20 G90 X1 Y0 Z0
        """)
        XCTAssertEqual(program.segments.count, 4)
        XCTAssertEqual(program.segments[1].end, NCPoint(x: 10, y: 5, z: 0))
        XCTAssertEqual(program.segments[2].end, NCPoint(x: 8, y: 5, z: 1))
        XCTAssertEqual(program.segments[3].end, NCPoint(x: 25.4, y: 0, z: 0))
    }

    func testArcsAndPlanesReachTheirEndpoints() {
        let program = NCParser.parse("""
        G90 G0 X1 Y0 Z0
        G17 G3 X0 Y1 I-1 J0
        G18 G3 X-1 Z1 K1
        """)
        XCTAssertFalse(program.warnings.contains(.invalidArc))
        XCTAssertGreaterThan(program.segments.count, 2)
        XCTAssertEqual(program.segments.last?.end, NCPoint(x: -1, y: 1, z: 1))
    }

    func testReferenceMoveAndUnsupportedCycleDoNotDrawFalsePaths() {
        let program = NCParser.parse("""
        G90 G0 X0 Y0 Z5
        G28 G91 Z0
        G90 G0 X10 Y10
        Z15
        G1 Z0
        G81 X20 Y20 Z-1
        X30
        G80
        G0 X1 Y2 Z3
        G1 X2
        """)
        XCTAssertEqual(program.segments.count, 2)
        XCTAssertEqual(program.segments[0].start, NCPoint(x: 10, y: 10, z: 15))
        XCTAssertEqual(program.segments[1].start, NCPoint(x: 1, y: 2, z: 3))
        XCTAssertFalse(program.warnings.isEmpty)
    }

    func testExtensionsAreCaseInsensitive() {
        XCTAssertTrue(NCFile.supports(URL(fileURLWithPath: "/tmp/example.NC")))
        XCTAssertTrue(NCFile.supports(URL(fileURLWithPath: "/tmp/example.gcode")))
        XCTAssertFalse(NCFile.supports(URL(fileURLWithPath: "/tmp/example.txt")))
    }

    func testCRLFLineNumbersMatchSource() {
        let program = NCParser.parse("G0 X0 Y0 Z0\r\nG1 X1\r\nX2\r\n")
        XCTAssertEqual(program.segments.map(\.line), [1, 2])
    }

    func testCompensationAndInvalidArcAreNotDrawn() {
        let program = NCParser.parse("""
        G0 X0 Y0 Z0
        G41 G1 X1
        X2
        G40 G0 X3 Y0 Z0
        G2 X10 Y0 R1
        G1 X11
        """)
        XCTAssertTrue(program.warnings.contains(.compensation))
        XCTAssertTrue(program.warnings.contains(.invalidArc))
        XCTAssertTrue(program.segments.isEmpty)
    }

    func testReferenceMoveWithoutAxesMakesEntirePositionUnknown() {
        let program = NCParser.parse("G0 X0 Y0 Z0\nG28\nG0 X1\nG1 X2")
        XCTAssertTrue(program.segments.isEmpty)
        XCTAssertTrue(program.warnings.contains(.reference))
    }

    func testLineStatesAndUnknownFeedMode() {
        let program = NCParser.parse("G21 G94 G0 X0 Y0 Z0\nG1 X1 F100 M8\n(comment)\nG28 Z0")
        XCTAssertEqual(program.lines[1].position, NCPoint(x: 1, y: 0, z: 0))
        XCTAssertEqual(program.lines[2].segmentCount, 1)
        XCTAssertEqual(program.lines[1].feed, 100)
        XCTAssertNil(program.lines[3].position)
        let unknown = NCParser.parse("G21 G0 X0 Y0 Z0\nG1 X1 F100\nG95 F2 X2")
        XCTAssertNil(unknown.lines[1].feed)
        XCTAssertNil(unknown.lines[2].feed)
    }

    func testCodeToolsPreserveCommentsAndUnits() throws {
        let input = "G21 G94\r\nG1 F100 S1000 (F77)\r\nG20 F2 ; F9\r\nM30\r\n"
        XCTAssertEqual(
            try NCCodeTools.change(input, .feed(254)),
            "G21 G94\r\nG1 F254 S1000 (F77)\r\nG20 F10 ; F9\r\nM30\r\n"
        )
        XCTAssertThrowsError(try NCCodeTools.change("G21 G94 F100\nG95 F2", .feed(200)))
        XCTAssertThrowsError(try NCCodeTools.change("G94 F100", .feed(200)))
        XCTAssertThrowsError(try NCCodeTools.changeCoolant("G21\nM30\n%", line: 1, code: 8, insert: true))
        XCTAssertEqual(
            try NCCodeTools.change("N20 S5000 M03\nM30\n", .spindle(5500), assumeSpindleRPM: true),
            "N20 S5500 M03\nM30\n"
        )
        XCTAssertThrowsError(try NCCodeTools.change("G96 S5000", .spindle(5500), assumeSpindleRPM: true))
    }

    @MainActor
    func testPreviewPreferencesReopen() throws {
        let suite = "GMSCommanderTests.NCPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NCPreviewSettings(defaults: defaults)
        settings.speed = 2
        settings.showingHUD = false
        settings.pathMode = .remaining
        settings.toolMode = .cutter
        settings.splitRatio = 0.4
        XCTAssertTrue(settings.setToolColor(.red))
        let camera = NCCameraState(position: [12, -9, 6], target: [1, 2, 3], orthographic: true, orthographicScale: 4)
        settings.camera = camera
        let reopened = NCPreviewSettings(defaults: defaults)
        XCTAssertEqual(reopened.speed, 2)
        XCTAssertFalse(reopened.showingHUD)
        XCTAssertEqual(reopened.pathMode, .remaining)
        XCTAssertEqual(reopened.toolMode, .cutter)
        XCTAssertEqual(reopened.splitRatio, 0.4)
        XCTAssertEqual(reopened.camera, camera)
        XCTAssertEqual(NCPreviewView.coordinateText(NCPoint(x: 1.25, y: -2, z: 3)), "X 1.250  Y -2.000  Z 3.000")
        XCTAssertEqual(NCPreviewView.coordinateText(nil), L.t("nc.hud.unknown"))
    }
}

import Foundation

struct NCPoint: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
}

struct NCSegment: Sendable {
    let start: NCPoint
    let end: NCPoint
    let rapid: Bool
    let line: Int
    let feed: Double?
}

struct NCLineState: Sendable {
    let position: NCPoint?
    let segmentCount: Int
    let feed: Double?
    let spindle: Double?
    let coolant: String?
}

struct NCProgram: Sendable {
    let segments: [NCSegment]
    let lines: [NCLineState]
    let warnings: [NCWarning]
}

enum NCWarning: String, Sendable, Comparable {
    case limit, macro, axis, subprogram, reference, compensation, unsupported, unknownPosition, invalidArc

    static func < (lhs: NCWarning, rhs: NCWarning) -> Bool { lhs.rawValue < rhs.rawValue }
    var localizedMessage: String { L.t("nc.warning.\(rawValue)") }
}

enum NCFile {
    static func supports(_ url: URL) -> Bool {
        ["nc", "gcode", "cnc"].contains(url.pathExtension.lowercased())
    }
}

enum NCParser {
    private static let words = try! NSRegularExpression(
        pattern: #"([A-Z])\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))"#
    )
    private static let comments = try! NSRegularExpression(pattern: #"\([^)]*\)|;.*$"#)
    private static let maximumSegments = 1_000_000

    private struct Position {
        var x: Double?
        var y: Double?
        var z: Double?

        var point: NCPoint? {
            guard let x, let y, let z else { return nil }
            return NCPoint(x: x, y: y, z: z)
        }
    }

    static func parse(_ text: String) -> NCProgram {
        var segments: [NCSegment] = []
        var lineStates: [NCLineState] = []
        var warnings = Set<NCWarning>()
        var position = Position()
        var motion = 0
        var motionKnown = true
        var absolute = true
        var absoluteCenter = false
        var unit = 1.0
        var unitKnown = false
        var plane = 17
        var coordinateSystem: Double?
        var compensationActive = false
        var feed: Double?
        var feedRateKnown = false
        var spindle: Double?
        var coolant: String?

        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for (lineIndex, rawLine) in normalizedText.components(separatedBy: "\n").enumerated() {
            if Task.isCancelled { break }
            defer {
                lineStates.append(NCLineState(
                    position: position.point, segmentCount: segments.count,
                    feed: feed, spindle: spindle, coolant: coolant
                ))
            }
            if segments.count >= maximumSegments {
                warnings.insert(.limit)
                break
            }
            let upper = rawLine.uppercased()
            let line = comments.stringByReplacingMatches(
                in: upper, range: NSRange(upper.startIndex..., in: upper), withTemplate: ""
            )
            if line.contains("#") || line.contains("=") || line.contains("[") || line.contains("]") {
                warnings.insert(.macro)
                motionKnown = false
                position = Position()
                continue
            }
            var parameters: [String: [Double]] = [:]
            var invalidNumber = false
            for match in words.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let keyRange = Range(match.range(at: 1), in: line),
                      let valueRange = Range(match.range(at: 2), in: line),
                      let value = Double(line[valueRange]) else {
                    invalidNumber = true
                    continue
                }
                guard value.isFinite, abs(value) <= 100_000_000 else {
                    invalidNumber = true
                    continue
                }
                parameters[String(line[keyRange]), default: []].append(value)
            }
            if invalidNumber || ["A", "B", "C", "U", "V", "W"].contains(where: { parameters[$0] != nil }) {
                warnings.insert(.axis)
                position = Position()
                motionKnown = false
                continue
            }
            if (parameters["M"] ?? []).contains(where: { $0 == 98 || $0 == 99 }) {
                warnings.insert(.subprogram)
                position = Position()
                motionKnown = false
                continue
            }
            if (parameters["M"] ?? []).contains(where: { ![0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 30].contains($0) }) {
                warnings.insert(.unsupported)
                position = Position()
                motionKnown = false
                continue
            }
            let codes = parameters["G"] ?? []
            if let value = parameters["S"]?.first { spindle = value }
            for code in parameters["M"] ?? [] {
                if code == 7 { coolant = "M7" }
                else if code == 8 { coolant = "M8" }
                else if code == 9 { coolant = "M9" }
            }
            var skipMotion = false
            var unknownMotion = false
            for code in codes {
                switch code {
                case 0, 1, 2, 3:
                    motion = Int(code)
                    motionKnown = true
                case 17, 18, 19: plane = Int(code)
                case 20, 21:
                    let newUnit = code == 20 ? 25.4 : 1.0
                    if !unitKnown || unit != newUnit { feed = nil }
                    unit = newUnit
                    unitKnown = true
                case 90: absolute = true
                case 91: absolute = false
                case 90.1: absoluteCenter = true
                case 91.1: absoluteCenter = false
                case 28, 30, 53:
                    skipMotion = true
                    warnings.insert(.reference)
                case 40: compensationActive = false
                case 41, 42:
                    compensationActive = true
                    warnings.insert(.compensation)
                case 54...59:
                    if let coordinateSystem, coordinateSystem != code { position = Position() }
                    coordinateSystem = code
                case 80: motionKnown = false
                case 94: feedRateKnown = true
                case 49, 97:
                    break
                case 93, 95:
                    feedRateKnown = false
                    feed = nil
                    warnings.insert(.unsupported)
                default:
                    skipMotion = true
                    unknownMotion = true
                    warnings.insert(.unsupported)
                }
            }
            if unknownMotion { motionKnown = false }
            if let value = parameters["F"]?.first {
                feed = feedRateKnown && unitKnown ? value * unit : nil
            }

            let axes = ["X", "Y", "Z"].map { parameters[$0]?.first.map { $0 * unit } }
            if compensationActive {
                if axes.contains(where: { $0 != nil }) { position = Position() }
                continue
            }
            if skipMotion {
                if unknownMotion || (axes.allSatisfy { $0 == nil } && codes.contains(where: { $0 == 28 || $0 == 30 })) {
                    position = Position()
                } else {
                    if axes[0] != nil { position.x = nil }
                    if axes[1] != nil { position.y = nil }
                    if axes[2] != nil { position.z = nil }
                }
                continue
            }
            guard motionKnown else { continue }
            let hasAxis = axes.contains { $0 != nil }
            let hasCenter = ["I", "J", "K", "R"].contains { parameters[$0] != nil }
            guard hasAxis || ((motion == 2 || motion == 3) && hasCenter) else { continue }

            func updated(_ old: Double?, _ value: Double?) -> Double? {
                guard let value else { return old }
                if absolute { return value }
                return old.map { $0 + value }
            }
            let next = Position(
                x: updated(position.x, axes[0]),
                y: updated(position.y, axes[1]),
                z: updated(position.z, axes[2])
            )
            guard let start = position.point, let end = next.point else {
                warnings.insert(.unknownPosition)
                position = next
                continue
            }
            if motion == 0 || motion == 1 {
                segments.append(NCSegment(start: start, end: end, rapid: motion == 0, line: lineIndex, feed: feed))
                position = next
                continue
            }
            let offsets = ["I", "J", "K"].map { parameters[$0]?.first.map { $0 * unit } }
            guard let arc = arcPoints(
                start: start, end: end, plane: plane, clockwise: motion == 2,
                offsets: offsets, radius: parameters["R"]?.first.map { $0 * unit },
                absoluteCenter: absoluteCenter
            ) else {
                warnings.insert(.invalidArc)
                position = Position()
                motionKnown = false
                continue
            }
            if segments.count + arc.count > maximumSegments {
                warnings.insert(.limit)
                break
            }
            var previous = start
            for point in arc {
                segments.append(NCSegment(start: previous, end: point, rapid: false, line: lineIndex, feed: feed))
                previous = point
            }
            position = next
        }
        return NCProgram(segments: segments, lines: lineStates, warnings: warnings.sorted())
    }

    private static func arcPoints(
        start: NCPoint, end: NCPoint, plane: Int, clockwise: Bool,
        offsets: [Double?], radius: Double?, absoluteCenter: Bool
    ) -> [NCPoint]? {
        let startValues = [start.x, start.y, start.z]
        let endValues = [end.x, end.y, end.z]
        let indices = plane == 17 ? (0, 1, 2) : (plane == 18 ? (2, 0, 1) : (1, 2, 0))
        let (a, b, orthogonal) = indices
        let sa = startValues[a], sb = startValues[b], ea = endValues[a], eb = endValues[b]
        let dx = ea - sa, dy = eb - sb
        let centerA: Double
        let centerB: Double
        if let signedRadius = radius {
            let distance = hypot(dx, dy)
            let r = abs(signedRadius)
            guard distance > 1e-9, r > 0, distance <= 2 * r + 1e-8 else { return nil }
            let h = sqrt(max(0, r * r - distance * distance / 4))
            let midpointA = (sa + ea) / 2, midpointB = (sb + eb) / 2
            let candidates = [
                (midpointA - dy / distance * h, midpointB + dx / distance * h),
                (midpointA + dy / distance * h, midpointB - dx / distance * h)
            ]
            func sweep(_ center: (Double, Double)) -> Double {
                var angle = atan2(eb - center.1, ea - center.0) - atan2(sb - center.1, sa - center.0)
                if clockwise && angle >= 0 { angle -= 2 * .pi }
                if !clockwise && angle <= 0 { angle += 2 * .pi }
                return angle
            }
            let sorted = candidates.sorted { abs(sweep($0)) < abs(sweep($1)) }
            let selected = signedRadius < 0 ? sorted[1] : sorted[0]
            centerA = selected.0
            centerB = selected.1
        } else {
            guard offsets[a] != nil || offsets[b] != nil else { return nil }
            centerA = absoluteCenter ? (offsets[a] ?? sa) : sa + (offsets[a] ?? 0)
            centerB = absoluteCenter ? (offsets[b] ?? sb) : sb + (offsets[b] ?? 0)
        }
        let r = hypot(sa - centerA, sb - centerB)
        guard r > 1e-9, abs(hypot(ea - centerA, eb - centerB) - r) <= max(0.01, r * 0.001) else {
            return nil
        }
        let startAngle = atan2(sb - centerB, sa - centerA)
        var sweep = atan2(eb - centerB, ea - centerA) - startAngle
        if clockwise && sweep >= 0 { sweep -= 2 * .pi }
        if !clockwise && sweep <= 0 { sweep += 2 * .pi }
        let count = min(2048, max(1, Int(ceil(max(abs(sweep) / (.pi / 36), abs(sweep) * r / 0.75)))))
        return (1...count).map { index in
            if index == count { return end }
            let t = Double(index) / Double(count)
            let angle = startAngle + sweep * t
            var values = startValues
            values[a] = centerA + r * cos(angle)
            values[b] = centerB + r * sin(angle)
            values[orthogonal] = startValues[orthogonal] + (endValues[orthogonal] - startValues[orthogonal]) * t
            return NCPoint(x: values[0], y: values[1], z: values[2])
        }
    }
}

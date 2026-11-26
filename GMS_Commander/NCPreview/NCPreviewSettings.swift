import SwiftUI
import AppKit

struct NCCameraState: Equatable {
    let position: [Double]
    let target: [Double]
    let orthographic: Bool
    let orthographicScale: Double
}

@MainActor
final class NCPreviewSettings: ObservableObject {
    private enum Keys {
        static let speed = "nc.preview.speed"
        static let hud = "nc.preview.hud"
        static let path = "nc.preview.path"
        static let tool = "nc.preview.tool"
        static let color = "nc.preview.color"
        static let pointSize = "nc.preview.pointSize"
        static let diameter = "nc.preview.diameter"
        static let rapid = "nc.preview.rapid"
        static let splitRatio = "nc.preview.splitRatio"
        static let camera = "nc.preview.camera"
        static let windowFrame = "nc.preview.windowFrame"
        static let saveDirectory = "nc.preview.saveDirectory"
    }

    static let sharedDefaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: "com.gms.ncpreview.shared") else {
            preconditionFailure("NC preview preferences domain is unavailable")
        }
        return defaults
    }()

    private let defaults: UserDefaults
    @Published var speed: Double { didSet { defaults.set(speed, forKey: Keys.speed) } }
    @Published var showingHUD: Bool { didSet { defaults.set(showingHUD, forKey: Keys.hud) } }
    @Published var pathMode: NCPathMode { didSet { defaults.set(pathMode.rawValue, forKey: Keys.path) } }
    @Published var toolMode: NCToolMode { didSet { defaults.set(toolMode.rawValue, forKey: Keys.tool) } }
    @Published private(set) var toolColor: Color
    @Published var pointSize: Double { didSet { defaults.set(pointSize, forKey: Keys.pointSize) } }
    @Published var rapidValue: String { didSet { defaults.set(rapidValue, forKey: Keys.rapid) } }
    @Published var diameter: Double {
        didSet {
            if diameter.isFinite, diameter > 0 {
                defaults.set(diameter, forKey: Keys.diameter)
            }
        }
    }
    var splitRatio: Double {
        didSet {
            if splitRatio.isFinite, (0...1).contains(splitRatio) {
                defaults.set(splitRatio, forKey: Keys.splitRatio)
            }
        }
    }

    convenience init() {
        self.init(defaults: Self.sharedDefaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let speed = defaults.double(forKey: Keys.speed)
        self.speed = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0].contains(speed) ? speed : 1
        showingHUD = defaults.object(forKey: Keys.hud) as? Bool ?? true
        pathMode = defaults.string(forKey: Keys.path).flatMap(NCPathMode.init(rawValue:)) ?? .standard
        toolMode = defaults.string(forKey: Keys.tool).flatMap(NCToolMode.init(rawValue:)) ?? .point
        let pointSize = defaults.double(forKey: Keys.pointSize)
        self.pointSize = pointSize.isFinite && (4...40).contains(pointSize) ? pointSize : 12
        rapidValue = defaults.string(forKey: Keys.rapid) ?? ""
        let diameter = defaults.double(forKey: Keys.diameter)
        self.diameter = diameter.isFinite && diameter > 0 ? diameter : 1
        let ratio = defaults.double(forKey: Keys.splitRatio)
        splitRatio = ratio.isFinite && ratio > 0 && ratio < 1 ? ratio : 390.0 / 1100.0
        let color = defaults.array(forKey: Keys.color) as? [Double]
        if let color, color.count == 4, color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
            toolColor = Color(.sRGB, red: color[0], green: color[1], blue: color[2], opacity: color[3])
        } else {
            toolColor = .yellow
        }
    }

    func setToolColor(_ color: Color) -> Bool {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return false }
        defaults.set([rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent], forKey: Keys.color)
        toolColor = color
        return true
    }

    static func savedWindowFrame(defaults: UserDefaults) -> NSRect? {
        guard let values = defaults.array(forKey: Keys.windowFrame) as? [Double],
              values.count == 4, values.allSatisfy(\.isFinite),
              values[2] >= 850, values[3] >= 600,
              values[2] <= 10000, values[3] <= 10000 else { return nil }
        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    static func saveWindowFrame(_ frame: NSRect, defaults: UserDefaults) {
        defaults.set([frame.origin.x, frame.origin.y, frame.width, frame.height], forKey: Keys.windowFrame)
    }

    static func saveDirectory(for sourceURL: URL, defaults: UserDefaults) -> URL {
        guard let path = defaults.string(forKey: Keys.saveDirectory) else {
            return sourceURL.deletingLastPathComponent()
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return sourceURL.deletingLastPathComponent()
        }
        return directory
    }

    static func saveLastSaveDirectory(_ directory: URL, defaults: UserDefaults) {
        defaults.set(directory.standardizedFileURL.path, forKey: Keys.saveDirectory)
    }

    var camera: NCCameraState? {
        get {
            guard let values = defaults.array(forKey: Keys.camera) as? [Double],
                  values.count == 8, values.allSatisfy(\.isFinite),
                  values[7] > 0, values[6] == 0 || values[6] == 1 else { return nil }
            let position = Array(values[0..<3])
            let target = Array(values[3..<6])
            guard zip(position, target).contains(where: { abs($0 - $1) > 0.0001 }) else { return nil }
            return NCCameraState(position: position, target: target, orthographic: values[6] == 1, orthographicScale: values[7])
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Keys.camera)
                return
            }
            defaults.set(newValue.position + newValue.target + [newValue.orthographic ? 1 : 0, newValue.orthographicScale], forKey: Keys.camera)
        }
    }
}

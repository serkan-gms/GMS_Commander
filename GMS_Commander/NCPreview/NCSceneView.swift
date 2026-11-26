import SwiftUI
import AppKit
import SceneKit
import simd

final class NCInteractiveSceneView: SCNView {
    var zoom: ((CGFloat) -> Void)?
    var dragCamera: ((CGFloat, CGFloat, Bool) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
        zoom?(delta)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {
        dragCamera?(event.deltaX, event.deltaY, event.modifierFlags.contains(.command))
    }
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        dragCamera?(event.deltaX, event.deltaY, event.modifierFlags.contains(.command))
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {
        dragCamera?(event.deltaX, event.deltaY, true)
    }
}

enum NCPathMode: String, CaseIterable, Identifiable {
    case standard, highlighted, remaining
    var id: String { rawValue }
    var title: String { L.t("nc.path.\(rawValue)") }
}

enum NCToolMode: String, CaseIterable, Identifiable {
    case point, cutter
    var id: String { rawValue }
    var title: String { L.t("nc.tool.\(rawValue)") }
}

enum NCCameraAction {
    case fit, home, top, front, right, iso, zoomIn, zoomOut, left, rotateRight, panLeft, panRight, panUp, panDown
}

struct NCCameraRequest {
    let id = UUID()
    let action: NCCameraAction
}

struct NCSceneView: NSViewRepresentable {
    let program: NCProgram
    let revision: UUID
    let progress: Double
    let selectedPosition: NCPoint?
    let positionUnknown: Bool
    let mode: NCPathMode
    let toolMode: NCToolMode
    let toolColor: Color
    let pointSize: Double
    let toolDiameter: Double
    let cameraRequest: NCCameraRequest?
    let settings: NCPreviewSettings

    @MainActor
    final class Coordinator {
        private let settings: NCPreviewSettings?

        init(settings: NCPreviewSettings? = nil) { self.settings = settings }

        final class Paths {
            let indices: [Int]
            let source: SCNGeometrySource
            let normal: SCNNode
            let processed: SCNNode
            let normalMaterial: SCNMaterial
            let processedMaterial: SCNMaterial
            var previous: (Int, NCPathMode)?

            init(indices: [Int], source: SCNGeometrySource, normalMaterial: SCNMaterial, processedMaterial: SCNMaterial) {
                self.indices = indices
                self.source = source
                self.normalMaterial = normalMaterial
                self.processedMaterial = processedMaterial
                normal = SCNNode()
                processed = SCNNode()
                normal.renderingOrder = 1
                processed.renderingOrder = 2
            }

            func update(completed: Int, mode: NCPathMode) {
                let effectiveCompleted = mode == .standard ? 0 : completed
                if let previous, previous.0 == effectiveCompleted && previous.1 == mode { return }
                previous = (effectiveCompleted, mode)
                let normalRange = mode == .standard ? 0..<indices.count : completed..<indices.count
                let processedRange = mode == .highlighted ? 0..<completed : 0..<0
                update(normal, range: normalRange, material: normalMaterial)
                update(processed, range: processedRange, material: processedMaterial)
            }

            private func update(_ node: SCNNode, range: Range<Int>, material: SCNMaterial) {
                guard !range.isEmpty else {
                    node.isHidden = true
                    return
                }
                let indices = Array(UInt32(range.lowerBound * 2)..<UInt32(range.upperBound * 2))
                let element = SCNGeometryElement(indices: indices, primitiveType: .line)
                let geometry = SCNGeometry(sources: [source], elements: [element])
                geometry.materials = [material]
                node.geometry = geometry
                node.isHidden = false
            }
        }
        var revision: UUID?
        var cameraRequestID: UUID?
        var paths: [Paths] = []
        var marker: SCNNode?
        var target: SCNNode?
        var camera: SCNNode?
        var center = NCPoint(x: 0, y: 0, z: 0)
        var scale = 1.0
        var toolKey = ""

        func vector(_ point: NCPoint) -> SCNVector3 {
            SCNVector3(
                Float((point.x - center.x) * scale),
                Float((point.y - center.y) * scale),
                Float((point.z - center.z) * scale)
            )
        }

        func completedCount(in values: [Int], progress: Int) -> Int {
            var low = 0, high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] < progress { low = mid + 1 } else { high = mid }
            }
            return low
        }

        func zoom(by delta: CGFloat) {
            guard delta.isFinite, delta != 0, let camera, let target, let lens = camera.camera else { return }
            let factor = Float(exp(Double(max(-40, min(40, -delta))) * 0.08))
            if lens.usesOrthographicProjection {
                lens.orthographicScale = min(1000, max(0.01, lens.orthographicScale * Double(factor)))
            } else {
                let offset = camera.simdPosition - target.simdPosition
                let distance = simd_length(offset)
                guard distance > 0 else { return }
                let newDistance = min(Float(1000), max(Float(0.05), distance * factor))
                camera.simdPosition = target.simdPosition + offset * (newDistance / distance)
            }
            saveCamera()
        }

        func drag(dx: CGFloat, dy: CGFloat, pan: Bool, height: CGFloat) {
            guard let camera, let target, height > 0 else { return }
            let offset = camera.simdPosition - target.simdPosition
            let distance = simd_length(offset)
            guard distance > 0 else { return }
            let forward = -offset / distance
            let worldUp = SIMD3<Float>(0, 0, 1)
            var right = simd_cross(forward, worldUp)
            if simd_length_squared(right) < 0.0001 { right = SIMD3<Float>(1, 0, 0) }
            right = simd_normalize(right)
            let up = simd_normalize(simd_cross(right, forward))
            if pan {
                let scale = camera.camera?.usesOrthographicProjection == true
                    ? Float((camera.camera?.orthographicScale ?? 8) * 2 / height)
                    : distance * 1.2 / Float(height)
                let translation = (-Float(dx) * right + Float(dy) * up) * scale
                camera.simdPosition += translation
                target.simdPosition += translation
            } else {
                let yaw = simd_quatf(angle: -Float(dx) * 0.008, axis: worldUp)
                let yawed = yaw.act(offset)
                let pitch = simd_quatf(angle: -Float(dy) * 0.008, axis: right)
                let candidate = pitch.act(yawed)
                let alignment = abs(simd_dot(simd_normalize(candidate), worldUp))
                let oldAlignment = abs(simd_dot(simd_normalize(yawed), worldUp))
                camera.simdPosition = target.simdPosition
                    + (alignment < 0.995 || alignment < oldAlignment ? candidate : yawed)
                if let look = camera.constraints?.first as? SCNLookAtConstraint {
                    let currentOffset = simd_normalize(camera.simdPosition - target.simdPosition)
                    look.worldUp = abs(simd_dot(currentOffset, worldUp)) > 0.99
                        ? SCNVector3(0, 1, 0) : SCNVector3(0, 0, 1)
                }
            }
            saveCamera()
        }

        var cameraState: NCCameraState? {
            guard let camera, let target, let lens = camera.camera else { return nil }
            return NCCameraState(
                position: [Double(camera.position.x), Double(camera.position.y), Double(camera.position.z)],
                target: [Double(target.position.x), Double(target.position.y), Double(target.position.z)],
                orthographic: lens.usesOrthographicProjection,
                orthographicScale: lens.orthographicScale
            )
        }

        func saveCamera() {
            guard let cameraState else { return }
            settings?.camera = cameraState
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(settings: settings) }

    func makeNSView(context: Context) -> SCNView {
        let view = NCInteractiveSceneView()
        view.backgroundColor = NSColor(calibratedWhite: 0.91, alpha: 1)
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        let coordinator = context.coordinator
        view.zoom = { [weak coordinator] delta in coordinator?.zoom(by: delta) }
        view.dragCamera = { [weak coordinator, weak view] dx, dy, pan in
            guard let view else { return }
            coordinator?.drag(dx: dx, dy: dy, pan: pan, height: view.bounds.height)
        }
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        if c.revision != revision {
            c.revision = revision
            configure(view, coordinator: c)
        }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for path in c.paths {
            let completed = c.completedCount(in: path.indices, progress: Int(progress))
            path.update(completed: completed, mode: mode)
        }
        if let marker = c.marker, !program.segments.isEmpty {
            marker.isHidden = positionUnknown
            let current = min(max(progress, 0), Double(program.segments.count))
            let index = min(Int(current), program.segments.count - 1)
            let segment = program.segments[index]
            let fraction = current >= Double(program.segments.count) ? 1 : current - Double(index)
            let point = selectedPosition ?? NCPoint(
                x: segment.start.x + (segment.end.x - segment.start.x) * fraction,
                y: segment.start.y + (segment.end.y - segment.start.y) * fraction,
                z: segment.start.z + (segment.end.z - segment.start.z) * fraction
            )
            marker.position = c.vector(point)
            let color = NSColor(toolColor).usingColorSpace(.deviceRGB) ?? NSColor.systemYellow
            let key = "\(toolMode.rawValue)-\(pointSize)-\(toolDiameter)-\(color)"
            if c.toolKey != key {
                c.toolKey = key
                let geometry: SCNGeometry
                if toolMode == .point {
                    geometry = SCNSphere(radius: CGFloat(pointSize / 100))
                    marker.eulerAngles = SCNVector3Zero
                    marker.pivot = SCNMatrix4Identity
                } else {
                    let radius = max(0.001, toolDiameter * c.scale / 2)
                    let height = max(radius * 6, 0.01)
                    geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
                    marker.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                    marker.pivot = SCNMatrix4MakeTranslation(0, -CGFloat(height / 2), 0)
                }
                geometry.firstMaterial?.lightingModel = .constant
                geometry.firstMaterial?.diffuse.contents = color.withAlphaComponent(toolMode == .cutter ? 0.6 : 1)
                geometry.firstMaterial?.isDoubleSided = true
                marker.geometry = geometry
            }
        }
        if let request = cameraRequest, c.cameraRequestID != request.id {
            c.cameraRequestID = request.id
            Self.apply(request.action, view: view, coordinator: c)
            c.saveCamera()
        }
        SCNTransaction.commit()
    }

    private func configure(_ view: SCNView, coordinator c: Coordinator) {
        let cameraState = c.cameraState ?? settings.camera
        let scene = SCNScene()
        view.scene = scene
        c.paths = []
        c.toolKey = ""
        guard let first = program.segments.first else {
            c.marker = nil
            c.camera = nil
            c.target = nil
            return
        }
        var minPoint = first.start, maxPoint = first.start
        for segment in program.segments {
            for point in [segment.start, segment.end] {
                minPoint.x = min(minPoint.x, point.x); maxPoint.x = max(maxPoint.x, point.x)
                minPoint.y = min(minPoint.y, point.y); maxPoint.y = max(maxPoint.y, point.y)
                minPoint.z = min(minPoint.z, point.z); maxPoint.z = max(maxPoint.z, point.z)
            }
        }
        c.center = NCPoint(x: (minPoint.x + maxPoint.x) / 2, y: (minPoint.y + maxPoint.y) / 2, z: (minPoint.z + maxPoint.z) / 2)
        c.scale = 10 / max(maxPoint.x - minPoint.x, maxPoint.y - minPoint.y, maxPoint.z - minPoint.z, 0.01)
        let gridZ = Float((minPoint.z - c.center.z) * c.scale - 0.1)
        var gridVertices: [SCNVector3] = []
        for line in -6...6 {
            let value = Float(line)
            gridVertices.append(contentsOf: [
                SCNVector3(-6, value, gridZ), SCNVector3(6, value, gridZ),
                SCNVector3(value, -6, gridZ), SCNVector3(value, 6, gridZ)
            ])
        }
        addLines(gridVertices, color: NSColor(calibratedWhite: 0.62, alpha: 1), to: scene)
        let origin = c.vector(NCPoint(x: 0, y: 0, z: 0))
        addLines([origin, SCNVector3(origin.x + 2, origin.y, origin.z)], color: .systemRed, to: scene)
        addLines([origin, SCNVector3(origin.x, origin.y + 2, origin.z)], color: .systemGreen, to: scene)
        addLines([origin, SCNVector3(origin.x, origin.y, origin.z + 2)], color: .systemBlue, to: scene)
        for rapid in [false, true] {
            let indexed = program.segments.enumerated().filter { $0.element.rapid == rapid }
            guard !indexed.isEmpty else { continue }
            let standardMaterial = SCNMaterial()
            standardMaterial.lightingModel = .constant
            standardMaterial.writesToDepthBuffer = false
            standardMaterial.diffuse.contents = rapid ? NSColor.systemOrange : NSColor.systemBlue
            let completedMaterial = SCNMaterial()
            completedMaterial.lightingModel = .constant
            completedMaterial.writesToDepthBuffer = false
            completedMaterial.diffuse.contents = NSColor.systemGreen
            let chunkSize = 1024
            for start in stride(from: 0, to: indexed.count, by: chunkSize) {
                let chunk = indexed[start..<min(start + chunkSize, indexed.count)]
                let vertices = chunk.flatMap { [c.vector($0.element.start), c.vector($0.element.end)] }
                let path = Coordinator.Paths(
                    indices: chunk.map(\.offset), source: SCNGeometrySource(vertices: vertices),
                    normalMaterial: standardMaterial, processedMaterial: completedMaterial
                )
                scene.rootNode.addChildNode(path.normal)
                scene.rootNode.addChildNode(path.processed)
                c.paths.append(path)
            }
        }
        let marker = SCNNode()
        marker.renderingOrder = 3
        scene.rootNode.addChildNode(marker)
        c.marker = marker
        let target = SCNNode()
        scene.rootNode.addChildNode(target)
        c.target = target
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 1000
        scene.rootNode.addChildNode(camera)
        c.camera = camera
        view.pointOfView = camera
        if let cameraState {
            Self.restore(cameraState, view: view, coordinator: c)
        } else {
            Self.apply(.fit, view: view, coordinator: c)
        }
    }

    static func restore(_ state: NCCameraState, view: SCNView, coordinator c: Coordinator) {
        guard let camera = c.camera, let target = c.target else { return }
        camera.position = SCNVector3(state.position[0], state.position[1], state.position[2])
        target.position = SCNVector3(state.target[0], state.target[1], state.target[2])
        camera.camera?.usesOrthographicProjection = state.orthographic
        camera.camera?.orthographicScale = state.orthographicScale
        orient(camera, toward: target)
        view.pointOfView = camera
    }

    private static func orient(_ camera: SCNNode, toward target: SCNNode) {
        let look = SCNLookAtConstraint(target: target)
        let offset = simd_normalize(camera.simdPosition - target.simdPosition)
        look.worldUp = abs(offset.z) > 0.99 ? SCNVector3(0, 1, 0) : SCNVector3(0, 0, 1)
        look.isGimbalLockEnabled = true
        camera.constraints = [look]
    }

    private func addLines(_ vertices: [SCNVector3], color: NSColor, to scene: SCNScene) {
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: Array(UInt32(0)..<UInt32(vertices.count)), primitiveType: .line)]
        )
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.diffuse.contents = color
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }

    static func apply(_ action: NCCameraAction, view: SCNView, coordinator c: Coordinator) {
        guard let camera = c.camera, let target = c.target else { return }
        var position = camera.position
        switch action {
        case .fit, .home, .iso:
            target.position = SCNVector3Zero
            position = SCNVector3(15, -18, 15)
            camera.camera?.usesOrthographicProjection = false
        case .top:
            position = SCNVector3(target.position.x, target.position.y, target.position.z + 25)
            camera.camera?.usesOrthographicProjection = true
        case .front:
            position = SCNVector3(target.position.x, target.position.y - 25, target.position.z)
            camera.camera?.usesOrthographicProjection = true
        case .right:
            position = SCNVector3(target.position.x + 25, target.position.y, target.position.z)
            camera.camera?.usesOrthographicProjection = true
        case .zoomIn, .zoomOut:
            let factor: CGFloat = action == .zoomIn ? 0.8 : 1.25
            if camera.camera?.usesOrthographicProjection == true {
                camera.camera?.orthographicScale *= Double(factor)
            } else {
                position = SCNVector3(target.position.x + (position.x - target.position.x) * factor,
                                      target.position.y + (position.y - target.position.y) * factor,
                                      target.position.z + (position.z - target.position.z) * factor)
            }
        case .left, .rotateRight:
            let angle: CGFloat = action == .left ? .pi / 12 : -.pi / 12
            let x = position.x - target.position.x, y = position.y - target.position.y
            position.x = target.position.x + x * cos(angle) - y * sin(angle)
            position.y = target.position.y + x * sin(angle) + y * cos(angle)
        case .panLeft, .panRight, .panUp, .panDown:
            let direction: SCNVector3
            switch action {
            case .panLeft: direction = SCNVector3(-1, 0, 0)
            case .panRight: direction = SCNVector3(1, 0, 0)
            case .panUp: direction = SCNVector3(0, 0, 1)
            default: direction = SCNVector3(0, 0, -1)
            }
            target.position = SCNVector3(target.position.x + direction.x, target.position.y + direction.y, target.position.z + direction.z)
            position = SCNVector3(position.x + direction.x, position.y + direction.y, position.z + direction.z)
        }
        if action == .top || action == .front || action == .right {
            camera.camera?.orthographicScale = 8
        }
        camera.position = position
        orient(camera, toward: target)
        view.pointOfView = camera
    }
}

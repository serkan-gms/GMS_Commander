import SwiftUI
import AppKit

struct NCPreviewView: View {
    @ObservedObject var document: NCDocument
    let close: () -> Void
    @StateObject private var settings = NCPreviewSettings()
    @State private var progress = 0.0
    @State private var playing = false
    @State private var selectedPosition: NCPoint?
    @State private var selectedPositionUnknown = false
    @State private var cameraRequest: NCCameraRequest?
    @State private var showingHelp = false
    @State private var showingToolSettings = false
    @State private var spindleValue = ""
    @State private var feedValue = ""
    @State private var percentValue = ""
    @State private var coolantCode = 8
    @State private var changing = false
    @State private var stats: NCStatistics?
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if document.loading {
                ProgressView(L.t("nc.loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let program = document.program {
                NCPreviewSplitView(
                    left: AnyView(NCCodeEditor(text: $document.text, controller: document.editor, onLineSelected: selectLine)
                        .frame(minWidth: 250, maxHeight: .infinity)),
                    right: AnyView(graphics(program).frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)),
                    settings: settings
                )
                Divider()
                playback(program)
                footer(program)
            } else if let error = document.error {
                Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView(L.t("nc.parsing")).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 850, idealWidth: 1100, minHeight: 600, idealHeight: 750)
        .task { await document.load() }
        .onChange(of: document.text) { _, _ in
            guard !document.loading else { return }
            playing = false
            document.reparse()
        }
        .onChange(of: document.revision) { _, _ in
            guard let program = document.program else { return }
            stats = NCStatistics(program: program)
            if !program.lines.isEmpty {
                document.selectedLine = min(document.selectedLine, program.lines.count - 1)
                let state = program.lines[document.selectedLine]
                progress = Double(state.segmentCount)
                selectedPosition = state.position
                selectedPositionUnknown = state.position == nil
            }
        }
        .onReceive(timer) { _ in
            guard playing, let program = document.program, !document.parsing else { return }
            let step = max(1.0, Double(program.segments.count) / 400) * settings.speed
            setProgress(min(Double(program.segments.count), progress + step), program: program)
            if Int(progress) >= program.segments.count { playing = false }
        }
        .alert(L.t("error.title.generic"), isPresented: Binding(
            get: { document.error != nil && document.program != nil },
            set: { if !$0 { document.error = nil } }
        )) {
            Button(L.t("common.ok")) { document.error = nil }
        } message: {
            Text(document.error ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            Text(document.url.lastPathComponent).font(.headline).lineLimit(1)
            if document.isModified { Text(L.t("editor.modified")).foregroundStyle(.orange).font(.caption) }
            if document.parsing { Text(L.t("nc.parsing")).foregroundStyle(.orange).font(.caption) }
            Spacer()
            Button(L.t("nc.update")) { document.reparse() }
                .disabled(!document.loaded || document.saving)
            Button(L.t("common.save")) { Task { _ = await document.save() } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!document.loaded || document.saving)
            Button(L.t("nc.saveAs")) { Task { _ = await document.saveAs() } }
                .disabled(!document.loaded || document.saving)
            Button(L.t("nc.saveAndClose")) {
                Task {
                    if await document.saveAs() { close() }
                }
            }
            .disabled(!document.loaded || document.saving)
            Button(L.t("common.close"), action: close).keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    private func graphics(_ program: NCProgram) -> some View {
        ZStack(alignment: .topLeading) {
            NCSceneView(
                program: program, revision: document.revision, progress: progress,
                selectedPosition: selectedPosition, positionUnknown: selectedPositionUnknown,
                mode: settings.pathMode, toolMode: settings.toolMode,
                toolColor: settings.toolColor, pointSize: settings.pointSize, toolDiameter: settings.diameter,
                cameraRequest: cameraRequest, settings: settings
            )
            if program.segments.isEmpty {
                Text(L.t("nc.empty"))
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 6) {
                cameraToolbar
                if settings.showingHUD {
                    ScrollView(.vertical) {
                        hud(program)
                    }
                    .frame(maxWidth: 300, maxHeight: 420)
                    .environment(\.colorScheme, .dark)
                }
                Spacer()
            }
            .padding(8)
            VStack {
                Spacer()
                Text(coordinateText(program))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(8)
            .allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    NCViewCube { cameraRequest = NCCameraRequest(action: $0) }
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private var cameraToolbar: some View {
        HStack(spacing: 4) {
            cameraButton("arrow.up.left.and.arrow.down.right", .fit, "nc.camera.fit")
            cameraButton("plus.magnifyingglass", .zoomIn, "nc.camera.zoomIn")
            cameraButton("minus.magnifyingglass", .zoomOut, "nc.camera.zoomOut")
            cameraButton("rotate.left", .left, "nc.camera.left")
            cameraButton("rotate.right", .rotateRight, "nc.camera.right")
            Menu {
                Button(L.t("nc.camera.panLeft")) { cameraRequest = NCCameraRequest(action: .panLeft) }
                Button(L.t("nc.camera.panRight")) { cameraRequest = NCCameraRequest(action: .panRight) }
                Button(L.t("nc.camera.panUp")) { cameraRequest = NCCameraRequest(action: .panUp) }
                Button(L.t("nc.camera.panDown")) { cameraRequest = NCCameraRequest(action: .panDown) }
            } label: { Image(systemName: "hand.draw") }
            .help(L.t("nc.camera.pan"))
            Button { settings.showingHUD.toggle() } label: {
                Image(systemName: settings.showingHUD ? "sidebar.left" : "sidebar.right")
            }
            .help(L.t(settings.showingHUD ? "nc.hud.hide" : "nc.hud.show"))
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func cameraButton(_ symbol: String, _ action: NCCameraAction, _ help: String) -> some View {
        Button { cameraRequest = NCCameraRequest(action: action) } label: {
            Image(systemName: symbol).frame(width: 20, height: 20)
        }
        .help(L.t(help))
    }

    private func hud(_ program: NCProgram) -> some View {
        let line = program.lines.indices.contains(document.selectedLine) ? program.lines[document.selectedLine] : nil
        return VStack(alignment: .leading, spacing: 5) {
            Text(L.t("nc.hud.title")).font(.system(size: 14, weight: .semibold))
            Text(coordinateText(program))
                .monospacedDigit()
            if let stats {
                Text(String(format: "X %.3f … %.3f", stats.min.x, stats.max.x)).monospacedDigit()
                Text(String(format: "Y %.3f … %.3f", stats.min.y, stats.max.y)).monospacedDigit()
                Text(String(format: "Z %.3f … %.3f", stats.min.z, stats.max.z)).monospacedDigit()
                Text(L.t("nc.hud.boundsNote"))
                HStack {
                    Text(L.t("nc.hud.rapid"))
                    TextField("mm/min", text: $settings.rapidValue).textFieldStyle(.roundedBorder)
                }
                Text(stats.durationText(rapid: number(settings.rapidValue)))
            }
            Divider()
            Text("\(L.t("nc.hud.spindle")): \(line?.spindle.map { String(format: "%.0f", $0) } ?? "—")")
            Text("\(L.t("nc.hud.feed")): \(line?.feed.map { String(format: "%.2f mm/min", $0) } ?? "—")")
            Text("\(L.t("nc.hud.coolant")): \(line?.coolant ?? "—")")
            HStack {
                TextField(L.t("nc.hud.spindle"), text: $spindleValue).textFieldStyle(.roundedBorder)
                Button(L.t("nc.apply")) { applyNumeric(.spindle(number(spindleValue) ?? .nan)) }.disabled(changing)
            }
            HStack {
                TextField(L.t("nc.hud.feed"), text: $feedValue).textFieldStyle(.roundedBorder)
                Button(L.t("nc.apply")) { applyNumeric(.feed(number(feedValue) ?? .nan)) }.disabled(changing)
            }
            HStack {
                Button("−10%") { applyNumeric(.feedPercent(-10)) }.disabled(changing)
                Button("+10%") { applyNumeric(.feedPercent(10)) }.disabled(changing)
                TextField("%", text: $percentValue).textFieldStyle(.roundedBorder)
                Button(L.t("nc.apply")) { applyNumeric(.feedPercent(number(percentValue) ?? .nan)) }.disabled(changing)
            }
            Picker(L.t("nc.hud.coolant"), selection: $coolantCode) {
                Text("M7").tag(7)
                Text("M8").tag(8)
                Text("M9").tag(9)
            }
            HStack {
                Button(L.t("nc.insert")) { editCoolant(insert: true) }.disabled(changing)
                Button(L.t("nc.remove")) { editCoolant(insert: false) }.disabled(changing)
            }
            Text(L.t("nc.coolantNote"))
                .foregroundStyle(.orange)
        }
        .font(.system(size: 12))
        .padding(8)
        .foregroundStyle(.white)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 0.96)), in: RoundedRectangle(cornerRadius: 7))
    }

    private func playback(_ program: NCProgram) -> some View {
        HStack(spacing: 8) {
            Button(L.t(playing ? "nc.pause" : "nc.play")) {
                if Int(progress) >= program.segments.count { setProgress(0, program: program) }
                playing.toggle()
            }
            .disabled(program.segments.isEmpty || document.parsing)
            Picker(L.t("nc.speed"), selection: $settings.speed) {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { speed in
                    Text("\(speed, specifier: "%g")×").tag(speed)
                }
            }
            .labelsHidden()
            .frame(width: 80)
            .help(L.t("nc.speed"))
            Slider(value: Binding(get: { progress }, set: {
                playing = false
                setProgress($0, program: program)
            }), in: 0...Double(max(program.segments.count, 1)))
            .disabled(program.segments.isEmpty || document.parsing)
            Text("\(Int(progress)) / \(program.segments.count)").font(.caption.monospacedDigit())
            Button(L.t("nc.reset")) { playing = false; setProgress(0, program: program) }
                .disabled(program.segments.isEmpty || document.parsing)
            Picker("", selection: $settings.pathMode) {
                ForEach(NCPathMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 185)
            Button(L.t("nc.tool.settings")) { showingToolSettings.toggle() }
                .popover(isPresented: $showingToolSettings) { toolSettings }
            Button(L.t("nc.help")) { showingHelp.toggle() }
                .popover(isPresented: $showingHelp) {
                    Text(L.t("nc.help.body")).padding().frame(width: 360, alignment: .leading)
                }
        }
        .padding(8)
    }

    private var toolSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L.t("nc.tool.mode"), selection: $settings.toolMode) {
                ForEach(NCToolMode.allCases) { Text($0.title).tag($0) }
            }
            ColorPicker(L.t("nc.tool.color"), selection: Binding(
                get: { settings.toolColor },
                set: { if !settings.setToolColor($0) { document.error = L.t("nc.tool.colorError") } }
            ))
            HStack {
                Text(L.t("nc.tool.pointSize"))
                Slider(value: $settings.pointSize, in: 4...40)
            }
            HStack {
                Text(L.t("nc.tool.diameter"))
                TextField("", value: $settings.diameter, format: .number)
                    .frame(width: 80)
            }
            Text(L.t("nc.tool.note")).font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(width: 300)
    }

    private func footer(_ program: NCProgram) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L.t("nc.disclaimer"))
            if !program.warnings.isEmpty {
                Text(program.warnings.map(\.localizedMessage).joined(separator: " "))
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    private func selectLine(_ line: Int) {
        document.selectedLine = line
        guard !document.parsing, let program = document.program, program.lines.indices.contains(line) else { return }
        playing = false
        let state = program.lines[line]
        progress = Double(state.segmentCount)
        selectedPosition = state.position
        selectedPositionUnknown = state.position == nil
    }

    private func setProgress(_ value: Double, program: NCProgram) {
        progress = value
        selectedPosition = nil
        selectedPositionUnknown = false
        guard !program.segments.isEmpty else { return }
        let index = min(max(Int(value), 0), program.segments.count - 1)
        let line = program.segments[index].line
        if line != document.selectedLine {
            document.selectedLine = line
            document.editor.selectLine(line)
        }
    }

    private func currentPosition(_ program: NCProgram) -> NCPoint? {
        guard !program.segments.isEmpty else { return nil }
        let index = min(max(Int(progress), 0), program.segments.count - 1)
        let segment = program.segments[index]
        let fraction = progress >= Double(program.segments.count) ? 1 : progress - Double(index)
        return NCPoint(
            x: segment.start.x + (segment.end.x - segment.start.x) * fraction,
            y: segment.start.y + (segment.end.y - segment.start.y) * fraction,
            z: segment.start.z + (segment.end.z - segment.start.z) * fraction
        )
    }

    private func coordinateText(_ program: NCProgram) -> String {
        let point = selectedPositionUnknown ? nil : (selectedPosition ?? currentPosition(program))
        return Self.coordinateText(point)
    }

    static func coordinateText(_ point: NCPoint?) -> String {
        return point.map { String(format: "X %.3f  Y %.3f  Z %.3f", $0.x, $0.y, $0.z) } ?? L.t("nc.hud.unknown")
    }

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func confirmChange() -> Bool {
        let alert = NSAlert()
        alert.messageText = L.t("nc.tools.confirmTitle")
        alert.informativeText = L.t("nc.tools.confirmMessage")
        alert.addButton(withTitle: L.t("nc.apply"))
        alert.addButton(withTitle: L.t("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applyNumeric(_ change: NCCodeTools.Change) {
        let fallback: (@Sendable (String) throws -> String)?
        if case .spindle = change {
            fallback = { try NCCodeTools.change($0, change, assumeSpindleRPM: true) }
        } else {
            fallback = nil
        }
        applyChange({ try NCCodeTools.change($0, change) }, spindleFallback: fallback)
    }

    private func editCoolant(insert: Bool) {
        let line = document.selectedLine
        let code = coolantCode
        applyChange({ try NCCodeTools.changeCoolant($0, line: line, code: code, insert: insert) })
    }

    private func applyChange(
        _ transform: @escaping @Sendable (String) throws -> String,
        spindleFallback: (@Sendable (String) throws -> String)? = nil
    ) {
        guard !changing else { return }
        changing = true
        let snapshot = document.text
        Task {
            defer { changing = false }
            do {
                let result: String
                do {
                    result = try await Task.detached(priority: .userInitiated) { try transform(snapshot) }.value
                } catch NCCodeToolError.spindleModeUnknown {
                    guard let spindleFallback else { throw NCCodeToolError.spindleModeUnknown }
                    guard document.text == snapshot else {
                        document.error = L.t("nc.tools.textChanged")
                        return
                    }
                    let alert = NSAlert()
                    alert.messageText = L.t("nc.tools.spindleConfirmTitle")
                    alert.informativeText = L.t("nc.tools.spindleConfirmMessage")
                    alert.addButton(withTitle: L.t("nc.tools.spindleConfirm"))
                    alert.addButton(withTitle: L.t("common.cancel"))
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                    result = try await Task.detached(priority: .userInitiated) { try spindleFallback(snapshot) }.value
                }
                guard document.text == snapshot else {
                    document.error = L.t("nc.tools.textChanged")
                    return
                }
                guard confirmChange(), document.text == snapshot else { return }
                document.text = result
            } catch { document.error = error.localizedDescription }
        }
    }
}

private struct NCStatistics {
    let min: NCPoint
    let max: NCPoint
    let rapidDistance: Double
    let cuttingMinutes: Double?
    let incomplete: Bool

    init?(program: NCProgram) {
        guard let first = program.segments.first else { return nil }
        var min = first.start, max = first.start
        var rapid = 0.0, cutting = 0.0, known = true
        for segment in program.segments {
            for point in [segment.start, segment.end] {
                min.x = Swift.min(min.x, point.x); max.x = Swift.max(max.x, point.x)
                min.y = Swift.min(min.y, point.y); max.y = Swift.max(max.y, point.y)
                min.z = Swift.min(min.z, point.z); max.z = Swift.max(max.z, point.z)
            }
            let distance = sqrt(pow(segment.end.x - segment.start.x, 2) + pow(segment.end.y - segment.start.y, 2) + pow(segment.end.z - segment.start.z, 2))
            if segment.rapid { rapid += distance }
            else if let feed = segment.feed, feed > 0 { cutting += distance / feed }
            else { known = false }
        }
        self.min = min
        self.max = max
        rapidDistance = rapid
        cuttingMinutes = known ? cutting : nil
        incomplete = !program.warnings.isEmpty
    }

    func durationText(rapid: Double?) -> String {
        guard let cuttingMinutes, let rapid, rapid.isFinite, rapid > 0 else { return L.t("nc.hud.timeUnknown") }
        let minutes = cuttingMinutes + rapidDistance / rapid
        return L.t(incomplete ? "nc.hud.partialTime" : "nc.hud.estimatedTime", String(format: "%.1f", minutes))
    }
}

private struct NCViewCube: View {
    let select: (NCCameraAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                face(.top, title: L.t("nc.camera.top"), color: .gray.opacity(0.35), action: .top)
                face(.front, title: L.t("nc.camera.front"), color: .gray.opacity(0.55), action: .front)
                face(.right, title: L.t("nc.camera.side"), color: .gray.opacity(0.75), action: .right)
            }
            .frame(width: 100, height: 85)
            HStack(spacing: 8) {
                Button(L.t("nc.camera.iso")) { select(.iso) }
                Button { select(.home) } label: { Image(systemName: "house") }
                    .help(L.t("nc.camera.home"))
                    .accessibilityLabel(L.t("nc.camera.home"))
            }
            .controlSize(.small)
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func face(_ side: NCCubeFace.Side, title: String, color: Color, action: NCCameraAction) -> some View {
        Button { select(action) } label: {
            ZStack(alignment: .topLeading) {
                NCCubeFace(side: side).fill(color)
                NCCubeFace(side: side).stroke(.white.opacity(0.9), lineWidth: 1)
                Text(title).font(.caption2.bold()).foregroundStyle(.white)
                    .position(side == .top ? CGPoint(x: 50, y: 20) :
                                side == .front ? CGPoint(x: 27, y: 51) : CGPoint(x: 73, y: 51))
            }
            .frame(width: 100, height: 85)
            .contentShape(NCCubeFace(side: side))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct NCCubeFace: Shape {
    enum Side { case top, front, right }
    let side: Side

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint]
        switch side {
        case .top: points = [.init(x: 50, y: 2), .init(x: 94, y: 22), .init(x: 50, y: 42), .init(x: 6, y: 22)]
        case .front: points = [.init(x: 6, y: 22), .init(x: 50, y: 42), .init(x: 50, y: 82), .init(x: 6, y: 62)]
        case .right: points = [.init(x: 50, y: 42), .init(x: 94, y: 22), .init(x: 94, y: 62), .init(x: 50, y: 82)]
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

import SwiftUI
import AppKit

struct NCPreviewSplitView: NSViewRepresentable {
    let left: AnyView
    let right: AnyView
    let settings: NCPreviewSettings

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NCNativeSplitView {
        let split = NCNativeSplitView(settings: settings)
        split.isVertical = true
        split.dividerStyle = .thin
        let leftHost = NSHostingView(rootView: left)
        let rightHost = NSHostingView(rootView: right)
        split.addArrangedSubview(leftHost)
        split.addArrangedSubview(rightHost)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        context.coordinator.leftHost = leftHost
        context.coordinator.rightHost = rightHost
        return split
    }

    func updateNSView(_ split: NCNativeSplitView, context: Context) {
        context.coordinator.leftHost?.rootView = left
        context.coordinator.rightHost?.rootView = right
    }

    final class Coordinator {
        var leftHost: NSHostingView<AnyView>?
        var rightHost: NSHostingView<AnyView>?
    }
}

final class NCNativeSplitView: NSSplitView, NSSplitViewDelegate {
    private let settings: NCPreviewSettings
    private var restored = false

    init(settings: NCPreviewSettings) {
        self.settings = settings
        super.init(frame: .zero)
        delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        guard !restored, subviews.count == 2, bounds.width >= 670 else { return }
        restored = true
        let maximum = max(250, bounds.width - dividerThickness - 420)
        setPosition(min(max(250, bounds.width * settings.splitRatio), maximum), ofDividerAt: 0)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard restored, bounds.width > 0, let left = subviews.first else { return }
        let ratio = left.frame.width / bounds.width
        if abs(settings.splitRatio - ratio) > 0.0001 {
            settings.splitRatio = ratio
        }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, 250)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width - splitView.dividerThickness - 420)
    }
}

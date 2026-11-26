import SwiftUI
import AppKit

final class NCTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        insertText("\n", replacementRange: selectedRange())
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let value = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        guard let value, value.contains("\n") || value.contains("\r") else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let newline = string.contains("\r\n") ? "\r\n" : "\n"
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: newline)
        super.insertText(normalized, replacementRange: replacementRange)
    }
}

@MainActor
final class NCCodeEditorController {
    weak var textView: NSTextView?
    var lineStarts: [Int] = [0]
    var selecting = false

    func rebuildLines() {
        guard let textView else { return }
        lineStarts = FileViewerService.lineStartOffsets(in: textView.string as NSString)
        if textView.string.hasSuffix("\n") {
            lineStarts.append((textView.string as NSString).length)
        }
    }

    func line(at location: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location { low = mid + 1 } else { high = mid }
        }
        return max(0, low - 1)
    }

    func selectLine(_ line: Int) {
        guard let textView, lineStarts.indices.contains(line) else { return }
        let text = textView.string as NSString
        let start = lineStarts[line]
        let length = line + 1 < lineStarts.count ? lineStarts[line + 1] - start : text.length - start
        selecting = true
        textView.setSelectedRange(NSRange(location: start, length: max(0, length)))
        if let layout = textView.layoutManager, let container = textView.textContainer,
           let scroll = textView.enclosingScrollView {
            let glyph = layout.glyphRange(forCharacterRange: NSRange(location: start, length: max(0, length)), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            let documentHeight = textView.bounds.height
            let height = scroll.contentView.bounds.height
            let y = max(0, min(documentHeight - height, rect.midY + textView.textContainerOrigin.y - height / 2))
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        selecting = false
    }
}

struct NCCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: NCCodeEditorController
    let onLineSelected: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let editor = NCTextView()
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.font = NSFont.monospacedSystemFont(ofSize: CGFloat(max(Appearance.tableFontSize, 11)), weight: .regular)
        editor.textColor = Palette.textPrimary
        editor.backgroundColor = Palette.field
        editor.insertionPointColor = Palette.accent
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = editor.maxSize
        editor.textContainer?.widthTracksTextView = false
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        controller.textView = editor
        controller.rebuildLines()
        let ruler = LineNumberRulerView(textView: editor, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler
        context.coordinator.editor = editor
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.highlightVisible()
        }
        DispatchQueue.main.async { context.coordinator.highlightVisible() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            let selected = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
            controller.rebuildLines()
            context.coordinator.ruler?.rebuildLineStarts()
            context.coordinator.highlightVisible()
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.ruler?.stopObserving()
        coordinator.parent.controller.textView = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NCCodeEditor
        weak var editor: NSTextView?
        weak var ruler: LineNumberRulerView?
        var observer: NSObjectProtocol?
        private let tokenPattern = try! NSRegularExpression(
            pattern: #"\([^)]*\)|;[^\r\n]*|[GMXYZFS]\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)"#,
            options: [.caseInsensitive]
        )

        init(_ parent: NCCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
            parent.controller.rebuildLines()
            ruler?.rebuildLineStarts()
            highlightVisible()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor, !parent.controller.selecting else { return }
            parent.onLineSelected(parent.controller.line(at: editor.selectedRange().location))
        }

        func highlightVisible() {
            guard let editor, let layout = editor.layoutManager,
                  let container = editor.textContainer, let scroll = editor.enclosingScrollView else { return }
            let glyphRange = layout.glyphRange(forBoundingRect: scroll.contentView.bounds, in: container)
            let visible = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let source = editor.string as NSString
            guard visible.location != NSNotFound, NSMaxRange(visible) <= source.length else { return }
            let lineRange = source.lineRange(for: visible)
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: lineRange)
            for match in tokenPattern.matches(in: editor.string, range: lineRange) {
                let token = source.substring(with: match.range).uppercased()
                let color: NSColor
                if token.hasPrefix("(") || token.hasPrefix(";") { color = .systemGreen }
                else if token.hasPrefix("M") { color = .systemPurple }
                else if token.hasPrefix("F") { color = .systemOrange }
                else if token.hasPrefix("S") { color = .systemPink }
                else if token.hasPrefix("G") {
                    let code = Double(token.dropFirst().trimmingCharacters(in: .whitespaces))
                    color = code == 0 ? .systemOrange : (code == 1 ? .systemBlue : .systemTeal)
                } else { color = .systemCyan }
                layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: match.range)
            }
        }
    }
}

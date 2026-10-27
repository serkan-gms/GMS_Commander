//
//  ViewerTextView.swift
//  GMS_Commander
//
//  Görüntüleyici ve düzenleyici için satır numaralı, yatay kaydırılabilir
//  AppKit metin görünümü. Arama vurguları geçici layout öznitelikleriyle
//  çizilir; dosya içeriği değiştirilmez.
//

import SwiftUI
import AppKit

// MARK: - Arama denetleyicisi

/// Görüntüleyici metni üzerinde arama yapan küçük denetleyici.
/// Metin görünümü ile SwiftUI katmanı arasında köprü kurar.
@MainActor
final class ViewerTextController {
    /// Bağlı metin görünümü.
    weak var textView: NSTextView?

    private var matches: [NSRange] = []
    private var currentIndex = -1
    private var currentQuery = ""

    /// Metin görünümünü bağlar.
    func attach(_ textView: NSTextView) {
        self.textView = textView
    }

    /// Aramayı temizler ve vurguları kaldırır.
    func clearSearch() {
        currentQuery = ""
        matches = []
        currentIndex = -1
        clearHighlights()
    }

    /// Arama sorgusunu günceller ve tüm eşleşmeleri vurgular.
    /// - Returns: Eşleşme sayısı.
    @discardableResult
    func updateSearch(_ query: String) -> Int {
        guard let textView else { return 0 }
        currentQuery = query
        clearHighlights()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matches = []
            currentIndex = -1
            return 0
        }

        let text = textView.string as NSString
        var searchRange = NSRange(location: 0, length: text.length)
        var found: [NSRange] = []
        // Çok büyük dosyalarda vurgu sayısını sınırlıyoruz.
        while searchRange.length > 0, found.count < 5000 {
            let range = text.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            if range.location == NSNotFound { break }
            found.append(range)
            let next = NSMaxRange(range)
            if next >= text.length { break }
            searchRange = NSRange(location: next, length: text.length - next)
        }

        matches = found
        currentIndex = found.isEmpty ? -1 : 0
        applyHighlights()
        selectCurrent()
        return found.count
    }

    /// Sonraki eşleşmeye gider.
    /// - Returns: Gösterilen eşleşmenin sırası (1 tabanlı), eşleşme yoksa 0.
    @discardableResult
    func findNext() -> Int {
        guard !matches.isEmpty else { return 0 }
        currentIndex = (currentIndex + 1) % matches.count
        selectCurrent()
        return currentIndex + 1
    }

    /// Önceki eşleşmeye gider.
    /// - Returns: Gösterilen eşleşmenin sırası (1 tabanlı), eşleşme yoksa 0.
    @discardableResult
    func findPrevious() -> Int {
        guard !matches.isEmpty else { return 0 }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        selectCurrent()
        return currentIndex + 1
    }

    /// Eşleşme sayısı.
    var matchCount: Int { matches.count }

    /// Seçili metni döndürür (düzenleyicide kullanılmaz).
    var selectedText: String {
        guard let textView, textView.selectedRange().length > 0 else { return "" }
        return (textView.string as NSString).substring(with: textView.selectedRange())
    }

    private func selectCurrent() {
        guard let textView, matches.indices.contains(currentIndex) else { return }
        let range = matches[currentIndex]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func clearHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        textView.needsDisplay = true
    }

    private func applyHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        for range in matches {
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                forCharacterRange: range
            )
        }
        textView.needsDisplay = true
    }
}

// MARK: - Metin görünümü

/// Satır numaralı, salt okunur veya düzenlenebilir metin görünümü.
struct ViewerTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let showLineNumbers: Bool
    let controller: ViewerTextController
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.field

        let textView = NSTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(
            ofSize: CGFloat(max(Appearance.tableFontSize, 11)),
            weight: .regular
        )
        textView.textColor = Palette.textPrimary
        textView.backgroundColor = Palette.field
        textView.insertionPointColor = Palette.accent
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        controller.attach(textView)

        let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        context.coordinator.ruler = ruler

        if isEditable {
            // Düzenleyici açıldığında imleç metnin başında ve odakta olsun.
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.ruler?.rebuildLineStarts()
            controller.clearSearch()
        }
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        context.coordinator.ruler?.rebuildLineStartsIfNeeded()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.ruler?.stopObserving()
        coordinator.textView = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ViewerTextView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(_ parent: ViewerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let value = textView.string
            if parent.text != value {
                parent.text = value
            }
            ruler?.rebuildLineStarts()
            parent.onTextChange?()
        }
    }
}

// MARK: - Satır numarası cetveli

/// Metin görünümünün solunda satır numaralarını çizen cetvel.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var observer: NSObjectProtocol?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        ruleThickness = 42

        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        rebuildLineStarts()
    }

    required init(coder: NSCoder) {
        fatalError("LineNumberRulerView programatik olarak oluşturulur.")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Gözlemciyi kaldırır.
    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Satır başlangıçlarını yeniden hesaplar.
    func rebuildLineStarts() {
        guard let textView else { return }
        let text = textView.string as NSString
        lineStarts = FileViewerService.lineStartOffsets(in: text)
        lastRebuiltLength = text.length
        updateThickness()
        needsDisplay = true
    }

    private var lastRebuiltLength = -1

    /// Metin uzunluğu değiştiyse yeniden hesaplar.
    func rebuildLineStartsIfNeeded() {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        if length != lastRebuiltLength {
            lastRebuiltLength = length
            rebuildLineStarts()
        }
    }

    private func updateThickness() {
        let digits = max(String(max(lineStarts.count, 1)).count, 3)
        ruleThickness = CGFloat(digits * 7 + 14)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView else { return }

        // Cetvel zemini
        Palette.header.setFill()
        bounds.fill()

        let relativePoint = convert(NSZeroPoint, from: textView)
        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else { return }

        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        var lineIndex = lineIndex(for: characterRange.location)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: max(Appearance.tableFontSize - 2, 9),
                weight: .regular
            ),
            .foregroundColor: Palette.textSecondary
        ]

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange
            )
            let y = relativePoint.y + lineRect.minY + textView.textContainerOrigin.y
            let number = String(lineIndex + 1) as NSString
            let size = number.size(withAttributes: attributes)
            let x = ruleThickness - size.width - 7
            number.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)

            glyphIndex = NSMaxRange(lineGlyphRange)
            lineIndex += 1
            if lineGlyphRange.length == 0 { break }
        }
    }

    /// Verilen karakter indeksinin bulunduğu satır numarasını (0 tabanlı) bulur.
    private func lineIndex(for location: Int) -> Int {
        guard !lineStarts.isEmpty else { return 0 }
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] == location {
                return mid
            } else if lineStarts[mid] < location {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return max(0, min(low - 1, lineStarts.count - 1))
    }
}

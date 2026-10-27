//
//  QuickLookService.swift
//  GMS_Commander
//
//  Seçili dosyaların hızlı önizlemesini (Quick Look) yönetir.
//  Boşluk tuşuyla açılır/kapanır; seçim değiştiğinde içerik güncellenir.
//

import AppKit
import QuickLookUI

/// Quick Look panelini yöneten koordinatör.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// Uygulama genelinde tek örnek.
    static let shared = QuickLookCoordinator()

    /// Önizlenecek dosyalar.
    private var previewURLs: [URL] = []

    /// Önizleme panelinin görünür olup olmadığı.
    var isVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else {
            return false
        }
        return panel.isVisible
    }

    private override init() {
        super.init()
    }

    /// Verilen dosyaları önizler. Panel görünürse içerik güncellenir.
    /// - Parameter urls: Önizlenecek dosya adresleri.
    func preview(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        previewURLs = urls

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self

        if panel.isVisible {
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Önizlemeyi açar veya kapatır.
    /// - Parameter urls: Seçili dosyalar.
    func toggle(_ urls: [URL]) {
        if isVisible {
            close()
        } else {
            preview(urls)
        }
    }

    /// Önizlemeyi görünür tutarak verilen seçimle günceller.
    func show(_ urls: [URL]) {
        preview(urls)
    }

    /// Önizlemeyi kapatır.
    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else {
            return
        }
        panel.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Klavye olaylarını panelin kendi kısayollarına bırakıyoruz.
        false
    }
}

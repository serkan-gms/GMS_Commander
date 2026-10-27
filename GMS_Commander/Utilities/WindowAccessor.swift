//
//  WindowAccessor.swift
//  GMS_Commander
//
//  SwiftUI görünümünün bağlı olduğu AppKit penceresine erişmek için küçük
//  yardımcı. Pencereye bağlanınca yapılandırma kapanışı yalnızca bir kez
//  çalıştırılır.
//

import SwiftUI
import AppKit

/// Bağlandığı pencerede tek seferlik yapılandırma çalıştırır.
struct WindowAccessor: NSViewRepresentable {
    /// Pencere bulunduğunda çalıştırılacak kapanış.
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        nsView.configure = configure
        nsView.applyIfNeeded()
    }

    /// Pencereye bağlanmayı bekleyen görünüm.
    final class WindowProbeView: NSView {
        var configure: ((NSWindow) -> Void)?
        private var configuredWindow: ObjectIdentifier?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIfNeeded()
        }

        /// Pencere henüz yapılandırılmadıysa kapanışı çalıştırır.
        func applyIfNeeded() {
            guard let window, let configure else { return }
            let identifier = ObjectIdentifier(window)
            guard configuredWindow != identifier else { return }
            configuredWindow = identifier
            configure(window)
        }
    }
}

/// Ana pencerenin açılışta ekranın ortasına yerleşmesini sağlar.
@MainActor
enum MainWindowPlacement {
    private static var didPlace = false

    /// Yalnızca uygulama açılışında ilk ana pencereyi ortalar.
    /// - Parameter window: Yerleştirilecek pencere.
    static func centerIfNeeded(_ window: NSWindow) {
        guard !didPlace else { return }
        didPlace = true
        // SwiftUI ilk yerleşimi tamamladıktan sonra ortalamak için bir tur bekliyoruz.
        DispatchQueue.main.async {
            window.center()
        }
    }
}

/// Sheet penceresini kullanıcı tarafından yeniden boyutlandırılabilir yapar.
@MainActor
enum SheetWindowConfiguration {
    /// Pencereyi yeniden boyutlandırılabilir hâle getirir.
    /// - Parameters:
    ///   - window: Sheet penceresi.
    ///   - minimumContentSize: İçerik için izin verilen en küçük boyut.
    static func makeResizable(
        _ window: NSWindow,
        minimumContentSize: NSSize
    ) {
        window.styleMask.insert(.resizable)
        window.contentMinSize = minimumContentSize
    }
}

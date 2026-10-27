//
//  KeyboardShortcutManager.swift
//  GMS_Commander
//
//  Uygulamadaki klavye kısayollarının tek kaynaktan tanımlandığı katalog.
//  Yardım ekranı bu katalogdan beslenir; menüler ise aynı eylemleri
//  `MenuCommands` içinde `.keyboardShortcut` ile bağlar.
//

import Foundation
import AppKit

/// Kullanıcıya gösterilen klavye kısayolları.
enum KeyboardShortcutManager {
    /// Tek bir kısayol kaydı.
    struct Shortcut: Identifiable, Hashable {
        /// Tuş birleşiminin görünen adı, ör. "⌘C".
        let keys: String

        /// `Localizable.strings` içindeki eylem anahtarı.
        let titleKey: String

        var id: String { "\(keys)|\(titleKey)" }

        /// Eylemin Türkçe adı.
        var title: String { L.t(titleKey) }
    }

    /// Yardım ekranında listelenen kısayollar (görünen sırayla).
    static let all: [Shortcut] = [
        Shortcut(keys: "⌘C", titleKey: "menu.edit.copy"),
        Shortcut(keys: "⌘X", titleKey: "menu.edit.cut"),
        Shortcut(keys: "⌘V", titleKey: "menu.edit.paste"),
        Shortcut(keys: "⌘A", titleKey: "menu.edit.selectAll"),
        Shortcut(keys: "⌘F", titleKey: "menu.view.search"),
        Shortcut(keys: "⌥⌘F", titleKey: "menu.view.advancedSearch"),
        Shortcut(keys: "⌥⌘K", titleKey: "menu.tools.folderCompare"),
        Shortcut(keys: "⌘R", titleKey: "menu.view.refresh"),
        Shortcut(keys: "⌘O", titleKey: "menu.file.open"),
        Shortcut(keys: "⌘Y", titleKey: "menu.file.quickLook"),
        Shortcut(keys: "Space", titleKey: "menu.file.quickLook"),
        Shortcut(keys: "Return", titleKey: "menu.file.open"),
        Shortcut(keys: "⌘⌫", titleKey: "menu.file.trash"),
        Shortcut(keys: "⌥⌘⌫", titleKey: "menu.file.deletePermanently"),
        Shortcut(keys: "⌘⇧N", titleKey: "menu.file.newFolder"),
        Shortcut(keys: "⌥⌘R", titleKey: "menu.edit.batchRename"),
        Shortcut(keys: "⇧⌘A", titleKey: "menu.edit.selectPattern"),
        Shortcut(keys: "⇧⌘I", titleKey: "menu.edit.invertSelection"),
        Shortcut(keys: "Tab", titleKey: "menu.view.switchPanel"),
        Shortcut(keys: "⌘[", titleKey: "toolbar.back"),
        Shortcut(keys: "⌘]", titleKey: "toolbar.forward"),
        Shortcut(keys: "⌘↑", titleKey: "toolbar.up"),
        Shortcut(keys: "⌫", titleKey: "toolbar.up"),
        Shortcut(keys: "⌘I", titleKey: "menu.tools.properties"),
        Shortcut(keys: "⌥⌘H", titleKey: "menu.tools.hash"),
        Shortcut(keys: "⌃`", titleKey: "menu.tools.openTerminal"),
        Shortcut(keys: "⌘⇧.", titleKey: "menu.file.showHidden"),
        Shortcut(keys: "F3", titleKey: "fkey.view"),
        Shortcut(keys: "F4", titleKey: "fkey.edit"),
        Shortcut(keys: "F5", titleKey: "fkey.copy"),
        Shortcut(keys: "F6", titleKey: "fkey.move"),
        Shortcut(keys: "F7", titleKey: "fkey.newFolder"),
        Shortcut(keys: "F8", titleKey: "fkey.delete"),
        Shortcut(keys: "F9", titleKey: "fkey.terminal"),
        Shortcut(keys: "F10", titleKey: "fkey.quit"),
        Shortcut(keys: "F11", titleKey: "fkey.compress")
    ]

    /// Menü kısayolu olmayan, yalın tuşlarla çalışan eylemler.
    enum BareKeyAction: Equatable {
        /// Boşluk: hızlı önizleme.
        case quickLook
        /// Return: aç / klasöre gir.
        case open
        /// Backspace: üst klasöre geç.
        case goUp
        /// Tab: etkin paneli değiştir (Norton Commander geleneği).
        case switchPanel
    }

    /// Atanabilir işlev tuşları (F1–F12).
    enum FunctionKey: String, CaseIterable, Identifiable, Hashable {
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

        var id: String { rawValue }

        /// Kullanıcıya gösterilen ad, ör. "F5".
        var label: String { rawValue.uppercased() }

        /// macOS sanal tuş kodu.
        var keyCode: UInt16 {
            switch self {
            case .f1: return 122
            case .f2: return 120
            case .f3: return 99
            case .f4: return 118
            case .f5: return 96
            case .f6: return 97
            case .f7: return 98
            case .f8: return 100
            case .f9: return 101
            case .f10: return 109
            case .f11: return 103
            case .f12: return 111
            }
        }

        /// Tuş kodundan işlev tuşunu bulur.
        static func from(keyCode: UInt16) -> FunctionKey? {
            allCases.first { $0.keyCode == keyCode }
        }
    }

    /// Kullanıcının işlev tuşu atamaları. Varsayılan Norton Commander düzenidir.
    struct FunctionKeyBindings: Equatable {
        /// Eylem → tuş eşlemesi.
        private(set) var keys: [FunctionKeyAction: FunctionKey]

        /// Varsayılan atamalar (F3–F11).
        static let `default` = FunctionKeyBindings(keys: [
            .view: .f3,
            .edit: .f4,
            .copy: .f5,
            .move: .f6,
            .newFolder: .f7,
            .delete: .f8,
            .terminal: .f9,
            .quit: .f10,
            .compress: .f11
        ])

        init(keys: [FunctionKeyAction: FunctionKey]) {
            self.keys = keys
        }

        /// Kayıtlı sözlükten okur; eksik veya geçersiz kayıtlar varsayılana döner.
        /// Aynı tuşun birden çok eyleme atanması durumunda sonraki eylem
        /// varsayılan tuşuna geri alınır.
        init(dictionary: [String: String]) {
            var resolved = Self.default.keys
            for action in FunctionKeyAction.allCases {
                guard let raw = dictionary[action.rawValue],
                      let key = FunctionKey(rawValue: raw.lowercased()) else { continue }
                resolved[action] = key
            }

            var used = Set<FunctionKey>()
            for action in FunctionKeyAction.allCases {
                let key = resolved[action] ?? Self.default.keys[action]!
                if used.contains(key), let fallback = Self.default.keys[action],
                   !used.contains(fallback) {
                    resolved[action] = fallback
                } else {
                    resolved[action] = key
                }
                used.insert(resolved[action]!)
            }
            self.keys = resolved
        }

        /// UserDefaults'a yazılacak sözlük.
        var dictionary: [String: String] {
            Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value.rawValue) })
        }

        /// Eylemin tuşu.
        func key(for action: FunctionKeyAction) -> FunctionKey {
            keys[action] ?? Self.default.keys[action] ?? .f3
        }

        /// Tuşa atanmış eylem.
        func action(for key: FunctionKey) -> FunctionKeyAction? {
            FunctionKeyAction.allCases.first { keys[$0] == key || (keys[$0] == nil && Self.default.keys[$0] == key) }
        }

        /// Tuş koduna atanmış eylem.
        func action(forKeyCode keyCode: UInt16) -> FunctionKeyAction? {
            guard let key = FunctionKey.from(keyCode: keyCode) else { return nil }
            return action(for: key)
        }

        /// Eylemin görünen tuş etiketi.
        func label(for action: FunctionKeyAction) -> String {
            key(for: action).label
        }
    }

    /// Norton Commander düzenindeki işlev tuşu eylemleri.
    enum FunctionKeyAction: String, CaseIterable, Identifiable, Equatable {
        /// F3 — hızlı önizleme.
        case view
        /// F4 — dahili metin düzenleyici.
        case edit
        /// F5 — diğer panele kopyala.
        case copy
        /// F6 — diğer panele taşı.
        case move
        /// F7 — yeni klasör.
        case newFolder
        /// F8 — çöp kutusuna taşı.
        case delete
        /// F9 — Terminali aç.
        case terminal
        /// F10 — çıkış.
        case quit
        /// F11 — seçili öğeleri sıkıştır.
        case compress

        var id: String { rawValue }

        /// Varsayılan rozet tuş adı, ör. "F5". Kullanıcı ataması varsa
        /// `FunctionKeyBindings.label(for:)` kullanılmalıdır.
        var keyLabel: String {
            switch self {
            case .view: return "F3"
            case .edit: return "F4"
            case .copy: return "F5"
            case .move: return "F6"
            case .newFolder: return "F7"
            case .delete: return "F8"
            case .terminal: return "F9"
            case .quit: return "F10"
            case .compress: return "F11"
            }
        }

        /// Türkçe eylem adı.
        var title: String { L.t("fkey.\(rawValue)") }
    }

    /// Yönlendiriciye teslim edilen klavye komutu.
    enum KeyCommand: Equatable {
        case bare(BareKeyAction)
        case function(FunctionKeyAction)
    }

    /// Yalın tuş olayını eyleme çevirir. Değiştirici tuş basılıysa `nil` döner.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> BareKeyAction? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        // Tab (ve Shift+Tab) panel değiştirir; metin düzenlenirken yutulmaz.
        if keyCode == 48 {
            let allowed: NSEvent.ModifierFlags = [.shift]
            guard flags.subtracting(allowed).isEmpty else { return nil }
            return .switchPanel
        }

        guard flags.isEmpty else { return nil }

        switch keyCode {
        case 49: return .quickLook      // Space
        case 36, 76: return .open       // Return, Enter
        case 51: return .goUp           // Delete (Backspace)
        default: return nil
        }
    }

    /// İlk yanıtlayıcı bir metin alanıysa (arama, adres çubuğu, yeniden adlandırma)
    /// yalın tuşlar yazıya gitmelidir.
    static func isTextEditing() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSText { return true }
        if let textField = responder as? NSTextField, textField.isEditable { return true }
        return false
    }

    /// İşlev tuşu (F3…F10) kodunu eyleme çevirir. Değiştirici tuş basılıysa `nil` döner.
    static func functionKeyAction(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        bindings: FunctionKeyBindings = .default
    ) -> FunctionKeyAction? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        guard flags.isEmpty else { return nil }
        return bindings.action(forKeyCode: keyCode)
    }

    /// Tuş kodunu (ve değiştiricileri) yönlendirilecek komuta çevirir.
    ///
    /// İşlev tuşları metin düzenlenirken de çalışır; yalın tuşlar çalışmaz.
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        bindings: FunctionKeyBindings = .default
    ) -> KeyCommand? {
        if let function = functionKeyAction(keyCode: keyCode, modifiers: modifiers, bindings: bindings) {
            return .function(function)
        }
        if let bare = action(keyCode: keyCode, modifiers: modifiers) {
            return .bare(bare)
        }
        return nil
    }
}

/// Yalın tuşları (Space, Return, Backspace) ve işlev tuşlarını uygulama
/// eylemlerine yönlendiren yerel olay izleyicisi.
@MainActor
final class KeyboardEventRouter {
    private var monitor: Any?

    /// İzleyiciyi kurar. `handler` olayı işlediyse `true` döner ve tuş yutulur.
    /// - Parameters:
    ///   - bindings: Kullanıcının işlev tuşu atamaları.
    ///   - handler: Komutu işleyen kapanış.
    func start(
        bindings: KeyboardShortcutManager.FunctionKeyBindings = .default,
        handler: @escaping @MainActor (KeyboardShortcutManager.KeyCommand) -> Bool
    ) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let handled = MainActor.assumeIsolated {
                guard let command = KeyboardShortcutManager.command(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    bindings: bindings
                ) else {
                    return false
                }
                if case .bare = command, KeyboardShortcutManager.isTextEditing() {
                    return false
                }
                return handler(command)
            }
            return handled ? nil : event
        }
    }

    /// İzleyiciyi kaldırır.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

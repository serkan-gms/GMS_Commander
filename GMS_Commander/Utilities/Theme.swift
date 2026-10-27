//
//  Theme.swift
//  GMS_Commander
//
//  Çoklu tema ve yazı tipi ölçeği altyapısı.
//  Hem AppKit (NSTableView) hem SwiftUI katmanı aynı paleti ve aynı yazı
//  boyutlarını kullanır. Etkin palet `Appearance` üzerinde tutulur; `ThemeManager`
//  kullanıcı tercihini UserDefaults'ta saklar ve `Appearance`'ı günceller.
//

import SwiftUI
import AppKit

// MARK: - Tema kimliği

/// Seçilebilir temalar.
enum ThemeID: String, CaseIterable, Identifiable, Sendable {
    /// Modern koyu tema (Void Commander esintili).
    case voidCommander
    /// Klasik Norton Commander mavisi.
    case nortonCommander
    /// Nötr koyu gri.
    case graphite
    /// Açık gri tema (Cmdır esintili).
    case daylight
    /// Solarized koyu paleti.
    case solarizedDark
    /// Yüksek kontrastlı koyu tema (erişilebilirlik).
    case highContrast

    var id: String { rawValue }

    /// Türkçe görünen ad.
    var localizedName: String { L.t("theme.\(rawValue)") }

    /// Kısa açıklama.
    var localizedSummary: String { L.t("theme.\(rawValue).summary") }

    /// Açık zeminli tema mı?
    var isLight: Bool { self == .daylight }
}

// MARK: - Palet

/// Bir temanın tüm renkleri. `NSColor` tabanlıdır; SwiftUI katmanı `Theme`
/// üzerinden `Color` karşılıklarını kullanır.
struct ThemeSpec {
    let themeID: ThemeID
    /// Pencere zemini (en koyu katman).
    let window: NSColor
    /// Etkin olmayan panel zemini.
    let panel: NSColor
    /// Etkin panel zemini.
    let panelActive: NSColor
    /// Panel başlığı ve sütun başlığı.
    let header: NSColor
    /// Durum çubuğu ve işlev tuşu şeridi.
    let statusBar: NSColor
    /// İnce ayırıcı çizgiler.
    let border: NSColor
    /// Ana metin.
    let textPrimary: NSColor
    /// İkincil metin (boyut, tarih, ipuçları).
    let textSecondary: NSColor
    /// Klasör adları.
    let folder: NSColor
    /// Vurgu rengi (etkin panel çerçevesi, işlev tuşu rozetleri).
    let accent: NSColor
    /// Arama alanı zemini.
    let field: NSColor
    /// İşlev tuşu rozet zemini.
    let keyChip: NSColor
}

extension ThemeSpec {
    /// 0xRRGGBB biçimindeki onaltılık değeri renge çevirir.
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    /// Kimliğe karşılık gelen palet.
    static func make(_ id: ThemeID) -> ThemeSpec {
        switch id {
        case .voidCommander:
            return ThemeSpec(
                themeID: id,
                window: rgb(0x0A0D14),
                panel: rgb(0x101620),
                panelActive: rgb(0x141C29),
                header: rgb(0x1B2534),
                statusBar: rgb(0x0B1018),
                border: rgb(0x2A3444),
                textPrimary: rgb(0xEAF0F7),
                textSecondary: rgb(0x8B98AC),
                folder: rgb(0x93C5FD),
                accent: rgb(0x8B5CF6),
                field: rgb(0x0A0F18),
                keyChip: rgb(0x223047)
            )
        case .nortonCommander:
            return ThemeSpec(
                themeID: id,
                window: rgb(0x00005A),
                panel: rgb(0x000080),
                panelActive: rgb(0x0000A0),
                header: rgb(0x000070),
                statusBar: rgb(0x00005A),
                border: rgb(0x00A8A8),
                textPrimary: rgb(0xD8E4E4),
                textSecondary: rgb(0x8AB8C8),
                folder: rgb(0xFFFF55),
                accent: rgb(0x00D7D7),
                field: rgb(0x000060),
                keyChip: rgb(0x005A8C)
            )
        case .graphite:
            return ThemeSpec(
                themeID: id,
                window: rgb(0x1A1A1C),
                panel: rgb(0x212124),
                panelActive: rgb(0x28282C),
                header: rgb(0x303034),
                statusBar: rgb(0x1C1C1F),
                border: rgb(0x3C3C42),
                textPrimary: rgb(0xE7E7EA),
                textSecondary: rgb(0x9A9AA2),
                folder: rgb(0x9BE38A),
                accent: rgb(0x4ADE80),
                field: rgb(0x191919),
                keyChip: rgb(0x3A3A40)
            )
        case .daylight:
            return ThemeSpec(
                themeID: id,
                window: rgb(0xEFF1F4),
                panel: rgb(0xFFFFFF),
                panelActive: rgb(0xF7F9FC),
                header: rgb(0xE9EDF3),
                statusBar: rgb(0xF4F6F9),
                border: rgb(0xCFD6DF),
                textPrimary: rgb(0x1F2328),
                textSecondary: rgb(0x66707C),
                folder: rgb(0x1F5FBF),
                accent: rgb(0x2563EB),
                field: rgb(0xFFFFFF),
                keyChip: rgb(0xE4E9F0)
            )
        case .solarizedDark:
            return ThemeSpec(
                themeID: id,
                window: rgb(0x002B36),
                panel: rgb(0x073642),
                panelActive: rgb(0x0B4350),
                header: rgb(0x04303B),
                statusBar: rgb(0x001F27),
                border: rgb(0x2A5360),
                textPrimary: rgb(0xEEE8D5),
                textSecondary: rgb(0x93A1A1),
                folder: rgb(0xB58900),
                accent: rgb(0x268BD2),
                field: rgb(0x00252E),
                keyChip: rgb(0x1C4E5A)
            )
        case .highContrast:
            return ThemeSpec(
                themeID: id,
                window: rgb(0x000000),
                panel: rgb(0x000000),
                panelActive: rgb(0x0A0A0A),
                header: rgb(0x000000),
                statusBar: rgb(0x000000),
                border: rgb(0xFFFFFF),
                textPrimary: rgb(0xFFFFFF),
                textSecondary: rgb(0xFFD700),
                folder: rgb(0x00FFFF),
                accent: rgb(0xFFFF00),
                field: rgb(0x000000),
                keyChip: rgb(0x333333)
            )
        }
    }
}

// MARK: - Etkin görünüm

/// Süreç genelinde etkin palet ve yazı tipi ölçeği.
/// `ThemeManager` tarafından güncellenir; görünümler doğrudan buradan okur.
enum Appearance {
    /// Etkin palet.
    static var spec: ThemeSpec = ThemeSpec.make(.voidCommander)

    /// Liste ve arayüz yazılarının taban boyutu (punto).
    static var fontSize: Double = ThemeManager.defaultFontSize

    /// Liste satır yüksekliği.
    static var rowHeight: CGFloat {
        max(18, (fontSize * 1.55).rounded())
    }

    /// Dosya listesi yazı boyutu.
    static var tableFontSize: CGFloat {
        CGFloat(fontSize)
    }

    /// Panel alt bilgisi ve durum çubuğu yazı boyutu.
    static var secondaryFontSize: CGFloat {
        CGFloat(max(fontSize - 1.5, 9))
    }

    /// İşlev tuşu şeridi yazı boyutu.
    static var keyFontSize: CGFloat {
        CGFloat(max(fontSize - 0.5, 9))
    }

    /// Liste için sabit genişlikli yazı tipi.
    static func mono(_ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: tableFontSize, weight: weight)
    }

    /// Sütun başlığı yazı tipi.
    static var headerFont: NSFont {
        NSFont.systemFont(ofSize: max(tableFontSize - 1.5, 9), weight: .semibold)
    }

    /// Satır simgesi kenar uzunluğu.
    static var iconSize: CGFloat {
        max(16, tableFontSize + 4)
    }
}

/// `Appearance.spec` renklerinin AppKit kısayolları.
/// Adlar tarihsel nedenlerle `Palette` altında korunmuştur.
enum Palette {
    static var window: NSColor { Appearance.spec.window }
    static var panel: NSColor { Appearance.spec.panel }
    static var panelActive: NSColor { Appearance.spec.panelActive }
    static var header: NSColor { Appearance.spec.header }
    static var statusBar: NSColor { Appearance.spec.statusBar }
    static var border: NSColor { Appearance.spec.border }
    static var textPrimary: NSColor { Appearance.spec.textPrimary }
    static var textSecondary: NSColor { Appearance.spec.textSecondary }
    static var folder: NSColor { Appearance.spec.folder }
    static var accent: NSColor { Appearance.spec.accent }
    static var field: NSColor { Appearance.spec.field }
    static var keyChip: NSColor { Appearance.spec.keyChip }

    /// 0xRRGGBB biçimindeki onaltılık değeri renge çevirir.
    static func rgb(_ hex: UInt32) -> NSColor { ThemeSpec.rgb(hex) }
}

/// `Palette` renklerinin ve yazı tiplerinin SwiftUI karşılıkları.
enum Theme {
    static var window: Color { Color(nsColor: Palette.window) }
    static var panel: Color { Color(nsColor: Palette.panel) }
    static var panelActive: Color { Color(nsColor: Palette.panelActive) }
    static var header: Color { Color(nsColor: Palette.header) }
    static var statusBar: Color { Color(nsColor: Palette.statusBar) }
    static var border: Color { Color(nsColor: Palette.border) }
    static var textPrimary: Color { Color(nsColor: Palette.textPrimary) }
    static var textSecondary: Color { Color(nsColor: Palette.textSecondary) }
    static var folder: Color { Color(nsColor: Palette.folder) }
    static var accent: Color { Color(nsColor: Palette.accent) }
    static var field: Color { Color(nsColor: Palette.field) }
    static var keyChip: Color { Color(nsColor: Palette.keyChip) }

    /// Küçük, sabit genişlikli sayı yazı tipi.
    static var monoSmall: Font {
        .system(size: Appearance.secondaryFontSize, design: .monospaced)
    }

    /// Liste yazı tipi.
    static var monoList: Font {
        .system(size: Appearance.tableFontSize, design: .monospaced)
    }

    /// Panel yolu ve arama alanı yazı tipi.
    static var monoControl: Font {
        .system(size: max(Appearance.tableFontSize - 1, 9), design: .monospaced)
    }

    /// Genel arayüz yazı tipi.
    static var label: Font {
        .system(size: Appearance.keyFontSize)
    }

    /// İşlev tuşu rozeti yazı tipi.
    static var keyChipFont: Font {
        .system(size: max(Appearance.keyFontSize - 1.5, 8), weight: .bold, design: .monospaced)
    }
}

// MARK: - Tema yöneticisi

/// Tema ve yazı tipi ölçeği tercihini saklar.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// Seçilebilir yazı boyutu aralığı.
    static let fontSizeRange: ClosedRange<Double> = 10...20
    /// Varsayılan yazı boyutu.
    static let defaultFontSize: Double = 13

    /// UserDefaults anahtarları.
    enum Keys {
        static let themeID = "settings.themeID"
        static let fontSize = "settings.fontSize"
        static let functionKeyFontSize = "settings.functionKeyFontSize"
        static let functionKeyButtonScale = "settings.functionKeyButtonScale"
    }

    private let defaults: UserDefaults

    /// Seçili tema.
    @Published var themeID: ThemeID {
        didSet {
            guard themeID != oldValue else { return }
            defaults.set(themeID.rawValue, forKey: Keys.themeID)
            apply()
        }
    }

    /// Yazı boyutu (punto).
    @Published var fontSize: Double {
        didSet {
            let clamped = Self.clampFontSize(fontSize)
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            guard fontSize != oldValue else { return }
            defaults.set(fontSize, forKey: Keys.fontSize)
            apply()
        }
    }

    /// Alt işlev çubuğundaki etiketlerin yazı boyutu.
    @Published var functionKeyFontSize: Double {
        didSet {
            let clamped = Self.clampFunctionKeyFontSize(functionKeyFontSize)
            if clamped != functionKeyFontSize {
                functionKeyFontSize = clamped
                return
            }
            guard functionKeyFontSize != oldValue else { return }
            defaults.set(functionKeyFontSize, forKey: Keys.functionKeyFontSize)
        }
    }

    /// İşlev tuşu düğmelerinin genel ölçeği.
    @Published var functionKeyButtonScale: Double {
        didSet {
            let clamped = Self.clampFunctionKeyButtonScale(functionKeyButtonScale)
            if clamped != functionKeyButtonScale {
                functionKeyButtonScale = clamped
                return
            }
            guard functionKeyButtonScale != oldValue else { return }
            defaults.set(functionKeyButtonScale, forKey: Keys.functionKeyButtonScale)
        }
    }

    /// - Parameter defaults: Testlerde özel bir UserDefaults enjekte etmek için.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTheme = defaults.string(forKey: Keys.themeID) ?? ""
        self.themeID = ThemeID(rawValue: storedTheme) ?? .voidCommander
        let storedFontSize = defaults.object(forKey: Keys.fontSize) as? Double
        self.fontSize = Self.clampFontSize(storedFontSize ?? Self.defaultFontSize)
        self.functionKeyFontSize = Self.clampFunctionKeyFontSize(
            defaults.object(forKey: Keys.functionKeyFontSize) as? Double ?? 13
        )
        self.functionKeyButtonScale = Self.clampFunctionKeyButtonScale(
            defaults.object(forKey: Keys.functionKeyButtonScale) as? Double ?? 1
        )
        apply()
    }

    /// Etkin palet.
    var spec: ThemeSpec { Appearance.spec }

    /// Yazı boyutunu geçerli aralığa sıkıştırır.
    static func clampFontSize(_ value: Double) -> Double {
        min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    static func clampFunctionKeyFontSize(_ value: Double) -> Double {
        min(max(value, 9), 20)
    }

    static func clampFunctionKeyButtonScale(_ value: Double) -> Double {
        min(max(value, 0.8), 1.5)
    }

    /// Yazı boyutunu varsayılana döndürür.
    func resetFontSize() {
        fontSize = Self.defaultFontSize
    }

    /// Etkin temayı `Appearance`'a uygular.
    func apply() {
        Appearance.spec = ThemeSpec.make(themeID)
        Appearance.fontSize = Self.clampFontSize(fontSize)
    }
}

// MARK: - Görünüm imzası

/// Tema ve yazı boyutu değişimini AppKit tabanlı görünümlere bildirmek için
/// kullanılan küçük imza. `Equatable` olduğu için `updateNSView` içinde
/// karşılaştırılabilir; değişmediğinde gereksiz yeniden kurulum yapılmaz.
struct AppearanceSignature: Equatable {
    let themeID: ThemeID
    let fontSize: Double

    init(themeID: ThemeID, fontSize: Double) {
        self.themeID = themeID
        self.fontSize = fontSize
    }
}

extension ThemeManager {
    /// Etkin görünüm imzası.
    var signature: AppearanceSignature {
        AppearanceSignature(themeID: themeID, fontSize: fontSize)
    }
}

extension AppearanceSignature {
    /// Süreç genelindeki etkin imza.
    static var current: AppearanceSignature {
        AppearanceSignature(themeID: Appearance.spec.themeID, fontSize: Appearance.fontSize)
    }
}

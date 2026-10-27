//
//  FileOperationViewModel.swift
//  GMS_Commander
//
//  İlerleme göstergesinin görünen metinlerini üretir. Görünüm katmanı
//  biçimlendirme yapmaz; tüm değerler bu sunucudan gelir.
//

import Foundation

/// `OperationProgress` verisini ilerleme çubuğunun metinlerine dönüştüren sunucu.
struct FileOperationViewModel: Equatable {
    /// Gösterilecek işlem ilerlemesi.
    let progress: OperationProgress

    /// Ölçülen aktarım hızı (bayt/saniye). Bilinmiyorsa 0.
    let bytesPerSecond: Double

    init(progress: OperationProgress, bytesPerSecond: Double = 0) {
        self.progress = progress
        self.bytesPerSecond = bytesPerSecond
    }

    /// İşlem türünün Türkçe adı ("Kopyalanıyor", "Taşınıyor"…).
    var title: String {
        progress.kind.localizedTitle
    }

    /// İşlenmekte olan öğenin adı.
    var currentItemName: String {
        progress.currentItemName
    }

    /// 0...1 arasındaki ilerleme oranı.
    var fraction: Double {
        progress.fraction
    }

    /// Yüzde metni, ör. "%42".
    var percentText: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Toplam boyut bilinmiyorsa bayt metni gösterilmez.
    var showsByteCount: Bool {
        progress.totalBytes > 0
    }

    /// "1,2 MB / 4,8 MB" biçimindeki boyut metni.
    var byteCountText: String {
        let completed = FileSizeFormatter.string(fromBytes: progress.completedBytes)
        let total = FileSizeFormatter.string(fromBytes: progress.totalBytes)
        return "\(completed) / \(total)"
    }

    /// Aktarım hızı metni ("12,4 MB/sn"). Hız ölçülemiyorsa `nil`.
    var speedText: String? {
        guard bytesPerSecond >= 1024 else { return nil }
        let value = FileSizeFormatter.string(fromBytes: Int64(bytesPerSecond))
        return L.t("operation.speed", value)
    }

    /// Kalan süre tahmini ("~1 dk 20 sn"). Hesaplanamıyorsa `nil`.
    var remainingTimeText: String? {
        guard bytesPerSecond >= 1024,
              progress.totalBytes > progress.completedBytes else { return nil }
        let remaining = Double(progress.totalBytes - progress.completedBytes) / bytesPerSecond
        guard remaining.isFinite, remaining >= 1, remaining < 86_400 * 30 else { return nil }
        let seconds = Int(remaining.rounded())
        if seconds < 60 {
            return L.t("operation.remainingSeconds", seconds)
        }
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes < 60 {
            return L.t("operation.remainingMinutes", minutes, rest)
        }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        return L.t("operation.remainingHours", hours, restMinutes)
    }
}

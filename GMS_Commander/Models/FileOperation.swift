//
//  FileOperation.swift
//  GMS_Commander
//
//  Uzun süren dosya işlemlerinin (kopyalama, taşıma, çöp kutusu) ortak veri tipleri.
//  İlerleme bilgisi, çakışma kararları ve işlem sonuçları burada tanımlanır.
//

import Foundation

/// Yapılan dosya işleminin türü.
enum OperationKind: String, Sendable {
    case copy
    case move
    case trash
    case delete

    /// İşlemin Türkçe adı.
    var localizedTitle: String {
        switch self {
        case .copy: return L.t("operation.copy")
        case .move: return L.t("operation.move")
        case .trash: return L.t("operation.trash")
        case .delete: return L.t("operation.delete")
        }
    }
}

/// İlerleme çubuğunu besleyen anlık işlem bilgisi.
struct OperationProgress: Equatable, Sendable {
    let kind: OperationKind

    /// Şu anda işlenen öğenin adı.
    var currentItemName: String

    /// Tamamlanan öğe sayısı.
    var completedItems: Int

    /// Toplam öğe sayısı.
    var totalItems: Int

    /// Tamamlanan bayt miktarı.
    var completedBytes: Int64

    /// Toplam bayt miktarı (0 ise yüzde bilinmiyor demektir).
    var totalBytes: Int64

    /// 0...1 arasında ilerleme oranı; toplam boyut bilinmiyorsa öğe sayısına göre hesaplanır.
    var fraction: Double {
        if totalBytes > 0 {
            return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
        }
        if totalItems > 0 {
            return min(max(Double(completedItems) / Double(totalItems), 0), 1)
        }
        return 0
    }
}

/// Başarısız olan tek bir öğe ve Türkçe hata açıklaması.
struct FileOperationFailure: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let message: String

    init(url: URL, message: String) {
        self.id = UUID()
        self.url = url
        self.message = message
    }
}

/// Bir işlemin sonucu.
struct OperationResult: Sendable {
    let kind: OperationKind
    let completedCount: Int
    let failures: [FileOperationFailure]
    let wasCancelled: Bool

    var isSuccess: Bool {
        failures.isEmpty && !wasCancelled
    }

    static func empty(_ kind: OperationKind) -> OperationResult {
        OperationResult(kind: kind, completedCount: 0, failures: [], wasCancelled: false)
    }
}

/// Kopyalama/taşıma planındaki tek bir öğe.
struct CopyPlanItem: Sendable {
    let source: URL
    let destination: URL
    let overwrite: Bool
}

/// Çakışma durumunda kullanıcının verdiği karar.
enum ConflictDecision: String, Sendable {
    /// Hedefin üzerine yaz.
    case overwrite
    /// Bu öğeyi atla.
    case skip
    /// Her iki dosyayı da koru; hedefe yeni bir ad ver.
    case keepBoth
    /// Tüm işlemi iptal et.
    case cancel
}

/// Çakışmalarda izlenecek genel politika (Ayarlar ekranından seçilir).
enum ConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case ask
    case overwrite
    case skip
    case keepBoth

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .ask: return L.t("settings.conflict.ask")
        case .overwrite: return L.t("settings.conflict.overwrite")
        case .skip: return L.t("settings.conflict.skip")
        case .keepBoth: return L.t("settings.conflict.keepBoth")
        }
    }

    /// Kullanıcıya sorulmadan uygulanabilecek karar. `ask` için `nil`.
    var automaticDecision: ConflictDecision? {
        switch self {
        case .ask: return nil
        case .overwrite: return .overwrite
        case .skip: return .skip
        case .keepBoth: return .keepBoth
        }
    }
}

/// Kopyala/taşı yönü. Pano ve panel arası aktarımda kullanılır.
enum TransferMode: Sendable, Equatable {
    case copy
    case move

    var operationKind: OperationKind {
        switch self {
        case .copy: return .copy
        case .move: return .move
        }
    }
}

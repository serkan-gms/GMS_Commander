//
//  TransferControl.swift
//  GMS_Commander
//
//  Dosya kopyalama/taşıma işlemlerinin duraklatılması, sürdürülmesi ve iptal
//  edilmesi için iş parçacığı güvenli denetim nesnesi.
//
//  Servisler her dosya parçası ve her öğe başında `waitIfPaused()` çağırır.
//  Böylece işlem, arayüzü kilitlemeden güvenli bir noktada bekletilebilir.
//

import Foundation

/// Kopyalama/taşıma işleminin akışını denetleyen iş parçacığı güvenli sınıf.
final class TransferControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var cancelled = false

    init() {}

    /// İşlemi duraklatır. Devam eden parça tamamlandıktan sonra bekleme başlar.
    func pause() {
        condition.lock()
        paused = true
        condition.unlock()
    }

    /// Duraklatılmış işlemi sürdürür.
    func resume() {
        condition.lock()
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    /// İşlemi iptal eder. Bekleyen işlem varsa hemen uyanır.
    func cancel() {
        condition.lock()
        cancelled = true
        paused = false
        condition.broadcast()
        condition.unlock()
    }

    /// İşlem duraklatılmış mı?
    var isPaused: Bool {
        condition.lock()
        defer { condition.unlock() }
        return paused
    }

    /// İşlem iptal edilmiş mi?
    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    /// İptal edildiyse `CancellationError` fırlatır.
    func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }

    /// İşlem duraklatılmışsa sürdürülene veya iptal edilene kadar bekler.
    /// - Throws: İptal edildiyse `CancellationError`.
    func waitIfPaused() throws {
        try Task.checkCancellation()

        condition.lock()
        defer { condition.unlock() }
        while paused && !cancelled {
            condition.wait()
        }
        if cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

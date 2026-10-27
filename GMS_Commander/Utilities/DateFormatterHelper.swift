//
//  DateFormatterHelper.swift
//  GMS_Commander
//
//  Dosya tarihlerini Türkçe yerelleştirme ile gösteren yardımcı.
//  Liste görünümü ve özellikler penceresi aynı biçimlendiricileri kullanır.
//

import Foundation

/// Tarihleri Türkçe biçimde metne çeviren yardımcı.
enum DateFormatterHelper {
    /// Dosya listesinde kullanılan kısa biçim: "12 Eki 2025 14:32".
    private static let listFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM y HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    /// Özellikler penceresinde kullanılan ayrıntılı biçim.
    private static let detailedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.timeZone = .current
        return formatter
    }()

    /// Liste sütununda gösterilecek metin.
    static func listString(from date: Date?) -> String {
        guard let date else { return "—" }
        return listFormatter.string(from: date)
    }

    /// Özellikler ekranında gösterilecek metin.
    static func detailedString(from date: Date?) -> String {
        guard let date else { return "—" }
        return detailedFormatter.string(from: date)
    }
}

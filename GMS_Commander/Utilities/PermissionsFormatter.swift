//
//  PermissionsFormatter.swift
//  GMS_Commander
//
//  POSIX dosya izinlerini "rwxr-xr-x" biçiminde göstermeye yarayan yardımcı.
//

import Foundation

/// Dosya izinlerini okunabilir metne çeviren yardımcı.
enum PermissionsFormatter {
    /// Üç bitlik izin gruplarını temsil eden metinler (0...7).
    private static let triplets = ["---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"]

    /// Sayısal izin maskesini (ör. 0o755) "rwxr-xr-x" biçimine çevirir.
    /// - Parameter mode: POSIX izin bitleri.
    static func symbolicString(fromMode mode: Int) -> String {
        let owner = (mode >> 6) & 0b111
        let group = (mode >> 3) & 0b111
        let other = mode & 0b111
        return triplets[owner] + triplets[group] + triplets[other]
    }

    /// İzin maskesini sekizlik metne çevirir (ör. "755").
    static func octalString(fromMode mode: Int) -> String {
        String(format: "%03o", mode & 0o777)
    }
}

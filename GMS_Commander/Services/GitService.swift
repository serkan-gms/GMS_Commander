//
//  GitService.swift
//  GMS_Commander
//
//  Görüntülenen klasörün Git deposu olup olmadığını ve dal/Değişiklik durumunu
//  sorgular. Komut satırı `git` aracı yoksa sessizce "depo değil" sonucu döner.
//

import Foundation

/// Bir klasörün Git durumu.
struct GitStatus: Sendable, Equatable {
    enum State: String, Sendable {
        case notRepository
        case clean
        case modified
        case conflicted
        case unknown

        var localizedTitle: String {
            switch self {
            case .notRepository: return L.t("git.notRepository")
            case .clean: return L.t("git.clean")
            case .modified: return L.t("git.modified")
            case .conflicted: return L.t("git.conflicted")
            case .unknown: return L.t("git.unknown")
            }
        }
    }

    var state: State = .notRepository
    var branch: String?
    var repositoryRoot: URL?
    var changedFileCount: Int = 0
    var isRepository: Bool { state != .notRepository }
}

/// Git bilgisi sağlayan servis.
struct GitService: Sendable {
    /// `git` çalıştırılabilir dosyasının yolu.
    private static let gitExecutable = "/usr/bin/git"

    /// Klasörün Git durumunu asenkron olarak sorgular.
    func status(for url: URL) async -> GitStatus {
        await Task.detached(priority: .utility) {
            Self.statusSync(for: url)
        }.value
    }

    /// Git durumunun eşzamanlı çekirdeği (birim testlerinde doğrudan çağrılır).
    static func statusSync(for url: URL) -> GitStatus {
        guard FileManager.default.isExecutableFile(atPath: gitExecutable) else {
            return GitStatus()
        }
        guard let root = repositoryRoot(for: url) else {
            return GitStatus()
        }

        var status = GitStatus(state: .unknown, branch: nil, repositoryRoot: root, changedFileCount: 0)

        if let branchOutput = runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: root) {
            let branch = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            status.branch = branch.isEmpty ? nil : branch
        }

        guard let porcelain = runGit(["status", "--porcelain"], in: root) else {
            return status
        }

        let lines = porcelain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        status.changedFileCount = lines.count

        if lines.contains(where: { $0.hasPrefix("UU") || $0.hasPrefix("AA") || $0.hasPrefix("DD") }) {
            status.state = .conflicted
        } else if lines.isEmpty {
            status.state = .clean
        } else {
            status.state = .modified
        }

        return status
    }

    /// Verilen klasörden yukarı doğru ilerleyerek `.git` dizinini arar.
    /// - Parameter url: Başlangıç klasörü.
    /// - Returns: Depo kökü; bulunamazsa `nil`.
    static func repositoryRoot(for url: URL) -> URL? {
        let fileManager = FileManager.default
        var current = url.standardizedFileURL

        while current.path != "/" {
            let gitPath = current.appendingPathComponent(".git").path
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitPath, isDirectory: &isDirectory) {
                return current
            }
            current = current.deletingLastPathComponent()
        }

        return nil
    }

    /// Git komutunu çalıştırıp standart çıktısını döndürür.
    private static func runGit(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitExecutable)
        process.arguments = ["-C", directory.path] + arguments

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

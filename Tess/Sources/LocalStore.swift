import Foundation

/// Failed reads must never turn into silent overwrites of the user's local files.
final class LocalStore {
    enum Read<Value> {
        case missing, value(Value), unreadable
    }

    let directory: URL
    var recoveryDirectory: URL { directory.appendingPathComponent("Recovery", isDirectory: true) }
    private(set) var unreadableNames: Set<String> = []
    private(set) var failedWrites: Set<String> = []
    private(set) var hasRecoveryFiles: Bool

    init(directory: URL) {
        self.directory = directory
        let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
        hasRecoveryFiles = ((try? FileManager.default.contentsOfDirectory(atPath: recovery.path)) ?? []).contains { $0.hasSuffix(".json") }
    }

    func read<T: Decodable>(_ type: T.Type, name: String) -> Read<T> {
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return .value(try JSONDecoder().decode(type, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            unreadableNames.insert(name)
            return .unreadable
        }
    }

    func write<T: Encodable>(_ value: T, name: String) throws {
        do {
            let data = try JSONEncoder().encode(value)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if unreadableNames.contains(name) { try preserveUnreadableFile(name) }
            let file = directory.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            failedWrites.remove(name)
        } catch {
            failedWrites.insert(name)
            throw error
        }
    }

    // Screenshot cleanup belongs after both reference files are safely stored.
    func writeResults<T: Encodable>(recent: T, draft: T, cleanup: () -> Void) -> Bool {
        var saved = true
        for (name, value) in [("recent.json", recent), ("draft.json", draft)] {
            do { try write(value, name: name) }
            catch { saved = false }
        }
        guard saved else { return false }
        cleanup()
        return true
    }

    private func preserveUnreadableFile(_ name: String) throws {
        let original = directory.appendingPathComponent(name)
        // Reading or preserving the original may fail too. In that case write() must stop.
        let data = try Data(contentsOf: original)
        _ = try preserve(data, name: name)
        unreadableNames.remove(name)
    }

    func recoveryCopy<T: Encodable>(_ value: T, name: String) throws -> URL {
        try preserve(JSONEncoder().encode(value), name: name)
    }

    func discardRecoveryCopy(_ file: URL) throws {
        guard file.deletingLastPathComponent() == recoveryDirectory else { return }
        try FileManager.default.removeItem(at: file)
        hasRecoveryFiles = ((try? FileManager.default.contentsOfDirectory(atPath: recoveryDirectory.path)) ?? []).contains { $0.hasSuffix(".json") }
    }

    private func preserve(_ data: Data, name: String) throws -> URL {
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let backup = recoveryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: backup, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        guard try Data(contentsOf: backup) == data else { throw CocoaError(.fileWriteUnknown) }
        hasRecoveryFiles = true
        return backup
    }
}

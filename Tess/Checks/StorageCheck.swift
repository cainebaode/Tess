import Foundation

@main @MainActor struct StorageCheck {
    struct Value: Codable, Equatable { var text: String }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Tess-storage-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)

        guard case .missing = store.read(Value.self, name: "missing.json") else { preconditionFailure("Missing is distinct from unreadable") }
        try store.write(Optional<Value>.none, name: "empty.json")
        guard case .value(nil) = store.read(Value?.self, name: "empty.json") else { preconditionFailure("A saved empty result is valid") }
        precondition(store.unreadableNames.isEmpty && !store.hasRecoveryFiles)

        let broken = Data("{ unfinished local draft".utf8)
        let draft = directory.appendingPathComponent("draft.json")
        try broken.write(to: draft)
        guard case .unreadable = store.read(Value?.self, name: "draft.json") else { preconditionFailure("Malformed data must surface a read failure") }
        let unchangedAfterRead = try Data(contentsOf: draft)
        precondition(unchangedAfterRead == broken)

        // If preserving the source is impossible, an attempted save cannot replace it.
        let blockedRecovery = directory.appendingPathComponent("Recovery")
        try Data("blocked recovery folder".utf8).write(to: blockedRecovery)
        do {
            try store.write(Value(text: "replacement"), name: "draft.json")
            preconditionFailure("The write must fail when recovery cannot be created")
        } catch {}
        let unchangedAfterFailure = try Data(contentsOf: draft)
        precondition(unchangedAfterFailure == broken)
        precondition(store.failedWrites.contains("draft.json") && store.unreadableNames.contains("draft.json"))

        try FileManager.default.removeItem(at: blockedRecovery)
        try store.write(Value(text: "replacement"), name: "draft.json")
        let backups = try FileManager.default.contentsOfDirectory(at: store.recoveryDirectory, includingPropertiesForKeys: nil)
        precondition(backups.count == 1)
        let backupData = try Data(contentsOf: backups[0])
        precondition(backupData == broken)
        precondition(store.failedWrites.isEmpty && store.unreadableNames.isEmpty && store.hasRecoveryFiles)
        guard case .value(Value(text: "replacement")) = store.read(Value.self, name: "draft.json") else { preconditionFailure("Retry should persist the current result") }
        try store.write(Value(text: "later"), name: "draft.json")
        let laterBackups = try FileManager.default.contentsOfDirectory(atPath: store.recoveryDirectory.path)
        precondition(laterBackups.count == 1)
        precondition(LocalStore(directory: directory).hasRecoveryFiles)

        // Use the same two-file commit boundary as AppModel's deferred screenshot cleanup.
        let pairDirectory = directory.appendingPathComponent("paired-results", isDirectory: true)
        let pairStore = LocalStore(directory: pairDirectory)
        try FileManager.default.createDirectory(at: pairDirectory, withIntermediateDirectories: true)
        let oldImage = pairDirectory.appendingPathComponent("old-image.png")
        try Data("isolated image fixture".utf8).write(to: oldImage)
        let blockedDraft = pairDirectory.appendingPathComponent("draft.json", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedDraft, withIntermediateDirectories: true)
        let failedPair = pairStore.writeResults(recent: Value(text: "new recent"), draft: Value(text: "new draft")) {
            try! FileManager.default.removeItem(at: oldImage)
        }
        precondition(!failedPair && FileManager.default.fileExists(atPath: oldImage.path))
        try FileManager.default.removeItem(at: blockedDraft)
        let retriedPair = pairStore.writeResults(recent: Value(text: "new recent"), draft: Value(text: "new draft")) {
            try! FileManager.default.removeItem(at: oldImage)
        }
        precondition(retriedPair && !FileManager.default.fileExists(atPath: oldImage.path))

        // A filesystem read error is not an empty result and cannot be overwritten.
        let unreadable = directory.appendingPathComponent("unreadable.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        guard case .unreadable = store.read(Value.self, name: "unreadable.json") else { preconditionFailure("A read error must surface") }
        do { try store.write(Value(text: "replacement"), name: "unreadable.json"); preconditionFailure("Unreadable source cannot be overwritten") } catch {}
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: unreadable.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        // Real API configuration storage uses the same preservation boundary; no key is read or written.
        let apiFile = directory.appendingPathComponent("api-configurations.json")
        let apiBroken = Data("not valid configuration JSON".utf8)
        try apiBroken.write(to: apiFile)
        let configurations = APIConfigurationStore(storageDirectory: directory, credentialService: "com.caine.Tess.check-unused")
        precondition(configurations.lastError != nil && configurations.hasUnreadableFiles)
        var configuration = APIConfiguration()
        configuration.name = "Isolated configuration"
        configuration.baseURL = "http://127.0.0.1:11434/v1"
        configuration.modelID = "isolated-no-network"
        configuration.allowsUnauthenticatedLocal = true
        precondition(configurations.save(configuration))
        precondition(configurations.hasRecoveryFiles && !configurations.hasUnreadableFiles)
        let apiBackup = try FileManager.default.contentsOfDirectory(at: store.recoveryDirectory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasSuffix("-api-configurations.json") }!
        let apiBackupData = try Data(contentsOf: apiBackup)
        precondition(apiBackupData == apiBroken)
        precondition(APIConfigurationStore(storageDirectory: directory).configurations.count == 1)

        // Inject only credential deletion, so failure cases never touch the real Keychain.
        let credentialID = UUID()
        func deletionFixture(_ label: String) throws -> URL {
            let folder = directory.appendingPathComponent(label, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as! [String: Any]
            encoded["credentialID"] = credentialID.uuidString
            encoded["credentialOrigin"] = "http://127.0.0.1:11434"
            let data = try JSONSerialization.data(withJSONObject: ["configurations": [encoded], "currentID": configuration.id.uuidString])
            try data.write(to: folder.appendingPathComponent("api-configurations.json"))
            return folder
        }
        let successFolder = try deletionFixture("delete-success")
        var deletionCalls = 0
        let successStore = APIConfigurationStore(storageDirectory: successFolder, credentialRemover: { id in
            precondition(id == credentialID)
            deletionCalls += 1
        })
        precondition(successStore.delete(configuration.id) && deletionCalls == 1)
        precondition(successStore.configurations.isEmpty && !successStore.hasRecoveryFiles)
        precondition(APIConfigurationStore(storageDirectory: successFolder).configurations.isEmpty)

        let failureFolder = try deletionFixture("delete-key-failure")
        let failureStore = APIConfigurationStore(storageDirectory: failureFolder, credentialRemover: { _ in throw CocoaError(.fileWriteUnknown) })
        precondition(!failureStore.delete(configuration.id) && failureStore.configurations.count == 1)
        precondition(!failureStore.hasRecoveryFiles)
        let restored = APIConfigurationStore(storageDirectory: failureFolder)
        precondition(restored.current?.credentialID == credentialID)

        let rollbackFolder = try deletionFixture("delete-rollback-failure")
        let rollbackFile = rollbackFolder.appendingPathComponent("api-configurations.json")
        let rollbackStore = APIConfigurationStore(storageDirectory: rollbackFolder, credentialRemover: { _ in
            try FileManager.default.removeItem(at: rollbackFile)
            try FileManager.default.createDirectory(at: rollbackFile, withIntermediateDirectories: true)
            throw CocoaError(.fileWriteUnknown)
        })
        precondition(!rollbackStore.delete(configuration.id))
        precondition(rollbackStore.current?.credentialID == credentialID && rollbackStore.hasRecoveryFiles && rollbackStore.lastError != nil)
        let rollbackCopies = try FileManager.default.contentsOfDirectory(at: rollbackFolder.appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        let rollbackJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: rollbackCopies[0])) as! [String: Any]
        let recoveredConfigurations = rollbackJSON["configurations"] as! [[String: Any]]
        precondition(recoveredConfigurations[0]["credentialID"] as? String == credentialID.uuidString)
        try FileManager.default.removeItem(at: rollbackFile)
        precondition(rollbackStore.retryLocalSave())
        precondition(APIConfigurationStore(storageDirectory: rollbackFolder).current?.credentialID == credentialID)

        let saveFailureFolder = try deletionFixture("delete-save-failure")
        var prematureDeletion = false
        let saveFailureStore = APIConfigurationStore(storageDirectory: saveFailureFolder, credentialRemover: { _ in prematureDeletion = true })
        let saveFailureFile = saveFailureFolder.appendingPathComponent("api-configurations.json")
        try FileManager.default.removeItem(at: saveFailureFile)
        try FileManager.default.createDirectory(at: saveFailureFile, withIntermediateDirectories: true)
        precondition(!saveFailureStore.delete(configuration.id) && !prematureDeletion)
        precondition(saveFailureStore.current?.credentialID == credentialID && saveFailureStore.hasRecoveryFiles)
        print("Storage checks passed: missing/null/read failure, blocked recovery, byte-preserving backup, retry, restart notice, deferred screenshot cleanup, API recovery and credential deletion rollback. Only isolated temporary files and a fake credential remover used; no real keys, microphone, clipboard or network.")
    }
}

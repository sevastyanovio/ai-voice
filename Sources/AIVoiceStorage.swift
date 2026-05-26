import Foundation

enum AIVoiceStorage {
    private static let appFolderName = "AIVoice"

    static var appDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appFolderName, isDirectory: true)
        ensureProtectedDirectory(dir)
        return dir
    }

    static var audioDirectory: URL {
        let dir = appDirectory.appendingPathComponent("audio", isDirectory: true)
        ensureProtectedDirectory(dir)
        return dir
    }

    static var recordingStagingDirectory: URL {
        let dir = appDirectory.appendingPathComponent("recording-staging", isDirectory: true)
        ensureProtectedDirectory(dir)
        return dir
    }

    static func ensureProtectedDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func protectFile(at url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func writeProtected(_ data: Data, to url: URL) throws {
        ensureProtectedDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        protectFile(at: url)
    }
}

// NuDefndr - nudefndr.com
// Transparency Repository - Lock Screen camera inbox (v2.6.9)

import Foundation
import LockedCameraCapture

protocol LockedCaptureSource: Sendable {
    func sessionDirectories() -> [URL]
    func release(_ directory: URL) async
}

struct SystemLockedCaptureSource: LockedCaptureSource {
    func sessionDirectories() -> [URL] {
        LockedCameraCaptureManager.shared.sessionContentURLs
    }

    func release(_ directory: URL) async {
        do {
            try await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory)
        } catch {
            AppLogger.vault.debug("Lock Screen capture: could not release a session: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum LockedCaptureInbox {
    struct PendingFile: Sendable {
        enum State: Sendable {
            case readable(LockedCaptureFormat.Header)
            case malformed
            case unreadable
        }
        let url: URL
        let state: State

        var header: LockedCaptureFormat.Header? {
            if case .readable(let header) = state { return header }
            return nil
        }
    }

    static func pendingFiles(in directory: URL) throws -> [PendingFile] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix("." + LockedCaptureFormat.fileExtension) }
            .sorted()
            .map { name in
                let url = directory.appendingPathComponent(name)
                return PendingFile(url: url, state: Self.readState(at: url))
            }
    }

    static let maximumCaptureSize = 64 * 1024 * 1024

    static func readState(at url: URL) -> PendingFile.State {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable }
        defer { try? handle.close() }
        do {
            guard let size = try? handle.seekToEnd(), size > 0, size <= UInt64(maximumCaptureSize) else {
                return .malformed
            }
            try handle.seek(toOffset: 0)
            guard let prefix = try handle.read(upToCount: 128), !prefix.isEmpty else { return .malformed }
            guard let header = try? LockedCaptureFormat.header(of: prefix) else { return .malformed }
            return .readable(header)
        } catch {
            return .unreadable
        }
    }

    static func referencedKeyIDs(in directories: [URL]) -> Set<Data>? {
        var ids = Set<Data>()
        for directory in directories {
            guard let files = try? pendingFiles(in: directory) else { return nil }
            for file in files {
                switch file.state {
                case .readable(let header): ids.insert(header.keyID)
                case .malformed: continue
                case .unreadable: return nil
                }
            }
        }
        return ids
    }

    static func isZeroLength(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue == 0
    }

    @discardableResult
    static func discard(_ url: URL) -> Bool {
        if (try? FileManager.default.removeItem(at: url)) != nil { return true }
        if !FileManager.default.fileExists(atPath: url.path) { return true }
        return (try? Data().write(to: url)) != nil
    }

    static func excludeFromBackup(_ directories: [URL]) {
        for directory in directories {
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
}
